;;; typst-completion-tests.el --- Typst path completion regressions -*- lexical-binding: t; -*-

(require 'ert)
(require 'cl-lib)
(require 'cape)

(defmacro config-test/with-typst-completion (content &rest body)
  "Test CONTENT and BODY in real Typst file buffers, with and without grammar.
A vertical bar in CONTENT marks point; the fixture has a nested source file."
  (declare (indent 1) (debug t))
  `(let ((ready (treesit-ready-p 'typst t))
         (ready-p (symbol-function 'treesit-ready-p))
         (treesit-auto-install nil))
     (dolist (grammar (if ready '(nil t) '(nil)))
       (cl-letf (((symbol-function 'treesit-ready-p)
                  (lambda (language &optional quiet)
                    (and grammar (funcall ready-p language quiet)))))
         (config-test/with-language-file "book/chapter.typ" ,content
           (should (eq major-mode (if grammar 'typst-ts-mode 'typst-mode)))
           (config-test/file root ".typst-root")
           (config-test/file root "assets/logo.png")
           (config-test/file root "book/local.txt")
           (config-test/file root "book/pictures/logo.png")
           (config-test/file root "book/pictures/logo two.png")
           (config-test/file root "book/pictures/图像.png")
           (config-test/file root "book/pictures/a\"quote.png")
           (config-test/file root "book/pictures/a\\backslash.png")
           (goto-char (point-min))
           (search-forward "|")
           (delete-char -1)
           ,@body)))))

(defun config-test/typst-path-candidates (capf)
  "Return CAPF's candidates for the input currently in the buffer."
  (should capf)
  (all-completions (buffer-substring-no-properties (nth 0 capf) (nth 1 capf))
                   (nth 2 capf) (plist-get (nthcdr 3 capf) :predicate)))

(ert-deftest config-test/typst-path-relative-and-parent-prefixes ()
  (dolist (fixture '(("./|" . "local.txt")
                     ("../|" . "assets/")
                     ("..|" . "../")
                     ("./pictures/lo|" . "logo.png")))
    (config-test/with-typst-completion (concat "#let path = \"" (car fixture) "\"")
      (let* ((original (point))
             (capf (typst/path-completion-at-point)))
        (should (= (point) original))
        (should (member (cdr fixture) (config-test/typst-path-candidates capf)))
        (should (eq (plist-get (nthcdr 3 capf) :company-prefix-length) t))
        (should (eq (plist-get (nthcdr 3 capf) :exclusive) t))))))

(ert-deftest config-test/typst-path-slash-starts-at-document-root ()
  (dolist (fixture '(("/|" . "assets/")
                     ("/assets/lo|" . "logo.png")))
    (config-test/with-typst-completion (concat "#let path = \"" (car fixture) "\"")
      ;; Even when a nearer unrelated marker exists, / is the Typst root.
      (config-test/file root "book/package.json" "{}")
      (let ((capf (typst/path-completion-at-point)))
        (should (member (cdr fixture) (config-test/typst-path-candidates capf)))
        (should-not (member "local.txt" (config-test/typst-path-candidates capf)))
        (should (eq (char-before (car capf)) ?/))))))

(ert-deftest config-test/typst-path-root-falls-back-without-marker ()
  (config-test/with-typst-completion "#let path = \"/|\""
    (delete-file (expand-file-name ".typst-root" root))
    (let ((locate-dominating-stop-dir-regexp
           (concat "\\`" (regexp-quote root) "\\'")))
      (should (member "local.txt"
                      (config-test/typst-path-candidates
                       (typst/path-completion-at-point)))))))

(ert-deftest config-test/typst-path-root-falls-back-to-normal-project ()
  (config-test/with-typst-completion "#let path = \"/|\""
    (delete-file (expand-file-name ".typst-root" root))
    (config-test/file root "package.json" "{}")
    (should (member "assets/"
                    (config-test/typst-path-candidates
                     (typst/path-completion-at-point))))))

(ert-deftest config-test/typst-path-root-prefers-nested-typst-marker ()
  (config-test/with-typst-completion "#let path = \"/|\""
    (config-test/file root "book/.typst-root")
    (let ((candidates (config-test/typst-path-candidates
                       (typst/path-completion-at-point))))
      (should (member "local.txt" candidates))
      (should-not (member "assets/" candidates)))))

(ert-deftest config-test/typst-path-relative-base-is-source-not-working-directory ()
  (config-test/with-typst-completion "#let path = \"./|\""
    (let ((default-directory root))
      (should (member "local.txt"
                      (config-test/typst-path-candidates
                       (typst/path-completion-at-point)))))))

(ert-deftest config-test/typst-path-spaces-and-escaped-filenames ()
  (dolist (fixture '(("./pictures/logo |" . "logo two.png")
                     ("./pictures/图|" . "图像.png")
                     ("./pictures/a|" . "a\\\"quote.png")
                     ("./pictures/a|" . "a\\\\backslash.png")
                     ("./pictures/a\\\"q|" . "a\\\"quote.png")
                     ("./pictures/a\\\\b|" . "a\\\\backslash.png")))
    (config-test/with-typst-completion (concat "#let path = \"" (car fixture) "\"")
      (let ((capf (typst/path-completion-at-point)))
        (should (member (cdr fixture) (config-test/typst-path-candidates capf)))
        (should (string-prefix-p "./pictures/"
                                 (buffer-substring-no-properties
                                  (car capf) (cadr capf))))))))

(ert-deftest config-test/typst-path-completion-keeps-quotes-and-prefix ()
  (dolist (fixture '(("./pictures/logo t|" . "./pictures/logo two.png")
                     ("/assets/log|" . "/assets/logo.png")
                     ("./pictures/a\\\"quo|" . "./pictures/a\\\"quote.png")
                     ("./pictures/a\\\\back|" . "./pictures/a\\\\backslash.png")))
    (config-test/with-typst-completion (concat "#let path = \"" (car fixture) "\"")
      (let ((completion-at-point-functions '(typst/path-completion-at-point))
            (completion-in-region-function #'completion--in-region)
            (completion-cycle-threshold nil))
        (should (completion-at-point))
        (should (equal (buffer-string)
                       (concat "#let path = \"" (cdr fixture) "\"")))))))

(ert-deftest config-test/typst-path-completion-replaces-existing-suffix ()
  (config-test/with-typst-completion "#let path = \"/assets/log|.png\""
    (let ((completion-at-point-functions '(typst/path-completion-at-point))
          (completion-in-region-function #'completion--in-region))
      (should (completion-at-point))
      (should (equal (buffer-string) "#let path = \"/assets/logo.png\"")))))

(ert-deftest config-test/typst-path-directory-completion-continues ()
  (config-test/with-typst-completion "#let path = \"./pict|\""
    (let ((completion-at-point-functions '(typst/path-completion-at-point))
          (completion-in-region-function #'completion--in-region))
      (should (completion-at-point))
      (should (equal (buffer-string) "#let path = \"./pictures/\""))
      (should (member "logo.png"
                      (config-test/typst-path-candidates
                       (typst/path-completion-at-point)))))))

(ert-deftest config-test/typst-path-context-leaves-normal-completion-alone ()
  (dolist (content '("#let path = \"hello|\""
                     "#let path = \"prefix ./pictures/lo|\""
                     "#let path = \"https://example.org/lo|\""
                     "#let path = \"@preview/example|\""
                     "#let path = \".|\""
                     "#let path = \"./pictures/logo.png\"|"
                     "// \"./pictures/lo|\""
                     "/* \"./pictures/lo|\" */"
                     "./pictures/lo|"))
    (config-test/with-typst-completion content
      (should-not (typst/path-completion-at-point)))))

(ert-deftest config-test/typst-path-tree-sitter-rejects-markup-and-raw-quotes ()
  (skip-unless (treesit-ready-p 'typst t))
  (dolist (content '("Prose \"./pictures/lo|\""
                     "`\"./pictures/lo|\"`"
                     "```typst\n#let x = \"./pictures/lo|\"\n```"))
    (config-test/with-typst-completion content
      (when (eq major-mode 'typst-ts-mode)
        (should-not (typst/path-completion-at-point))))))

(ert-deftest config-test/typst-path-tree-sitter-ignores-earlier-markup-quotes ()
  (skip-unless (treesit-ready-p 'typst t))
  (dolist (prefix '("Prose \"unbalanced\n" "`raw \" quote`\n"))
    (config-test/with-typst-completion
        (concat prefix "#let path = \"./pictures/lo|\"")
      (when (eq major-mode 'typst-ts-mode)
        (should (member "logo.png"
                        (config-test/typst-path-candidates
                         (typst/path-completion-at-point))))))))

(ert-deftest config-test/typst-path-unclosed-string-completes ()
  (config-test/with-typst-completion "#let path = \"./pictures/lo|"
    (should (member "logo.png"
                    (config-test/typst-path-candidates
                     (typst/path-completion-at-point))))))

(ert-deftest config-test/typst-path-corfu-auto-accepts-short-prefixes ()
  (require 'corfu)
  (dolist (prefix '("./" ".." "/"))
    (config-test/with-typst-completion (concat "#let path = \"" prefix "|\"")
      ;; Use Corfu's real adapter with an intentionally larger auto threshold.
      (let ((result (corfu--capf-wrapper #'typst/path-completion-at-point 4)))
        (should (eq (car result) #'typst/path-completion-at-point))
        (should (alist-get 'corfu--candidates
                           (plist-get (nthcdr 4 result) :corfu--state)))))))

(ert-deftest config-test/typst-path-non-path-still-uses-eglot ()
  (config-test/with-typst-completion "#let x = sym|"
    (let (queried)
      (add-hook 'completion-at-point-functions #'eglot-completion-at-point 0 t)
      (cl-letf (((symbol-function 'eglot-completion-at-point)
                 (lambda ()
                   (setq queried t)
                   (list (- (point) 3) (point) '("symbol")))))
        (let ((completion-in-region-function (lambda (&rest _) t)))
          (should (completion-at-point))))
      (should queried))))

(ert-deftest config-test/typst-path-priority-survives-eglot-lifecycle ()
  (config-test/with-typst-completion "#let path = \"./pictures/lo|\""
    (should (memq #'typst/path-completion-at-point completion-at-point-functions))
    (should-not (memq #'cape-file completion-at-point-functions))
    ;; Reproduce Eglot installing its CAPF, then its public lifecycle hook.
    (add-hook 'completion-at-point-functions #'eglot-completion-at-point nil t)
    (cl-letf (((symbol-function 'lsp/format-on-save) #'ignore)
              ((symbol-function 'completion/eldoc-popup-maybe) #'ignore))
      (run-hooks 'eglot-managed-mode-hook))
    (should (eq (car completion-at-point-functions) #'typst/path-completion-at-point))
    (should (memq #'eglot-completion-at-point completion-at-point-functions))
    (typst/setup-completion)
    (should (= 1 (cl-count #'typst/path-completion-at-point
                           completion-at-point-functions)))
    (cl-letf (((symbol-function 'eglot-completion-at-point)
               (lambda () (ert-fail "Path completion queried the language server"))))
      (let ((completion-in-region-function (lambda (&rest _) t)))
        (should (completion-at-point))))))

(provide 'typst-completion-tests)
;;; typst-completion-tests.el ends here
