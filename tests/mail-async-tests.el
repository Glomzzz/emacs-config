;;; mail-async-tests.el --- Real-process offline sending tests -*- lexical-binding: t; -*-

(require 'cl-lib)
(require 'ert)
(require 'json)
(require 'mail-async)

(defconst config-test/mail-async-fixture
  (expand-file-name "fixtures/msmtp-send.py"
                    (file-name-directory (or load-file-name buffer-file-name))))

(defun config-test/mail-await (predicate)
  "Run the event loop until PREDICATE succeeds or fail after 10 seconds."
  (let ((deadline (+ (float-time) 10)))
    (while (and (not (funcall predicate)) (< (float-time) deadline))
      (accept-process-output nil 0.02))
    (should (funcall predicate))))

(defmacro config-test/with-mail-delivery (&rest body)
  "Run BODY with a synthetic compose buffer and gated fake msmtp.
ROOT, SOURCE, PREPARED, SENT, and FILED are available in BODY."
  (declare (indent 0) (debug t))
  `(let* ((root (make-temp-file "mail-async-test-" t))
          (source (generate-new-buffer " *mail-async-test*"))
          (process-environment (copy-sequence process-environment))
          (original-buffers (buffer-list))
          (prepared 0) (sent 0) (filed 0)
          job)
     (setenv "MAIL_ASYNC_TEST_ROOT" root)
     (unwind-protect
         (with-current-buffer source
           (message-mode)
           (mail-async/mode 1)
           (setq-local sendmail-program config-test/mail-async-fixture
                       message-sendmail-f-is-evil t
                       message-sendmail-extra-arguments '("--read-envelope-from")
                       message-mail-alias-type nil
                       message-confirm-send nil
                       message-send-actions nil
                       message-exit-actions nil
                       message-kill-buffer-on-exit nil
                       message-send-hook
                       (list (lambda ()
                               (cl-incf prepared)
                               (write-region (point-min) (point-max)
                                             (expand-file-name "draft" root)
                                             nil 'silent)))
                       message-sent-hook (list (lambda () (cl-incf sent)))
                       message-fcc-handler-function
                       (lambda (path)
                         (cl-incf filed)
                         (write-region (point-min) (point-max) path nil 'silent)))
           (insert "From: sender@example.org\nTo: recipient@example.org\n"
                   "Bcc: hidden@example.org\nSubject: Background mail test\n"
                   "Fcc: " (expand-file-name "sent.eml" root) "\n"
                   mail-header-separator "\nHello from an offline test.\n")
           (cl-letf (((symbol-function 'display-buffer) (lambda (&rest _) nil)))
             ,@body))
       (when (buffer-live-p source)
         (with-current-buffer source (setq job mail-async--job)))
       (when job
         (setf (mail-async--job-status job) 'test-cleanup)
         (let ((process (mail-async--job-process job)))
           (when (process-live-p process)
             (set-process-query-on-exit-flag process nil)
             (delete-process process)))
         (when (file-exists-p (mail-async--job-input job))
           (delete-file (mail-async--job-input job))))
       (dolist (buffer (buffer-list))
         (when (or (eq buffer source) (not (memq buffer original-buffers)))
           (with-current-buffer buffer
             (setq mail-async--job nil
                   kill-buffer-query-functions nil
                   buffer-file-name nil))
           (kill-buffer buffer)))
       (delete-directory root t))))

(defun config-test/mail-release (root)
  "Allow the fake SMTP process below ROOT to finish."
  (with-temp-file (expand-file-name "release" root)))

(ert-deftest config-test/mail-async-defers-fcc-and-hooks-until-smtp-success ()
  (config-test/with-mail-delivery
    (should-not (message-send))
    (let* ((job mail-async--job)
           (input (mail-async--job-input job))
           tick)
      (should buffer-read-only)
      (should (file-exists-p (expand-file-name "draft" root)))
      (should (= (logand (file-modes input) #o777) #o600))
      (should (= prepared 1))
      (should (= sent 0))
      (should (= filed 0))
      (should-error (message-send) :type 'user-error)
      (should-error (message-kill-buffer) :type 'user-error)
      (should-error (message-dont-send) :type 'user-error)
      (should-not (mail-async--keep-buffer))
      (should-error (insert "must not change the message") :type 'buffer-read-only)
      (run-at-time 0 nil (lambda () (setq tick t)))
      (config-test/mail-await (lambda () tick))
      (should (process-live-p (mail-async--job-process job)))
      (config-test/mail-release root)
      (config-test/mail-await (lambda () (eq (mail-async--job-status job) 'done)))
      (should (buffer-live-p source))
      (should-not buffer-read-only)
      (should-not mail-async--job)
      (should (= prepared 1))
      (should (= sent 1))
      (should (= filed 1))
      (should-not (file-exists-p input))
      (let ((args (json-read-file (expand-file-name "arguments.json" root))))
        (should (equal (append args nil) '("-oi" "--read-envelope-from" "-t"))))
      (with-temp-buffer
        (insert-file-contents (expand-file-name "wire.eml" root))
        (should-not (search-forward mail-header-separator nil t))
        (goto-char (point-min))
        (should (search-forward "Hello from an offline test." nil t))))))

(ert-deftest config-test/mail-async-send-and-exit-closes-only-after-acceptance ()
  (config-test/with-mail-delivery
    (setq-local message-kill-buffer-on-exit t)
    (should-not (message-send-and-exit))
    (let ((job mail-async--job))
      (should (buffer-live-p source))
      (should (= sent 0))
      (config-test/mail-release root)
      (config-test/mail-await (lambda () (eq (mail-async--job-status job) 'done)))
      (should (= sent 1))
      (should (= filed 1))
      (should-not (buffer-live-p source)))))

(ert-deftest config-test/mail-async-failure-preserves-editable-draft-and-error ()
  (config-test/with-mail-delivery
    (setenv "MAIL_ASYNC_TEST_FAIL" "1")
    (message-send-and-exit)
    (let* ((job mail-async--job)
           (log (mail-async--job-log job)))
      (config-test/mail-release root)
      (config-test/mail-await (lambda () (eq (mail-async--job-status job) 'failed)))
      (should (buffer-live-p source))
      (should-not buffer-read-only)
      (should-not mail-async--job)
      (should (= sent 0))
      (should (= filed 0))
      (should (file-exists-p (expand-file-name "draft" root)))
      (should-not (file-exists-p (expand-file-name "sent.eml" root)))
      (should-not (file-exists-p (mail-async--job-input job)))
      (with-current-buffer log
        (should (string-match-p "synthetic SMTP rejection" (buffer-string))))
      (insert "Can edit and manually retry now."))))

(ert-deftest config-test/mail-async-filing-error-never-resubmits-smtp ()
  (config-test/with-mail-delivery
    (setq-local message-fcc-handler-function
                (lambda (_) (error "synthetic disk failure")))
    (message-send)
    (let ((job mail-async--job))
      (config-test/mail-release root)
      (config-test/mail-await (lambda () (eq (mail-async--job-status job) 'accepted)))
      (should (eq mail-async--job job))
      (should-not buffer-read-only)
      (should (= sent 0))
      (should-error (message-send) :type 'user-error)
      (with-temp-buffer
        (insert-file-contents (expand-file-name "starts" root))
        (should (equal (buffer-string) "started\n")))
      (with-current-buffer (mail-async--job-log job)
        (should (string-match-p "do NOT resend" (buffer-string)))))))

(ert-deftest config-test/mail-async-launch-error-cleans-staging-and-keeps-draft ()
  (config-test/with-mail-delivery
    (cl-letf (((symbol-function 'make-process)
               (lambda (&rest _) (error "synthetic spawn failure"))))
      (should-error (message-send) :type 'error))
    (should-not mail-async--job)
    (should-not buffer-read-only)
    (should (= sent 0))
    (should (= filed 0))))

(ert-deftest config-test/mail-async-preserves-mime-attachment-and-unicode ()
  (config-test/with-mail-delivery
    (let ((attachment (expand-file-name "attachment.bin" root)))
      (with-temp-file attachment
        (set-buffer-multibyte nil)
        (insert (unibyte-string 0 1 2 127 128 255)))
      (goto-char (point-max))
      (insert "你好, café\n")
      (mml-attach-file attachment "application/octet-stream" nil "attachment")
      (message-send)
      (let ((job mail-async--job))
        (config-test/mail-release root)
        (config-test/mail-await (lambda () (eq (mail-async--job-status job) 'done))))
      (with-temp-buffer
        (insert-file-contents (expand-file-name "wire.eml" root))
        (should (string-match-p "multipart/mixed" (buffer-string)))
        (should (string-match-p "filename=attachment.bin" (buffer-string)))
        (should (string-match-p "AAECf4D/" (buffer-string)))))))

(ert-deftest config-test/mail-async-large-message-does-not-fill-an-emacs-pipe ()
  (config-test/with-mail-delivery
    (goto-char (point-max))
    (insert (make-string (* 2 1024 1024) ?x) "\n")
    ;; The fake transport does not even read stdin until released.  This
    ;; submission must return without needing it to drain a process pipe.
    (message-send)
    (let ((job mail-async--job))
      (should (= sent 0))
      (should (process-live-p (mail-async--job-process job)))
      (config-test/mail-release root)
      (config-test/mail-await (lambda () (eq (mail-async--job-status job) 'done))))))

(ert-deftest config-test/mail-async-signal-preserves-draft-without-retrying ()
  (config-test/with-mail-delivery
    (message-send)
    (let ((job mail-async--job))
      (config-test/mail-await (lambda () (file-exists-p (expand-file-name "started" root))))
      (cl-letf (((symbol-function 'yes-or-no-p) (lambda (_) t)))
        (mail-async/cancel))
      (config-test/mail-await (lambda () (eq (mail-async--job-status job) 'failed)))
      (should (buffer-live-p source))
      (should-not buffer-read-only)
      (should (= sent 0))
      (should (= filed 0))
      (should (file-exists-p (expand-file-name "draft" root)))
      (should-not (file-exists-p (mail-async--job-input job))))))

(ert-deftest config-test/mail-async-does-not-depend-on-compose-working-directory ()
  (config-test/with-mail-delivery
    (setq-local default-directory (file-name-as-directory
                                  (expand-file-name "missing-directory" root)))
    (message-send)
    (let ((job mail-async--job))
      (config-test/mail-release root)
      (config-test/mail-await (lambda () (eq (mail-async--job-status job) 'done))))))

(ert-deftest config-test/mail-async-deliberate-resend-confirms-only-once ()
  (config-test/with-mail-delivery
    (setq-local message-sent-message-via '(mail))
    (let ((confirmations 0))
      (cl-letf (((symbol-function 'y-or-n-p)
                 (lambda (_) (cl-incf confirmations) t)))
        (message-send)
        (let ((job mail-async--job))
          (config-test/mail-release root)
          (config-test/mail-await (lambda () (eq (mail-async--job-status job) 'done)))))
      (should (= confirmations 1))
      (should (memq 'mail message-sent-message-via)))))

(ert-deftest config-test/mail-async-does-not-change-other-message-transports ()
  (with-temp-buffer
    (message-mode)
    (let (called)
      (should (eq (mail-async--send
                   (lambda (_) (setq called t) 'unchanged) nil)
                  'unchanged))
      (should called))))

(provide 'mail-async-tests)
;;; mail-async-tests.el ends here
