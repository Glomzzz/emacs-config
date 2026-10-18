;;; typst-editing-tests.el --- Typst indentation regressions -*- lexical-binding: t; -*-

(require 'cl-lib)
(require 'ert)

(defmacro config-test/with-typst-editing (&rest body)
  "Run BODY in a displayed Typst buffer with its real parser and keymaps."
  (declare (indent 0) (debug t))
  `(progn
     (when (getenv "EMACS_TEST_REQUIRE_GRAMMARS")
       (should (treesit-ready-p 'typst t)))
     (skip-unless (treesit-ready-p 'typst t))
     (config-test/with-pair-buffer #'typst-ts-mode
       ,@body)))

(ert-deftest config-test/typst-editing-dollars-preserve-list-indentation ()
  (dolist (bullet '("-" "+"))
    (dolist (content (list (concat bullet " item\n    ")
                          (concat bullet " item\n    more text ")
                          (concat bullet " item\n\n    ")
                          (concat "    " bullet " item ")
                          (concat bullet " outer\n    - inner\n        ")
                          (concat bullet " outer\n    + inner\n        ")))
      (config-test/with-typst-editing
        (insert content)
        ;; Check each key: an unfinished math node must not shift the line
        ;; either, and finishing it must not normalize list indentation.
        (config-test/pair-type "$")
        (should (equal (buffer-string) (concat content "$")))
        (should (= (point) (point-max)))
        (config-test/pair-type "$")
        (should (equal (buffer-string) (concat content "$$")))
        (should (= (point) (point-max)))))))

(ert-deftest config-test/typst-editing-closing-dollar-preserves-indentation ()
  (dolist (bullet '("-" "+"))
    (config-test/with-typst-editing
      (insert bullet " item\n    $x suffix")
      (backward-char (length " suffix"))
      (config-test/pair-type "$")
      (should (equal (buffer-string) (concat bullet " item\n    $x$ suffix")))
      (should (eq (char-after) ?\s)))))

(ert-deftest config-test/typst-editing-indent-triggers-are-buffer-local ()
  (let ((defaults (copy-sequence (default-value 'electric-indent-chars))))
    (config-test/with-typst-editing
      (should electric-indent-mode)
      (should-not (memq ?$ electric-indent-chars))
      (dolist (character (append "{}()[]&." defaults))
        (should (memq character electric-indent-chars))))
    (should (equal defaults (default-value 'electric-indent-chars)))))

(ert-deftest config-test/typst-editing-explicit-and-newline-indent-still-work ()
  (config-test/with-typst-editing
    (insert "- item\n    $$\n")
    (backward-char)
    (indent-according-to-mode)
    (should (equal (buffer-string) "- item\n  $$\n"))
    (erase-buffer)
    (insert "- item\n")
    (backward-char)
    (execute-kbd-macro (kbd "RET"))
    (should (equal (buffer-string) "- item\n  \n"))))

(ert-deftest config-test/typst-editing-fallback-dollar-insertion-unchanged ()
  (dolist (bullet '("-" "+"))
    (config-test/with-pair-buffer #'typst-mode
      (insert bullet " item\n    ")
      (config-test/pair-type "$$")
      (should (equal (buffer-string) (concat bullet " item\n    $$"))))))

(provide 'typst-editing-tests)
;;; typst-editing-tests.el ends here
