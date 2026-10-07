;;; refinement-tests.el --- Configurable-default regressions -*- lexical-binding: t; -*-

(require 'ert)
(require 'cl-lib)

(ert-deftest config-test/haskell-server-settings-are-project-local ()
  (let ((haskell/server-threads 4)
        (haskell/max-completions 250))
    (should (equal (haskell/server-command)
                   '("haskell-language-server-wrapper" "--lsp" "-j" "4")))
    (should (equal (haskell/eglot-workspace-configuration nil)
                   '(:haskell (:maxCompletions 250)))))
  (let ((haskell/server-threads nil))
    (should (equal (haskell/server-command)
                   '("haskell-language-server-wrapper" "--lsp")))))

(ert-deftest config-test/haskell-does-not-override-server-sorting ()
  (with-temp-buffer
    (cl-letf (((symbol-function 'eglot-ensure) #'ignore))
      (haskell-mode)
      (should-not (local-variable-p 'corfu-sort-override-function)))))

(ert-deftest config-test/shared-buffer-size-policy ()
  (with-temp-buffer
    (insert "12345")
    (let ((buffers/feature-size-limit 5))
      (should-not (buffers/small-p))
      (should (buffers/small-p 6)))
    (let ((buffers/feature-size-limit nil))
      (should (buffers/small-p)))))

(ert-deftest config-test/whitespace-preserves-prose-and-markdown-breaks ()
  (dolist (mode '(text-mode markdown-mode))
    (with-temp-buffer
      (funcall mode)
      (insert "line  \n")
      (emacs/delete-trailing-whitespace-maybe)
      (should (equal (buffer-string) "line  \n")))))

(ert-deftest config-test/whitespace-respects-project-policy ()
  (with-temp-buffer
    (emacs-lisp-mode)
    (insert "code  \n")
    (let ((editor/trim-trailing-whitespace nil))
      (emacs/delete-trailing-whitespace-maybe)
      (should (equal (buffer-string) "code  \n")))
    (emacs/delete-trailing-whitespace-maybe)
    (should (equal (buffer-string) "code\n")))
  (with-temp-buffer
    (text-mode)
    (insert "text  \n")
    (let ((editor/trim-trailing-whitespace t))
      (emacs/delete-trailing-whitespace-maybe)
      (should (equal (buffer-string) "text\n")))))

(ert-deftest config-test/text-layout-keeps-upstream-defaults ()
  (with-temp-buffer
    (text-mode)
    (should bidi-display-reordering)
    (should-not bidi-paragraph-direction)
    (should-not bidi-inhibit-bpa)
    (should-not sentence-end)))

(provide 'refinement-tests)
;;; refinement-tests.el ends here
