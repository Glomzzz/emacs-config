;;; mail-async.el --- Background msmtp delivery for Message buffers -*- lexical-binding: t; -*-

;; Keep Message's preparation and successful-send housekeeping in Emacs.
;; Only the sendmail subprocess runs asynchronously.  Returning success from
;; the transport before SMTP finishes would prematurely file/delete the draft.

(require 'cl-lib)
(require 'message)
(require 'sendmail)

(cl-defstruct (mail-async--job (:constructor mail-async--make-job))
  source process input log exit status read-only mode-line)

(defvar mail-async/mode nil)
(defvar-local mail-async--job nil)
(defvar mail-async--source nil)
(defvar mail-async--exit nil)
(defvar mail-async--completing nil)

(defun mail-async--guard (&rest _)
  "Refuse destructive compose commands while delivery is pending."
  (when mail-async--job
    (user-error "Mail delivery is pending or already accepted; see M-x mail-async/status")))

(defun mail-async--keep-buffer ()
  "Keep a pending draft alive, including during ordinary Emacs shutdown."
  (if (and mail-async--job
           (eq (mail-async--job-status mail-async--job) 'sending))
      (progn (message "Mail is still sending; keep this draft open") nil)
    t))

(defun mail-async--unlock (job)
  "Restore the compose buffer's editing state after JOB."
  (when (buffer-live-p (mail-async--job-source job))
    (with-current-buffer (mail-async--job-source job)
      (setq buffer-read-only (mail-async--job-read-only job)
            mode-line-process (mail-async--job-mode-line job))
      (remove-hook 'kill-buffer-query-functions #'mail-async--keep-buffer t)
      (remove-hook 'change-major-mode-hook #'mail-async--guard t)
      (force-mode-line-update))))

(defun mail-async/status ()
  "Display the current draft's delivery log without retrying delivery."
  (interactive)
  (if-let* ((log (and mail-async--job (mail-async--job-log mail-async--job)))
           ((buffer-live-p log)))
      (display-buffer log)
    (user-error "No delivery is pending for this buffer; errors remain in *Mail delivery* buffers")))

(defun mail-async/cancel ()
  "Stop this draft's pending transport after an explicit ambiguity warning.
A server might already have accepted a message before a connection is cut;
cancellation is not a recall.  Never retry automatically."
  (interactive)
  (let ((process (and mail-async--job
                      (mail-async--job-process mail-async--job))))
    (unless (and process (process-live-p process))
      (user-error "No SMTP process is running for this draft"))
    (when (yes-or-no-p "Stop sending? SMTP may already have accepted it; check before any retry. ")
      (delete-process process))))

(defun mail-async--report (job text)
  "Record TEXT in JOB's log and show it without changing message contents."
  (unless (buffer-live-p (mail-async--job-log job))
    (setf (mail-async--job-log job) (generate-new-buffer "*Mail delivery*")))
  (with-current-buffer (mail-async--job-log job)
    (goto-char (point-max))
    (insert "\n" text "\n")
    (special-mode))
  (display-buffer (mail-async--job-log job))
  (message "%s" text))

(defun mail-async--sentinel (job process _event)
  "Finish JOB once PROCESS exits, without ever retrying SMTP."
  (when (and (eq (mail-async--job-status job) 'sending)
             (memq (process-status process) '(exit signal)))
    (when (file-exists-p (mail-async--job-input job))
      (delete-file (mail-async--job-input job)))
    (mail-async--unlock job)
    (if (and (eq (process-status process) 'exit)
             (zerop (process-exit-status process)))
        (progn
          (setf (mail-async--job-status job) 'accepted)
          (if (not (buffer-live-p (mail-async--job-source job)))
              (mail-async--report job "SMTP accepted the message, but its draft buffer disappeared; check Sent before doing anything else. Do NOT resend.")
            (with-current-buffer (mail-async--job-source job)
              (condition-case error-data
                  (let ((mail-async--completing job))
                    (unless (funcall (if (mail-async--job-exit job)
                                        #'message-send-and-exit #'message-send))
                      (error "Message did not finish its local success actions"))
                    (setf (mail-async--job-status job) 'done)
                    (when (buffer-live-p (mail-async--job-source job))
                      (with-current-buffer (mail-async--job-source job)
                        (setq mail-async--job nil)))
                    (when (buffer-live-p (mail-async--job-log job))
                      (kill-buffer (mail-async--job-log job)))
                    (message "SMTP accepted the message; Sent filing completed"))
                (error
                 ;; Keep the accepted state: C-c C-c must NOT send it again.
                 (mail-async--report
                  job (format "SMTP accepted the message, but local filing/cleanup failed: %s. Draft kept; do NOT resend."
                              (error-message-string error-data))))))))
      (setf (mail-async--job-status job) 'failed)
      (when (buffer-live-p (mail-async--job-source job))
        (with-current-buffer (mail-async--job-source job)
          (setq mail-async--job nil)))
      (mail-async--report
       job (format "Send failed (process %s, status %s). Draft kept; no automatic retry. Check this log before retrying."
                   (process-status process) (process-exit-status process))))))

(defun mail-async--accepted (&optional _argument)
  "Tell Message that the previously submitted message was accepted by SMTP."
  (push 'mail message-sent-message-via)
  t)

(defun mail-async--send (original &optional argument)
  "Run ORIGINAL with ARGUMENT, deferring its success path until SMTP exits."
  (cond
   ((not mail-async/mode) (funcall original argument))
   ((and mail-async--job
         (eq mail-async--completing mail-async--job)
         (eq (current-buffer) (mail-async--job-source mail-async--job)))
    ;; Resume through Message's public method interface, not a second SMTP
    ;; submission or a second MIME encoding (which could differ from the wire).
    (let (result)
      (let ((message-send-method-alist '((mail always mail-async--accepted)))
            (message-send-hook nil)
            (message-confirm-send nil)
            ;; A deliberate resend was already confirmed before submission.
            ;; Do not ask for that confirmation again in the sentinel.
            (message-sent-message-via (remq 'mail message-sent-message-via)))
        (setq result (funcall original argument)))
      (when result (cl-pushnew 'mail message-sent-message-via))
      result))
   (mail-async--job (mail-async--guard))
   (t
    (when (or (message-news-p)
              (message-field-value "X-Message-SMTP-Method"))
      (user-error "Background delivery supports the configured msmtp transport only"))
    (let ((mail-async--source (current-buffer))
          (message-send-mail-function #'mail-async--transport)
          ;; A single process must receive the whole message, never just the
          ;; first part of Message's optional split-message transport.
          (message-send-mail-partially-limit nil))
      (catch 'mail-async--pending
        (funcall original argument))))))

(defun mail-async--send-and-exit (original &rest arguments)
  "Remember that ORIGINAL with ARGUMENTS should close the draft on success."
  (let ((mail-async--exit (current-buffer)))
    (apply original arguments)))

(defun mail-async--transport ()
  "Submit Message's already MIME-encoded buffer to msmtp asynchronously."
  (unless (buffer-live-p mail-async--source)
    (error "No originating compose buffer"))
  (let* ((resend-to (message-fetch-field "resent-to"))
         (arguments (append '("-oi") message-sendmail-extra-arguments
                            (unless message-sendmail-f-is-evil
                              (list "-f" (message-sendmail-envelope-from)))
                            (if resend-to (list resend-to) '("-t"))))
         (input (make-temp-file "emacs-mail-send-"))
         (log (generate-new-buffer "*Mail delivery*"))
         (source mail-async--source)
         (job (mail-async--make-job
               :source source :input input :log log
               :exit (eq source mail-async--exit)
               :status 'sending
               :read-only (buffer-local-value 'buffer-read-only source)
               :mode-line (buffer-local-value 'mode-line-process source)))
         started)
    (unwind-protect
        (progn
          ;; Like message-send-mail-with-sendmail: replace Message's separator
          ;; and run the transport hook in the prepared, disposable buffer.
          (goto-char (point-min))
          (re-search-forward (concat "^" (regexp-quote mail-header-separator) "\n"))
          (replace-match "\n" t t)
          (run-hooks 'message-send-mail-hook)
          (let ((coding-system-for-write message-send-coding-system))
            (write-region (point-min) (point-max) input nil 'silent))
          (with-current-buffer source
            (setq mail-async--job job
                  buffer-read-only t
                  mode-line-process " [sending mail]")
            (add-hook 'kill-buffer-query-functions #'mail-async--keep-buffer nil t)
            (add-hook 'change-major-mode-hook #'mail-async--guard nil t)
            (force-mode-line-update))
          ;; Let the OS feed the private file to msmtp.  process-send-region
          ;; could itself block Emacs if a large attachment fills the pipe.
          ;; Every value is a separate argv item, never interpolated shell text.
          (let ((default-directory "/"))
            (setf (mail-async--job-process job)
                  (make-process
                   :name "mail-msmtp" :buffer log :stderr log
                   :connection-type 'pipe :coding 'utf-8-unix :noquery nil
                   :command (append
                             (list (or (executable-find "sh")
                                       (error "A POSIX sh executable is required"))
                                   "-c" "input=$1; shift; exec \"$@\" < \"$input\""
                                   "mail-msmtp" input sendmail-program)
                             arguments)
                   :sentinel (lambda (process event)
                               (mail-async--sentinel job process event)))))
          (setq started t)
          (message "Sending mail in the background; draft kept until SMTP completes")
          ;; Unwind Message's temporary buffer without running Fcc/sent hooks.
          (throw 'mail-async--pending nil))
      (unless started
        (when (file-exists-p input) (delete-file input))
        (kill-buffer log)
        (mail-async--unlock job)
        (with-current-buffer source (setq mail-async--job nil))))))

;;;###autoload
(define-minor-mode mail-async/mode
  "Send through msmtp in the background, retaining the draft until success.
MIME preparation, attachment reads, and OpenPGP encoding still run locally
before submission.  There is no persistent queue or automatic retry."
  :lighter nil
  (when mail-async--job
    (setq mail-async/mode t)
    (mail-async--guard)))

(advice-add 'message-send :around #'mail-async--send)
(advice-add 'message-send-and-exit :around #'mail-async--send-and-exit)
(dolist (command '(message-kill-buffer message-dont-send))
  (advice-add command :before #'mail-async--guard))

(provide 'mail-async)
;;; mail-async.el ends here
