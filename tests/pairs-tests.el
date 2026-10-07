;;; pairs-tests.el --- Interactive pairing regressions -*- lexical-binding: t; -*-

(require 'ert)
(require 'smartparens-config)
(require 'tempel)

(defmacro config-test/with-pair-buffer (mode &rest body)
  "Run BODY in a displayed temporary buffer using MODE.
Keyboard macros exercise the actual pre/post-command hooks and keymaps,
including delete-selection integration, rather than calling pair helpers."
  (declare (indent 1) (debug (form body)))
  `(let ((buffer (generate-new-buffer " *pair test*"))
         ;; The runner intentionally isolates grammar caches too.  Pairing
         ;; must not download grammars or prompt while testing fallback modes.
         (treesit-auto-install nil))
     (unwind-protect
         (save-window-excursion
           (switch-to-buffer buffer)
           ;; No test buffer visits a file, so Eglot never starts a server.
           (funcall ,mode)
           ,@body)
       (kill-buffer buffer))))

(defun config-test/pair-type (text)
  "Type TEXT one key at a time through Emacs' command loop."
  (dolist (character (string-to-list text))
    (execute-kbd-macro (vector character))))

(ert-deftest config-test/pairs-pin-is-applied-before-archive-selection ()
  ;; `package-initialize' reads metadata before feature declarations run.
  ;; A late pin must not accidentally leave the old NonGNU candidate first.
  (when-let* ((descriptor (cadr (assq 'smartparens package-archive-contents))))
    (should (equal (package-desc-archive descriptor) "melpa"))))

(ert-deftest config-test/pairs-only-one-engine-and-not-strict ()
  (should-not electric-pair-mode)
  (should (equal (alist-get 'smartparens package-pinned-packages) "melpa"))
  (config-test/with-pair-buffer #'emacs-lisp-mode
    (should smartparens-mode)
    (should-not smartparens-strict-mode)
    (should-not (local-variable-p 'electric-pair-mode))))

(ert-deftest config-test/pairs-enabled-in-structured-modes ()
  (dolist (mode '(emacs-lisp-mode js-mode conf-mode markdown-mode org-mode))
    (config-test/with-pair-buffer mode
      (should smartparens-mode))))

(ert-deftest config-test/pairs-leave-prose-process-and-special-buffers-alone ()
  (dolist (mode '(text-mode fundamental-mode special-mode comint-mode))
    (config-test/with-pair-buffer mode
      (should-not smartparens-mode)))
  (config-test/with-pair-buffer #'text-mode
    (config-test/pair-type "don't (")
    (should (equal (buffer-string) "don't ("))))

(ert-deftest config-test/pairs-exclude-read-only-large-and-minibuffers ()
  (dolist (kind '(read-only large minibuffer))
    (with-temp-buffer
      (pcase kind
        ('read-only (setq buffer-read-only t))
        ('large (insert (make-string (* 2 1024 1024) ?x))))
      (cl-letf (((symbol-function 'minibufferp)
                 (lambda (&optional _buffer) (eq kind 'minibuffer))))
        (pairs/enable)
        (should-not (bound-and-true-p smartparens-mode))))))

(ert-deftest config-test/pairs-insert-and-skip-matching-delimiters ()
  (dolist (opener '("(" "[" "{" "\""))
    (config-test/with-pair-buffer #'emacs-lisp-mode
      (let ((closer (cdr (assoc opener '(("(" . ")") ("[" . "]")
                                       ("{" . "}") ("\"" . "\""))))))
        (config-test/pair-type opener)
        (should (equal (buffer-string) (concat opener closer)))
        (should (= (point) 2))
        (config-test/pair-type closer)
        (should (equal (buffer-string) (concat opener closer)))
        (should (= (point) 3))))))

(ert-deftest config-test/pairs-skip-existing-balanced-closer ()
  (config-test/with-pair-buffer #'emacs-lisp-mode
    (insert "(foo)")
    (goto-char 5)
    (config-test/pair-type ")")
    (should (equal (buffer-string) "(foo)"))
    (should (= (point) 6))))

(ert-deftest config-test/pairs-do-not-jump-over-expression-contents ()
  (config-test/with-pair-buffer #'emacs-lisp-mode
    (insert "(foo bar)")
    (goto-char 5)
    (config-test/pair-type ")")
    (should (equal (buffer-string) "(foo) bar)"))
    (should (= (point) 6))))

(ert-deftest config-test/pairs-allow-unmatched-closers ()
  (config-test/with-pair-buffer #'emacs-lisp-mode
    (config-test/pair-type ")")
    (should (equal (buffer-string) ")"))))

(ert-deftest config-test/pairs-backspace-deletes-empty-pair ()
  (config-test/with-pair-buffer #'emacs-lisp-mode
    (config-test/pair-type "(")
    (execute-kbd-macro (kbd "DEL"))
    (should (equal (buffer-string) ""))))

(ert-deftest config-test/pairs-nonempty-pairs-allow-normal-deletion ()
  (config-test/with-pair-buffer #'emacs-lisp-mode
    (insert "(foo)")
    (goto-char 2)
    (execute-kbd-macro (kbd "DEL"))
    (should (equal (buffer-string) "foo)"))))

(ert-deftest config-test/pairs-wrap-selection-instead-of-replacing-it ()
  (config-test/with-pair-buffer #'emacs-lisp-mode
    (insert "foo")
    (set-mark (point-min))
    (setq mark-active t)
    (let ((transient-mark-mode t))
      (config-test/pair-type "("))
    (should (equal (buffer-string) "(foo)"))))

(ert-deftest config-test/pairs-preserve-normal-selection-replacement ()
  (config-test/with-pair-buffer #'emacs-lisp-mode
    (insert "foo")
    (set-mark (point-min))
    (setq mark-active t)
    (let ((transient-mark-mode t))
      (config-test/pair-type "x"))
    (should (equal (buffer-string) "x"))))

(ert-deftest config-test/pairs-lisp-quote-and-backquote-are-prefixes ()
  (dolist (prefix '("'" "`"))
    (config-test/with-pair-buffer #'emacs-lisp-mode
      (config-test/pair-type (concat prefix "foo"))
      (should (equal (buffer-string) (concat prefix "foo"))))))

(ert-deftest config-test/pairs-haskell-primes-and-character-literals ()
  (dolist (mode '(haskell-mode haskell-literate-mode))
    (config-test/with-pair-buffer mode
      (insert "map")
      (config-test/pair-type "'")
      (should (equal (buffer-string) "map'"))))
  (config-test/with-pair-buffer #'haskell-mode
    (config-test/pair-type "'a'")
    (should (equal (buffer-string) "'a'"))))

(ert-deftest config-test/pairs-rust-lifetimes-and-character-literals ()
  (dolist (context '("&" "fn f<"))
    (config-test/with-pair-buffer #'rust-mode
      (insert context)
      (config-test/pair-type "'a")
      (should (equal (buffer-string) (concat context "'a")))))
  (config-test/with-pair-buffer #'rust-mode
    (config-test/pair-type "'x'")
    (should (equal (buffer-string) "'x'"))))

(ert-deftest config-test/pairs-comments-and-markdown-apostrophes ()
  (config-test/with-pair-buffer #'js-mode
    (insert "// don")
    (config-test/pair-type "'t")
    (should (equal (buffer-string) "// don't")))
  (dolist (mode '(markdown-mode org-mode))
    (config-test/with-pair-buffer mode
      (insert "don")
      (config-test/pair-type "'t")
      (should (equal (buffer-string) "don't")))))

(ert-deftest config-test/pairs-manually-escaped-quotes-stay-literal ()
  (config-test/with-pair-buffer #'js-mode
    (config-test/pair-type "\"hello\\\"world\"")
    (should (equal (buffer-string) "\"hello\\\"world\""))
    (should (= (point) (point-max)))))

(ert-deftest config-test/pairs-comparisons-shifts-and-arrows-are-literal ()
  (dolist (mode '(js-mode typescript-mode rust-mode))
    (dolist (operator '("<" ">" "<<" ">>" "=>" "->"))
      (config-test/with-pair-buffer mode
        (insert "a")
        (config-test/pair-type (concat operator "b"))
        (should (equal (buffer-string) (concat "a" operator "b")))))))

(ert-deftest config-test/pairs-angle-policy-includes-tree-sitter-modes ()
  (dolist (mode '(js-mode js-ts-mode typescript-mode typescript-ts-mode
                 tsx-ts-mode rust-mode rust-ts-mode))
    (should (equal (sp-get-pair-definition "<" mode :actions) '(wrap)))))

(ert-deftest config-test/pairs-explicit-angle-wrap ()
  (config-test/with-pair-buffer #'typescript-mode
    (insert "T")
    (goto-char (point-min))
    (execute-kbd-macro (kbd "C-c p <"))
    (should (equal (string-trim (buffer-string)) "<T>"))))

(ert-deftest config-test/pairs-unsupported-angle-wrap-leaves-text-untouched ()
  (config-test/with-pair-buffer #'emacs-lisp-mode
    (insert "foo")
    (goto-char (point-min))
    (should-error (pairs/wrap-angle) :type 'user-error)
    (should (equal (buffer-string) "foo"))
    (should (= (point) (point-min)))))

(ert-deftest config-test/pairs-markdown-and-org-markup ()
  (config-test/with-pair-buffer #'markdown-mode
    (config-test/pair-type "`code`")
    (should (equal (buffer-string) "`code`")))
  (config-test/with-pair-buffer #'markdown-mode
    (config-test/pair-type "* item")
    (should (equal (buffer-string) "* item")))
  (config-test/with-pair-buffer #'org-mode
    (config-test/pair-type "* Heading")
    (should (equal (buffer-string) "* Heading")))
  (config-test/with-pair-buffer #'org-mode
    (config-test/pair-type "~code~")
    (should (equal (buffer-string) "~code~"))))

(ert-deftest config-test/pairs-wrap-slurp-barf-and-splice-bindings ()
  (config-test/with-pair-buffer #'emacs-lisp-mode
    (insert "foo bar")
    (goto-char (point-min))
    (execute-kbd-macro (kbd "C-c p ("))
    (should (equal (buffer-string) "(foo) bar"))
    (execute-kbd-macro (kbd "C-c p s"))
    (should (equal (buffer-string) "(foo bar)"))
    (execute-kbd-macro (kbd "C-c p b"))
    (should (equal (buffer-string) "(foo) bar"))
    (execute-kbd-macro (kbd "C-c p u"))
    (should (equal (buffer-string) "foo bar"))))

(ert-deftest config-test/pairs-toggle-and-literal-insertion ()
  (config-test/with-pair-buffer #'emacs-lisp-mode
    (execute-kbd-macro (kbd "C-c p q ("))
    (should (equal (buffer-string) "("))
    (execute-kbd-macro (kbd "C-c p t"))
    (should-not smartparens-mode)
    (config-test/pair-type "[")
    (should (equal (buffer-string) "(["))
    (should (eq (key-binding (kbd "C-q")) #'quoted-insert))))

(ert-deftest config-test/pairs-do-not-reprocess-snippet-insertion ()
  (config-test/with-pair-buffer #'emacs-lisp-mode
    (require 'tempel)
    (tempel-insert '("(" (p "value") ")"))
    (should (equal (buffer-string) "(value)"))
    (tempel-done)))

(provide 'pairs-tests)
;;; pairs-tests.el ends here
