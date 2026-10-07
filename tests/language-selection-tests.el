;;; language-selection-tests.el --- Real file-opening regressions -*- lexical-binding: t; -*-

(require 'ert)
(require 'cl-lib)
(require 'treesit)

(defmacro config-test/with-language-file (name content &rest body)
  "Visit temporary file NAME containing CONTENT, then run BODY.
Keep real auto-mode selection and hooks, but do not start external servers."
  (declare (indent 2) (debug t))
  `(config-test/with-directory
     (let ((file (config-test/file root ,name ,content))
           (enable-local-variables nil)
           (enable-dir-local-variables nil)
           buffer)
       (unwind-protect
           (cl-letf (((symbol-function 'eglot-ensure) #'ignore))
             (setq buffer (find-file-noselect file))
             (with-current-buffer buffer ,@body))
         (when (buffer-live-p buffer)
           (with-current-buffer buffer (set-buffer-modified-p nil))
           (kill-buffer buffer))))))

(ert-deftest config-test/typescript-and-tsx-open-with-distinct-parsers ()
  (let ((ready (and (treesit-ready-p 'typescript t) (treesit-ready-p 'tsx t)))
        (treesit-auto-install nil))
    (when (getenv "EMACS_TEST_REQUIRE_GRAMMARS") (should ready))
    (skip-unless ready)
    (dolist (fixture '(("sample.ts" "const value: number = 1;\n"
                       typescript-ts-mode typescript)
                      ("sample.tsx" "const view = <div>Hello</div>;\n"
                       tsx-ts-mode tsx)))
      (pcase-let ((`(,name ,content ,mode ,language) fixture))
        (config-test/with-language-file name content
          (should (eq major-mode mode))
          (should (memq language (mapcar #'treesit-parser-language
                                        (treesit-parser-list))))
          (when (eq language 'tsx)
            (should-not (memq 'typescript (mapcar #'treesit-parser-language
                                                 (treesit-parser-list))))))))))

(ert-deftest config-test/typescript-and-tsx-open-without-grammars ()
  (let ((treesit-auto-install nil))
    (cl-letf (((symbol-function 'treesit-ready-p) (lambda (&rest _) nil)))
      (dolist (fixture '(("sample.ts" . typescript-mode)
                        ("sample.tsx" . typescript-tsx-mode)))
        (config-test/with-language-file (car fixture) "const value = 1;\n"
          (should (eq major-mode (cdr fixture)))
          (should (derived-mode-p 'typescript-mode))
          (should-not (treesit-parser-list)))))))

(provide 'language-selection-tests)
;;; language-selection-tests.el ends here
