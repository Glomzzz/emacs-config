;;; pi-inline-tests.el --- Inline Pi regression tests -*- lexical-binding: t; -*-

(require 'ert)
(require 'cl-lib)

(defconst config-test/pi-loaded-on-startup (featurep 'pi-inline))
(require 'pi-inline)

(defconst config-test/pi-fixture
  (expand-file-name "fixtures/pi-inline-rpc.py"
                    (file-name-directory (or load-file-name buffer-file-name))))

(defmacro config-test/with-pi (&rest body)
  "Run BODY in a source buffer with isolated Pi workers and transcripts."
  (declare (indent 0) (debug t))
  `(let ((pi-inline-executable (or (executable-find "python3") "python3"))
         (pi-inline-extra-arguments (list "-u" config-test/pi-fixture))
         (pi-inline-timeout 5)
         (default-directory temporary-file-directory)
         (source (generate-new-buffer " *pi-inline-source*"))
         request)
     (with-current-buffer source
       (buffer-enable-undo)
       (insert "before|after")
       (setq buffer-undo-list nil)
       (set-buffer-modified-p nil)
       (goto-char 8)
       (unwind-protect
           (progn ,@body)
         (when pi-inline--request
           (pi-inline/cancel))
         (when request
           (when (process-live-p (pi-inline--request-process request))
             (delete-process (pi-inline--request-process request)))
           (when (process-live-p (pi-inline--request-stderr request))
             (delete-process (pi-inline--request-stderr request)))
           (when (buffer-live-p (pi-inline--request-log request))
             (kill-buffer (pi-inline--request-log request))))
         (when (buffer-live-p source) (kill-buffer source))))))

(defun config-test/pi-submit (prompt)
  "Start an inline request with PROMPT in the current test buffer."
  (pi-inline/start)
  (insert prompt)
  (prog1 pi-inline--request (pi-inline/submit)))

(defun config-test/pi-wait (predicate)
  "Wait up to four seconds for PREDICATE while servicing process output."
  (let ((deadline (+ (float-time) 4)))
    (while (and (not (funcall predicate)) (< (float-time) deadline))
      (accept-process-output nil 0.01))
    (should (funcall predicate))))

(ert-deftest config-test/pi-draft-cancel-restores-text-modification-and-undo ()
  (config-test/with-pi
    (pi-inline/start)
    (should pi-inline-mode)
    (should (eq (key-binding (kbd "C-c C-c")) #'pi-inline/submit))
    (should (eq (key-binding (kbd "C-c C-k")) #'pi-inline/cancel))
    (insert "Write something\nwith two lines")
    (pi-inline/cancel)
    (should (equal (buffer-string) "before|after"))
    (should-not (buffer-modified-p))
    (should-not buffer-undo-list)
    (should-not pi-inline-mode)
    (should-not pi-inline--request)
    (should-not (overlays-in (point-min) (point-max)))))

(ert-deftest config-test/pi-draft-protects-source-and-save ()
  (config-test/with-pi
    (pi-inline/start)
    (should-error (pi-inline--check-save) :type 'user-error)
    (should-error (progn (goto-char (point-min)) (insert "bad")) :type 'user-error)
    ;; A rejected change must not silently disable the guard.
    (should-error (progn (goto-char (point-max)) (delete-char -1)) :type 'user-error)
    (should (pi-inline--request-guards pi-inline--request))
    (goto-char (+ 1 (overlay-start (pi-inline--request-overlay pi-inline--request))))
    (insert "still editable")
    (pi-inline/cancel)
    (should (equal (buffer-string) "before|after"))))

(ert-deftest config-test/pi-empty-or-missing-executable-keeps-editable-draft ()
  (config-test/with-pi
    (pi-inline/start)
    (should-error (pi-inline/submit) :type 'user-error)
    (insert "keep this instruction")
    (let ((pi-inline-executable "/nonexistent/pi-inline-executable"))
      (should-error (pi-inline/submit) :type 'user-error))
    (should (eq (pi-inline--request-status pi-inline--request) 'editing))))

(ert-deftest config-test/pi-refuses-read-only-and-remote-buffers ()
  (config-test/with-pi
    (let ((buffer-read-only t)) (should-error (pi-inline/start)))
    (let ((default-directory "/ssh:example.invalid:/tmp/"))
      (should-error (pi-inline/start) :type 'user-error))
    (should-not pi-inline--request)))

(ert-deftest config-test/pi-one-request-per-buffer ()
  (config-test/with-pi
    (pi-inline/start)
    (should-error (pi-inline/start) :type 'user-error)))

(ert-deftest config-test/pi-rpc-inserts-only-authoritative-text-and-keeps-source-unsaved ()
  (skip-unless (executable-find "python3"))
  (config-test/with-pi
    (setq request (config-test/pi-submit "Produce text"))
    (should (equal (buffer-string) "before|after"))
    (should-not (buffer-modified-p))
    (should (string-match-p "agent working" (overlay-get (pi-inline--request-overlay request) 'before-string)))
    (config-test/pi-wait (lambda () (eq (pi-inline--request-status request) 'done)))
    (should (equal (buffer-string) "before|generated λ\u2028text\nafter"))
    (should (buffer-modified-p))
    (should-not pi-inline-mode)
    (should (equal (pi-inline--request-session-file request) "/tmp/pi-inline-fixture-session.jsonl"))
    (with-current-buffer (pi-inline--request-log request)
      (should (string-match-p "Checking context" (buffer-string)))
      (should (string-match-p "Tool: read" (buffer-string)))
      (should (string-match-p "Read result" (buffer-string)))
      (should-not (string-match-p "incorrect partial" (buffer-string))))
    (undo-only)
    (should (equal (buffer-string) "before|after"))))

(ert-deftest config-test/pi-waits-for-settled-not-agent-end ()
  (skip-unless (executable-find "python3"))
  (config-test/with-pi
    (setq request (config-test/pi-submit "Produce text"))
    (config-test/pi-wait (lambda () (pi-inline--request-last-message request)))
    (should (eq (pi-inline--request-status request) 'working))
    (should (equal (buffer-string) "before|after"))
    (config-test/pi-wait (lambda () (eq (pi-inline--request-status request) 'done)))))

(ert-deftest config-test/pi-worker-uses-rpc-and-read-only-tools ()
  (skip-unless (executable-find "python3"))
  (config-test/with-pi
    (setq request (config-test/pi-submit "fixture/hang"))
    (let ((command (process-command (pi-inline--request-process request))))
      (should (equal (cadr (member "--mode" command)) "rpc"))
      (should (equal (cadr (member "--tools" command)) "read,grep,find,ls"))
      (should (member "--no-extensions" command))
      (should (member "--no-mcp" command))
      (should-not (member "--no-session" command)))))

(ert-deftest config-test/pi-working-display-is-virtual-and-source-remains-editable ()
  (skip-unless (executable-find "python3"))
  (config-test/with-pi
    (setq request (config-test/pi-submit "fixture/hang"))
    (pi-inline--check-save) ; no failure, unlike drafting
    (goto-char (point-min))
    (insert "new ")
    (should (= (pi-inline--request-position request) 12))
    (should (= (overlay-start (pi-inline--request-overlay request)) 12))
    (goto-char (pi-inline--request-position request))
    (insert "local ")
    (should (= (pi-inline--request-position request) 18))
    (should (= (overlay-start (pi-inline--request-overlay request)) 18))
    (pi-inline/cancel)
    (should (equal (buffer-string) "new before|local after"))))

(ert-deftest config-test/pi-failures-never-insert-partial-or-empty-text ()
  (skip-unless (executable-find "python3"))
  (dolist (case '("fixture/reject" "fixture/error" "fixture/length" "fixture/empty" "fixture/handled"))
    (config-test/with-pi
      (setq request (config-test/pi-submit case))
      (config-test/pi-wait (lambda () (eq (pi-inline--request-status request) 'failed)))
      (should (equal (buffer-string) "before|after"))
      (should-not (buffer-modified-p))
      (pi-inline/submit)
      (should (eq (pi-inline--request-status pi-inline--request) 'editing))
      (should (string-match-p case (buffer-string)))
      (pi-inline/cancel)
      (should (equal (buffer-string) "before|after")))))

(ert-deftest config-test/pi-timeout-retains-a-failure-link ()
  (skip-unless (executable-find "python3"))
  (config-test/with-pi
    (let ((pi-inline-timeout 0.1))
      (setq request (config-test/pi-submit "fixture/hang")))
    (config-test/pi-wait (lambda () (eq (pi-inline--request-status request) 'failed)))
    (should (string-match-p "Pi failed" (overlay-get (pi-inline--request-overlay request) 'before-string)))))

(ert-deftest config-test/pi-cancel-ignores-late-records ()
  (skip-unless (executable-find "python3"))
  (config-test/with-pi
    (setq request (config-test/pi-submit "fixture/hang"))
    (pi-inline/cancel)
    (should-not (process-live-p (pi-inline--request-process request)))
    (pi-inline--filter request "{\"type\":\"agent_settled\",\"aborted\":false}\n")
    (should (eq (pi-inline--request-status request) 'cancelled))
    (should (equal (buffer-string) "before|after"))))

(ert-deftest config-test/pi-unexpected-exit-and-malformed-protocol-fail ()
  (skip-unless (executable-find "python3"))
  (config-test/with-pi
    (setq request (config-test/pi-submit "fixture/hang"))
    (delete-process (pi-inline--request-process request))
    (config-test/pi-wait (lambda () (eq (pi-inline--request-status request) 'failed))))
  (config-test/with-pi
    (setq request (config-test/pi-submit "fixture/hang"))
    (pi-inline--filter request "not JSON\n")
    (should (eq (pi-inline--request-status request) 'failed))))

(ert-deftest config-test/pi-source-kill-or-mode-change-cancels-worker ()
  (skip-unless (executable-find "python3"))
  (config-test/with-pi
    (setq request (config-test/pi-submit "fixture/hang"))
    (fundamental-mode)
    (should (eq (pi-inline--request-status request) 'cancelled))
    (should-not (process-live-p (pi-inline--request-process request))))
  (config-test/with-pi
    (setq request (config-test/pi-submit "fixture/hang"))
    (kill-buffer (current-buffer))
    (should (eq (pi-inline--request-status request) 'cancelled))))

(ert-deftest config-test/pi-key-and-click-open-matching-transcript-without-rebinding-xref ()
  (skip-unless (executable-find "python3"))
  (config-test/with-pi
    (let (opened fallback)
      (local-set-key (kbd "M-.") (lambda () (interactive) (setq fallback t)))
      (setq request (config-test/pi-submit "fixture/hang"))
      (cl-letf (((symbol-function 'pop-to-buffer)
                 (lambda (buffer &rest _) (setq opened buffer))))
        (pi-inline/visit)
        (should (eq opened (pi-inline--request-log request)))
        (setq opened nil)
        (let* ((string (overlay-get (pi-inline--request-overlay request) 'before-string))
               (map (get-text-property 0 'keymap string)))
          (funcall (lookup-key map [mouse-1]) nil))
        (should (eq opened (pi-inline--request-log request)))
        (goto-char (point-min))
        (pi-inline/visit)
        (should fallback)))))

(ert-deftest config-test/pi-cancel-from-transcript-preserves-source ()
  (skip-unless (executable-find "python3"))
  (config-test/with-pi
    (setq request (config-test/pi-submit "fixture/hang"))
    (with-current-buffer (pi-inline--request-log request) (pi-inline/cancel))
    (should (equal (buffer-string) "before|after"))
    (should-not pi-inline-mode)))

(ert-deftest config-test/pi-final-insertion-obeys-read-only-source ()
  (skip-unless (executable-find "python3"))
  (config-test/with-pi
    (setq request (config-test/pi-submit "Produce text"))
    (setq buffer-read-only t)
    (config-test/pi-wait (lambda () (eq (pi-inline--request-status request) 'failed)))
    (should (equal (buffer-string) "before|after"))))

(ert-deftest config-test/pi-insertion-works-with-narrowing ()
  (skip-unless (executable-find "python3"))
  (config-test/with-pi
    (narrow-to-region 3 11)
    (setq request (config-test/pi-submit "Produce text"))
    (config-test/pi-wait (lambda () (eq (pi-inline--request-status request) 'done)))
    (should (= (point-min) 3))
    (widen)
    (should (equal (buffer-string) "before|generated λ\u2028text\nafter"))))

(ert-deftest config-test/pi-startup-is-lazy-and-start-binding-is-installed ()
  (should-not config-test/pi-loaded-on-startup)
  (when (featurep 'init)
    (should (eq (lookup-key global-map (kbd "C-c C-a")) #'pi-inline/start))))

(ert-deftest config-test/pi-start-shortcut-wins-in-editing-but-not-special-buffers ()
  (skip-unless (featurep 'init))
  (with-temp-buffer
    (org-mode)
    (should (eq (key-binding (kbd "C-c C-a")) #'pi-inline/start)))
  (with-temp-buffer
    (markdown-mode)
    (should (eq (key-binding (kbd "C-c C-a")) #'pi-inline/start)))
  (with-temp-buffer
    (special-mode)
    (local-set-key (kbd "C-c C-a") #'ignore)
    (should (eq (key-binding (kbd "C-c C-a")) #'ignore))))

(ert-deftest config-test/pi-real-save-and-auto-save-never-write-the-draft ()
  (let ((file (make-temp-file "pi-inline-save-"))
        (recovery (make-temp-name (expand-file-name "pi-inline-auto-" temporary-file-directory))))
    (unwind-protect
        (config-test/with-pi
          (setq buffer-file-name file
                buffer-auto-save-file-name recovery)
          (write-region (point-min) (point-max) file nil 'silent)
          (pi-inline/start)
          (insert "never write these instructions")
          (should-not buffer-auto-save-file-name)
          (dotimes (_ 2) (should-error (save-buffer) :type 'user-error))
          (do-auto-save t)
          (should-not (file-exists-p recovery))
          (with-temp-buffer
            (insert-file-contents file)
            (should (equal (buffer-string) "before|after")))
          (pi-inline/cancel)
          (should (equal buffer-auto-save-file-name recovery)))
      (delete-file file)
      (when (file-exists-p recovery) (delete-file recovery)))))

(ert-deftest config-test/pi-submit-restores-auto-save-and-revert-cancels-worker ()
  (skip-unless (executable-find "python3"))
  (config-test/with-pi
    (setq buffer-auto-save-file-name "/tmp/pi-inline-test-recovery")
    (setq request (config-test/pi-submit "fixture/hang"))
    (should (equal buffer-auto-save-file-name "/tmp/pi-inline-test-recovery"))
    (run-hooks 'before-revert-hook)
    (should (eq (pi-inline--request-status request) 'cancelled))
    (should-not (process-live-p (pi-inline--request-process request)))))

(ert-deftest config-test/pi-cancel-restores-preexisting-undo-and-read-only-draft ()
  (config-test/with-pi
    (goto-char (point-min))
    (insert "prior edit ")
    (undo-boundary)
    (pi-inline/start)
    (insert "instructions")
    (setq buffer-read-only t)
    (pi-inline/cancel)
    (should (equal (buffer-string) "prior edit before|after"))
    (should (buffer-modified-p))
    (setq buffer-read-only nil)
    (undo-only)
    (should (equal (buffer-string) "before|after"))))

(ert-deftest config-test/pi-rollback-notifies-normal-buffer-change-hooks ()
  (config-test/with-pi
    (let (observed)
      (add-hook 'after-change-functions
                (lambda (&rest _) (push (buffer-string) observed)) nil t)
      (pi-inline/start)
      (insert "instructions")
      (pi-inline/cancel)
      (should (equal (car observed) "before|after")))))

(ert-deftest config-test/pi-draft-works-with-undo-disabled ()
  (config-test/with-pi
    (buffer-disable-undo)
    (pi-inline/start)
    (insert "instructions")
    (pi-inline/cancel)
    (should (equal (buffer-string) "before|after"))
    (should (eq buffer-undo-list t))))

;;; pi-inline-tests.el ends here
