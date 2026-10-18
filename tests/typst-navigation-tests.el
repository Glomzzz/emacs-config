;;; typst-navigation-tests.el --- Typst string file jumps -*- lexical-binding: t; -*-

(require 'ert)
(require 'cl-lib)
(require 'xref)

(defun config-test/typst-follow-file (relative-name root)
  "Follow M-. to RELATIVE-NAME under ROOT and return with M-,."
  (let* ((source (current-buffer))
         (position (point))
         (file (expand-file-name relative-name root))
         (history (list nil))
         (xref-history-storage (lambda () history))
         target)
    (unwind-protect
        (save-window-excursion
          (switch-to-buffer source)
          (should (eq (key-binding (kbd "M-.")) #'typst/find-definition))
          (cl-letf (((symbol-function 'eglot-ensure) #'ignore)
                    ((symbol-function 'xref-find-definitions)
                     (lambda (&rest _)
                       (ert-fail "Existing file fell through to Xref"))))
            (call-interactively (key-binding (kbd "M-."))))
          (setq target (current-buffer))
          (should (equal buffer-file-name file))
          (call-interactively (key-binding (kbd "M-,")))
          (should (eq (current-buffer) source))
          (should (= (point) position)))
      (xref-clear-marker-stack)
      (when (and target (not (eq target source)) (buffer-live-p target))
        (kill-buffer target)))))

(ert-deftest config-test/typst-file-jump-root-relative-and-escaped-paths ()
  (dolist (fixture '(("|lemma" . "lemma.typ")
                     ("lemma|" . "lemma.typ")
                     ("/lem|ma" . "lemma.typ")
                     ("lem|ma.typ" . "lemma.typ")
                     ("chapters/first|lemma" . "chapters/firstlemma.typ")
                     ("lemma |two" . "lemma two.typ")
                     ("|定理" . "定理.typ")
                     ("a\\\"q|uote" . "a\"quote.typ")
                     ("a\\\\b|ackslash" . "a\\backslash.typ")))
    (config-test/with-typst-completion (concat "#let path = \"" (car fixture) "\"")
      (config-test/file root (cdr fixture))
      ;; Neither the nested source directory nor the working directory is root.
      (let ((default-directory temporary-file-directory))
        (config-test/typst-follow-file (cdr fixture) root)))))

(ert-deftest config-test/typst-file-jump-dot-slash-starts-at-source-directory ()
  (dolist (fixture '(("./lem|ma" . "lemma.typ")
                     ("./lem|ma.typ" . "lemma.typ")
                     ("./algebra/lem|ma" . "algebra/lemma.typ")
                     ("./lemma |two" . "lemma two.typ")
                     ("./|定理" . "定理.typ")
                     ("./a\\\"q|uote" . "a\"quote.typ")
                     ("./a\\\\b|ackslash" . "a\\backslash.typ")))
    (config-test/with-typst-completion (concat "#let path = \"" (car fixture) "\"")
      (dolist (directory '("" "statements/" "book/" "book/statements/"))
        (config-test/file root (concat directory (cdr fixture))))
      ;; Use the source directory even when Emacs' working directory differs.
      (let ((default-directory root))
        (config-test/typst-follow-file (concat "book/" (cdr fixture)) root)))))

(ert-deftest config-test/typst-file-jump-dot-slash-falls-back-to-source-statements ()
  (config-test/with-typst-completion "#let path = \"./lem|ma\""
    (dolist (name '("lemma.typ" "statements/lemma.typ"
                    "book/statements/lemma.typ"))
      (config-test/file root name))
    (config-test/typst-follow-file "book/statements/lemma.typ" root)))

(ert-deftest config-test/typst-file-jump-prefers-root-over-statements-and-source ()
  (config-test/with-typst-completion "#let name = \"lem|ma\""
    (dolist (name '("lemma.typ" "statements/lemma.typ" "book/lemma.typ"
                    "book/statements/lemma.typ"))
      (config-test/file root name))
    (config-test/typst-follow-file "lemma.typ" root)))

(ert-deftest config-test/typst-file-jump-falls-back-to-statements ()
  (dolist (fixture '(("lem|ma" . "statements/lemma.typ")
                     ("/lem|ma" . "statements/lemma.typ")
                     ("lem|ma.typ" . "statements/lemma.typ")
                     ("algebra/lem|ma" . "statements/algebra/lemma.typ")))
    (config-test/with-typst-completion (concat "#let name = \"" (car fixture) "\"")
      (config-test/file root (cdr fixture))
      ;; A source-relative file must not take priority over statements/.
      (config-test/file root "book/lemma.typ")
      (config-test/typst-follow-file (cdr fixture) root))))

(ert-deftest config-test/typst-file-jump-skips-directory-at-first-candidate ()
  (config-test/with-typst-completion "#let name = \"lem|ma\""
    (make-directory (expand-file-name "lemma.typ" root))
    (config-test/file root "statements/lemma.typ")
    (config-test/typst-follow-file "statements/lemma.typ" root)))

(ert-deftest config-test/typst-file-jump-adds-suffix-before-testing-root-file ()
  (config-test/with-typst-completion "#let name = \"lem|ma\""
    (config-test/file root "lemma")
    (config-test/file root "statements/lemma.typ")
    (config-test/typst-follow-file "statements/lemma.typ" root)))

(ert-deftest config-test/typst-file-jump-accepts-point-on-opening-quote ()
  (config-test/with-typst-completion "#let name = |\"lemma\""
    (config-test/file root "lemma.typ")
    (config-test/typst-follow-file "lemma.typ" root)))

(ert-deftest config-test/typst-file-jump-supports-import-include-and-read ()
  (dolist (content '("#import \"mod|ule\": value"
                     "#include \"mod|ule\""
                     "#read(\"mod|ule\")"))
    (config-test/with-typst-completion content
      (config-test/file root "module.typ" "#let value = 1\n")
      (config-test/typst-follow-file "module.typ" root))))

(ert-deftest config-test/typst-file-jump-root-prefers-typst-marker ()
  (config-test/with-typst-completion "#let name = \"lem|ma\""
    (config-test/file root "book/package.json" "{}")
    (config-test/file root "lemma.typ")
    (config-test/file root "book/lemma.typ")
    (config-test/typst-follow-file "lemma.typ" root)))

(ert-deftest config-test/typst-file-jump-root-prefers-nested-typst-marker ()
  (config-test/with-typst-completion "#let name = \"lem|ma\""
    (config-test/file root "book/.typst-root")
    (config-test/file root "lemma.typ")
    (config-test/file root "book/statements/lemma.typ")
    (config-test/typst-follow-file "book/statements/lemma.typ" root)))

(ert-deftest config-test/typst-file-jump-root-falls-back-to-normal-project ()
  (config-test/with-typst-completion "#let name = \"lem|ma\""
    (delete-file (expand-file-name ".typst-root" root))
    (config-test/file root "package.json" "{}")
    (config-test/file root "lemma.typ")
    (config-test/typst-follow-file "lemma.typ" root)))

(ert-deftest config-test/typst-file-jump-root-falls-back-to-source ()
  (config-test/with-typst-completion "#let name = \"lem|ma\""
    (delete-file (expand-file-name ".typst-root" root))
    (config-test/file root "book/lemma.typ")
    (let ((locate-dominating-stop-dir-regexp
           (concat "\\`" (regexp-quote root) "\\'")))
      (config-test/typst-follow-file "book/lemma.typ" root))))

(ert-deftest config-test/typst-file-jump-leaves-normal-xref-alone ()
  (dolist (content '("#let value = sym|bol"
                     "#let path = \"mis|sing\""
                     "#let path = \"./lem|ma\""
                     "#let path = \"|\""
                     "#let path = \"./pict|ures/\""
                     "#let path = \"lemma\"|"
                     "// \"lem|ma\""
                     "/* \"lem|ma\" */"
                     "#import \"@preview/exam|ple:0.1.0\""
                     "#link(\"https://example.org/lem|ma\")"))
    (config-test/with-typst-completion content
      (config-test/file root "lemma.typ")
      (let ((source (current-buffer))
            (position (point))
            queried)
        (cl-letf (((symbol-function 'xref-find-definitions)
                   (lambda ()
                     (interactive)
                     (should (eq (current-buffer) source))
                     (should (= (point) position))
                     (setq queried t)))
                  ((symbol-function 'xref-push-marker-stack)
                   (lambda (&rest _) (ert-fail "Fallback changed Xref history"))))
          (call-interactively (key-binding (kbd "M-."))))
        (should queried)))))

(ert-deftest config-test/typst-file-jump-does-not-use-source-relative-file ()
  (config-test/with-typst-completion "#let name = \"lem|ma\""
    (config-test/file root "book/lemma.typ")
    (let (queried)
      (cl-letf (((symbol-function 'xref-find-definitions)
                 (lambda () (interactive) (setq queried t)))
                ((symbol-function 'find-file)
                 (lambda (&rest _) (ert-fail "Source-relative file was opened"))))
        (call-interactively (key-binding (kbd "M-."))))
      (should queried))))

(ert-deftest config-test/typst-file-jump-prefix-forces-normal-lookup ()
  (config-test/with-typst-completion "#let name = \"lem|ma\""
    (config-test/file root "lemma.typ")
    (let ((current-prefix-arg '(4))
          queried)
      (cl-letf (((symbol-function 'xref-find-definitions)
                 (lambda ()
                   (interactive)
                   (should (equal current-prefix-arg '(4)))
                   (setq queried t)))
                ((symbol-function 'find-file)
                 (lambda (&rest _) (ert-fail "Prefix argument opened a file"))))
        (call-interactively (key-binding (kbd "M-."))))
      (should queried))))

(ert-deftest config-test/typst-file-jump-tree-sitter-rejects-markup-and-raw-text ()
  (skip-unless (treesit-ready-p 'typst t))
  (dolist (content '("Prose \"lem|ma\""
                     "`\"lem|ma\"`"
                     "```typst\n#let name = \"lem|ma\"\n```"))
    (config-test/with-typst-completion content
      (config-test/file root "lemma.typ")
      (when (eq major-mode 'typst-ts-mode)
        (let (queried)
          (cl-letf (((symbol-function 'xref-find-definitions)
                     (lambda () (interactive) (setq queried t)))
                    ((symbol-function 'find-file)
                     (lambda (&rest _) (ert-fail "Markup opened a file"))))
            (call-interactively (key-binding (kbd "M-."))))
          (should queried))))))

(ert-deftest config-test/typst-file-jump-keeps-global-definition-key ()
  (with-temp-buffer
    (text-mode)
    (should (eq (key-binding (kbd "M-.")) #'xref-find-definitions))))

(provide 'typst-navigation-tests)
;;; typst-navigation-tests.el ends here
