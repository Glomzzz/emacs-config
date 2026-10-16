;;; rainbow-delimiters-tests.el --- Delimiter coloring regressions -*- lexical-binding: t; -*-

(require 'ert)
(require 'cl-lib)
(require 'rainbow-delimiters)

(ert-deftest config-test/rainbow-delimiters-declaration-and-hooks ()
  (should (memq 'rainbow-delimiters packages/declared))
  (should (= rainbow-delimiters-max-face-count 5))
  (dolist (hook '(prog-mode-hook conf-mode-hook yaml-mode-hook yaml-ts-mode-hook))
    (should (memq #'ui/rainbow-delimiters-maybe (symbol-value hook)))))

(ert-deftest config-test/rainbow-delimiters-enables-without-parser ()
  (dolist (mode '(emacs-lisp-mode conf-mode))
    (with-temp-buffer
      (funcall mode)
      (should-not (treesit-parser-list))
      (should rainbow-delimiters-mode)
      ;; Parent and child mode hooks may both run; activation is idempotent.
      (ui/rainbow-delimiters-maybe)
      (should rainbow-delimiters-mode)))
  (with-temp-buffer
    (text-mode)
    (should-not (bound-and-true-p rainbow-delimiters-mode))))

(ert-deftest config-test/rainbow-delimiters-enables-with-parser ()
  (skip-unless (treesit-ready-p 'typescript t))
  (with-temp-buffer
    (cl-letf (((symbol-function 'eglot-ensure) #'ignore))
      (typescript-ts-mode))
    (should (treesit-parser-list))
    (should rainbow-delimiters-mode)
    (should fingertip-mode)))

(ert-deftest config-test/rainbow-delimiters-respects-size-limit ()
  (with-temp-buffer
    (insert "12345")
    (let ((buffers/feature-size-limit 5))
      (ui/rainbow-delimiters-maybe)
      (should-not (bound-and-true-p rainbow-delimiters-mode)))
    (let ((buffers/feature-size-limit 6))
      (ui/rainbow-delimiters-maybe)
      (should rainbow-delimiters-mode)))
  (with-temp-buffer
    (let ((buffers/feature-size-limit nil))
      (ui/rainbow-delimiters-maybe)
      (should rainbow-delimiters-mode))))

(ert-deftest config-test/rainbow-delimiters-excludes-remote-special-and-minibuffers ()
  (dolist (kind '(remote special minibuffer))
    (with-temp-buffer
      (when (eq kind 'special) (special-mode))
      (let ((default-directory (if (eq kind 'remote)
                                   "/ssh:unused-host:/tmp/" default-directory)))
        (cl-letf (((symbol-function 'minibufferp)
                   (lambda (&optional _buffer) (eq kind 'minibuffer)))
                  ((symbol-function 'file-attributes)
                   (lambda (&rest _) (ert-fail "Guard performed filesystem I/O"))))
          (ui/rainbow-delimiters-maybe)
          (should-not (bound-and-true-p rainbow-delimiters-mode)))))))

(ert-deftest config-test/rainbow-delimiters-fontifies-depth-and-skips-strings-comments ()
  (with-temp-buffer
    (emacs-lisp-mode)
    (insert "((((((x)))))) \"(text)\" ; (comment)\n")
    (let ((noninteractive nil)) (font-lock-mode 1))
    (font-lock-ensure)
    (dolist (position '(1 6 8 13))
      (should (memq 'rainbow-delimiters-depth-1-face
                    (ensure-list (get-text-property position 'face)))))
    (should (memq 'rainbow-delimiters-depth-2-face
                  (ensure-list (get-text-property 2 'face))))
    (dolist (text '("(text)" "(comment)"))
      (goto-char (point-min))
      (search-forward text)
      (should-not
       (cl-some (lambda (face)
                  (and (symbolp face)
                       (string-prefix-p "rainbow-delimiters-" (symbol-name face))))
                (ensure-list (get-text-property (- (point) (length text)) 'face)))))
    (should show-paren-mode)))

(ert-deftest config-test/rainbow-delimiters-so-long-disables-and-restores ()
  (with-temp-buffer
    (emacs-lisp-mode)
    (should rainbow-delimiters-mode)
    (should (memq 'rainbow-delimiters-mode so-long-minor-modes))
    (so-long 'so-long-minor-mode)
    (should-not rainbow-delimiters-mode)
    (let ((noninteractive nil)) (so-long-revert))
    (should rainbow-delimiters-mode)))

(provide 'rainbow-delimiters-tests)
;;; rainbow-delimiters-tests.el ends here
