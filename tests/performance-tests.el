;;; performance-tests.el --- Resource guard regressions -*- lexical-binding: t; -*-

(require 'ert)
(require 'cl-lib)

(ert-deftest config-test/line-numbers-respect-size-limit ()
  (with-temp-buffer
    (insert "12345")
    (let ((buffers/feature-size-limit 5))
      (appearance/line-numbers-maybe)
      (should-not display-line-numbers-mode))
    (let ((buffers/feature-size-limit 6))
      (appearance/line-numbers-maybe)
      (should display-line-numbers-mode)))
  (with-temp-buffer
    (let ((buffers/feature-size-limit nil))
      (appearance/line-numbers-maybe)
      (should display-line-numbers-mode))))

(ert-deftest config-test/line-numbers-remote-check-is-lexical ()
  (with-temp-buffer
    (let ((default-directory "/ssh:unused-host:/tmp/"))
      (cl-letf (((symbol-function 'file-attributes)
                 (lambda (&rest _) (ert-fail "Remote guard probed the filesystem"))))
        (appearance/line-numbers-maybe)
        (should-not display-line-numbers-mode)))))

(ert-deftest config-test/completion-auto-guard-keeps-manual-completion ()
  (require 'corfu)
  (dolist (kind '(small large remote opt-out))
    (with-temp-buffer
      (insert "ab")
      (let ((buffers/feature-size-limit (if (eq kind 'large) 2 3))
            (default-directory (if (eq kind 'remote)
                                   "/ssh:unused-host:/tmp/" default-directory)))
        (when (eq kind 'opt-out) (setq-local corfu-auto nil))
        (corfu-mode 1)
        (should corfu-mode)
        (if (eq kind 'small)
            (should corfu-auto)
          (should-not corfu-auto)
          (should (local-variable-p 'corfu-auto))
          ;; A nil option is insufficient if Corfu already installed its timer.
          (should-not (memq 'corfu-auto--post-command post-command-hook)))
        (should (functionp completion-in-region-function))
        ;; Exercise public manual CAPF dispatch without requiring a GUI popup.
        (let* ((completion-at-point-functions
                (list (lambda () '(1 3 ("abc") :exclusive t))))
               matches
               (completion-in-region-function
                (lambda (beg end table &optional predicate)
                  (setq matches (all-completions (buffer-substring beg end)
                                                table predicate))
                  t)))
          (should (completion-at-point))
          (should (equal matches '("abc"))))))))

(ert-deftest config-test/completion-so-long-keeps-manual-mode-only ()
  (with-temp-buffer
    (so-long-mode)
    (corfu-mode 1)
    (should corfu-mode)
    (should-not corfu-auto)
    (should-not (memq 'corfu-auto--post-command post-command-hook))
    (should (functionp completion-in-region-function))))

(ert-deftest config-test/completion-auto-guard-unlimited-and-local-scope ()
  (with-temp-buffer
    (insert "12345")
    (let ((buffers/feature-size-limit nil))
      (corfu-mode 1)
      (should corfu-auto)))
  (should (default-value 'corfu-auto)))

(ert-deftest config-test/so-long-disables-expensive-modes-and-reverts ()
  (require 'so-long)
  (dolist (mode '(font-lock-mode display-line-numbers-mode corfu-mode))
    (should (memq mode so-long-minor-modes)))
  (let ((buffer (generate-new-buffer "so-long-test")))
    (unwind-protect
        (with-current-buffer buffer
          (emacs-lisp-mode)
          ;; Font Lock skips batch sessions and space-prefixed buffers.
          (let ((noninteractive nil)) (font-lock-mode 1))
          (display-line-numbers-mode 1)
          (corfu-mode 1)
          (should font-lock-mode)
          (should corfu-mode)
          (so-long 'so-long-minor-mode)
          (should-not font-lock-mode)
          (should-not display-line-numbers-mode)
          (should-not corfu-mode)
          (should-not buffer-read-only)
          (let ((noninteractive nil)) (so-long-revert))
          (should font-lock-mode)
          (should display-line-numbers-mode)
          (should corfu-mode)
          (should corfu-auto))
      (kill-buffer buffer))))

;;; performance-tests.el ends here
