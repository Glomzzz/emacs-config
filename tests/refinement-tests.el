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

(provide 'refinement-tests)
;;; refinement-tests.el ends here
