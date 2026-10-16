;;; pairs-tests.el --- Fingertip command-loop regressions -*- lexical-binding: t; -*-

(require 'ert)
(require 'cl-lib)
(require 'fingertip)
(require 'tempel)

(load (expand-file-name "scripts/patch-fingertip.el" user-emacs-directory)
      nil 'nomessage)

(defconst config-test/fingertip-optional-source
  (concat ";;; fingertip.el --- Optional integration fixture -*- lexical-binding: t; -*-\n"
          ";;; Code:\n"
          "(defun fingertip-test-optional-calls ()\n"
          "  (sgml-skip-tag-forward 1)\n"
          "  (sgml-skip-tag-backward 1)\n"
          "  (web-mode-element-beginning-position 1)\n"
          "  (web-mode-element-end-position 1)\n"
          "  (web-mode-element-parent-position 1)\n"
          "  (web-mode-insert-text-at-pos \"text\" 1)\n"
          "  (web-mode-element-parent)\n"
          "  (web-mode-element-vanish 1)\n"
          "  (ielm-return))\n")
  "Standalone calls to Fingertip's optional integration functions.")

(ert-deftest config-test/pairs-build-patch-is-idempotent ()
  (let ((file (make-temp-file "fingertip-patch-" nil ".el"
                              config-test/fingertip-optional-source)))
    (unwind-protect
        (progn
          (pairs/patch-fingertip file)
          (let ((patched (with-temp-buffer
                           (insert-file-contents file)
                           (buffer-string)))
                (timestamp (seconds-to-time 1000000)))
            (should (string-match-p "(declare-function sgml-skip-tag-forward" patched))
            (set-file-times file timestamp)
            (pairs/patch-fingertip file)
            (should (equal timestamp
                           (file-attribute-modification-time (file-attributes file))))
            (should (equal patched (with-temp-buffer
                                     (insert-file-contents file)
                                     (buffer-string))))))
      (delete-file file))))

(ert-deftest config-test/pairs-build-patch-preserves-upstream-declarations ()
  (let* ((upstream "(declare-function sgml-skip-tag-forward \"sgml-mode\" (count))\n")
         (file (make-temp-file "fingertip-upstream-" nil ".el"
                               (concat upstream config-test/fingertip-optional-source))))
    (unwind-protect
        (progn
          (pairs/patch-fingertip file)
          (with-temp-buffer
            (insert-file-contents file)
            (should (search-forward upstream nil t))
            (should-not (search-forward "(declare-function sgml-skip-tag-forward" nil t))))
      (delete-file file))))

(ert-deftest config-test/pairs-build-patch-rejects-unknown-layout-without-writing ()
  (let* ((original ";;; No Fingertip code marker here.\n")
         (file (make-temp-file "fingertip-layout-" nil ".el" original)))
    (unwind-protect
        (progn
          (should-error (pairs/patch-fingertip file))
          (should (equal original (with-temp-buffer
                                    (insert-file-contents file)
                                    (buffer-string)))))
      (delete-file file))))

(ert-deftest config-test/pairs-build-command-fixes-clean-worker-compilation ()
  (require 'package-vc)
  (should (or (eq package-vc-allow-build-commands t)
              (memq 'fingertip package-vc-allow-build-commands)))
  (let* ((source (alist-get 'fingertip packages/vc-sources))
         (directory (make-temp-file "fingertip build " t))
         (default-directory (file-name-as-directory directory))
         (file (expand-file-name "fingertip.el" directory)))
    (unwind-protect
        (progn
          (should (equal source (alist-get 'fingertip package-vc-selected-packages)))
          (with-temp-file file (insert config-test/fingertip-optional-source))
          (with-temp-buffer
            ;; Use the actual recipe in a fresh -Q worker so optional libraries
            ;; preloaded by the configuration cannot hide missing declarations.
            (let ((command
                   (concat (plist-get source :shell-command) " --eval "
                           (shell-quote-argument
                            (prin1-to-string
                             `(progn
                                (require 'bytecomp)
                                (setq byte-compile-warnings '(unresolved)
                                      byte-compile-error-on-warn t)
                                (unless (byte-compile-file ,file)
                                  (kill-emacs 1))
                                (dolist (feature '(sgml-mode web-mode ielm))
                                  (when (featurep feature)
                                    (error "Build eagerly loaded %s" feature)))))))))
              (should (zerop (call-process-shell-command command nil t))))
            (should-not (string-match-p "Warning\\|Error" (buffer-string))))
          (should (file-exists-p (concat file "c"))))
      (delete-directory directory t))))

(defmacro config-test/with-pair-buffer (mode &rest body)
  "Run BODY in a displayed temporary buffer using MODE.
Keyboard macros exercise the actual keymaps and delete-selection behavior."
  (declare (indent 1) (debug (form body)))
  `(let ((buffer (generate-new-buffer " *pair test*"))
         (treesit-auto-install nil)
         (corfu-auto nil))
     (unwind-protect
         (save-window-excursion
           (switch-to-buffer buffer)
           (cl-letf (((symbol-function 'eglot-ensure) #'ignore))
             (funcall ,mode))
           ,@body)
       (kill-buffer buffer))))

(defmacro config-test/with-fingertip (&rest body)
  "Run BODY in a TypeScript buffer with its real Tree-sitter parser."
  (declare (indent 0) (debug t))
  `(progn
     (when (getenv "EMACS_TEST_REQUIRE_GRAMMARS")
       (should (treesit-ready-p 'typescript t)))
     (skip-unless (treesit-ready-p 'typescript t))
     (config-test/with-pair-buffer #'typescript-ts-mode
       (should fingertip-mode)
       ,@body)))

(defun config-test/pair-type (text)
  "Type TEXT one key at a time through Emacs' command loop."
  (dolist (character (string-to-list text))
    (execute-kbd-macro (vector character))))

(ert-deftest config-test/pairs-only-fingertip-is-declared ()
  (should (memq 'fingertip packages/declared))
  (should-not (memq 'smartparens packages/declared))
  (should-not electric-pair-mode)
  (should (equal (plist-get (alist-get 'fingertip packages/vc-sources) :url)
                 "https://github.com/manateelazycat/fingertip")))

(ert-deftest config-test/pairs-enabled-with-real-language-parsers ()
  (dolist (fixture '((typescript . typescript-ts-mode)
                     (tsx . tsx-ts-mode)
                     (rust . rust-ts-mode)
                     (nix . nix-ts-mode)
                     (typst . typst-ts-mode)))
    (when (treesit-ready-p (car fixture) t)
      (config-test/with-pair-buffer (cdr fixture)
        (should (treesit-parser-list))
        (should fingertip-mode)
        (should-not (bound-and-true-p smartparens-mode))))))

(ert-deftest config-test/pairs-no-activation-without-parser ()
  (dolist (mode '(emacs-lisp-mode js-mode rust-mode conf-mode markdown-mode
                 org-mode text-mode fundamental-mode special-mode comint-mode))
    (config-test/with-pair-buffer mode
      (should-not (treesit-parser-list))
      (should-not fingertip-mode)))
  (config-test/with-pair-buffer #'emacs-lisp-mode
    (config-test/pair-type "(")
    (should (equal (buffer-string) "("))))

(ert-deftest config-test/pairs-exclude-read-only-large-and-minibuffers ()
  (dolist (kind '(read-only large minibuffer special process))
    (with-temp-buffer
      (let ((pairs/enabled-modes '(prog-mode special-mode comint-mode)))
        (pcase kind
          ('special (special-mode) (setq buffer-read-only nil))
          ('process (comint-mode))
          (_ (emacs-lisp-mode)))
        (pcase kind
          ('read-only (setq buffer-read-only t))
          ('large (insert (make-string buffers/feature-size-limit ?x))))
        (cl-letf (((symbol-function 'minibufferp)
                   (lambda (&optional _buffer) (eq kind 'minibuffer)))
                  ((symbol-function 'treesit-parser-list) (lambda (&rest _) '(parser))))
          (pairs/enable)
          (should-not fingertip-mode))))))

(ert-deftest config-test/pairs-file-opening-honors-parser-and-fallback ()
  (skip-unless (treesit-ready-p 'typescript t))
  (config-test/with-language-file "sample.ts" "const value = 1;\n"
    (should (eq major-mode 'typescript-ts-mode))
    (should fingertip-mode))
  (cl-letf (((symbol-function 'treesit-ready-p) (lambda (&rest _) nil)))
    (config-test/with-language-file "sample.ts" "const value = 1;\n"
      (should (eq major-mode 'typescript-mode))
      (should-not fingertip-mode))))

(ert-deftest config-test/pairs-insert-and-skip-brackets ()
  (dolist (pair '(("(" . ")") ("[" . "]") ("{" . "}")))
    (config-test/with-fingertip
      (config-test/pair-type (car pair))
      (should (equal (buffer-string) (concat (car pair) (cdr pair))))
      (should (= (point) 2))
      (config-test/pair-type (cdr pair))
      (should (equal (buffer-string) (concat (car pair) (cdr pair))))
      (should (= (point) 3)))))

(ert-deftest config-test/pairs-insert-chinese-brackets ()
  (dolist (pair '(("（" . "）") ("「" . "」") ("【" . "】")))
    (config-test/with-fingertip
      (config-test/pair-type (car pair))
      (should (equal (buffer-string) (concat (car pair) (cdr pair))))
      (should (= (point) 2)))))

(ert-deftest config-test/pairs-quote-insertion-uses-upstream-escaping ()
  (config-test/with-fingertip
    (config-test/pair-type "\"hello\"")
    ;; Fingertip escapes a double quote inside a string instead of skipping
    ;; the closing quote.  Move right to leave the string.
    (should (equal (buffer-string) "\"hello\\\"\""))
    (should (= (point) (1- (point-max)))))
  (config-test/with-fingertip
    (config-test/pair-type "'")
    (should (equal (buffer-string) "''"))))

(ert-deftest config-test/pairs-backspace-deletes-empty-pair ()
  (dolist (opener '("(" "[" "{" "\""))
    (config-test/with-fingertip
      (config-test/pair-type opener)
      (execute-kbd-macro (kbd "DEL"))
      (should (equal (buffer-string) "")))))

(ert-deftest config-test/pairs-protect-nonempty-delimiters ()
  (config-test/with-fingertip
    (insert "(foo)")
    (goto-char 2)
    (execute-kbd-macro (kbd "DEL"))
    (should (equal (buffer-string) "(foo)"))
    (goto-char (point-min))
    (execute-kbd-macro (kbd "C-d"))
    (should (equal (buffer-string) "(foo)"))
    (should (= (point) 2))))

(ert-deftest config-test/pairs-wrap-round-selection-and-normal-replacement ()
  (config-test/with-fingertip
    (insert "foo")
    (set-mark (point-min))
    (setq mark-active t)
    (let ((transient-mark-mode t)) (config-test/pair-type "("))
    (should (equal (buffer-string) "(foo)")))
  (config-test/with-fingertip
    (insert "foo")
    (set-mark (point-min))
    (setq mark-active t)
    (let ((transient-mark-mode t)) (config-test/pair-type "x"))
    (should (equal (buffer-string) "x"))))

(ert-deftest config-test/pairs-wrap-and-unwrap-bindings ()
  (config-test/with-fingertip
    (insert "foo")
    (goto-char (point-min))
    (execute-kbd-macro (kbd "C-c p ("))
    (should (equal (string-trim (buffer-string)) "(foo)"))
    (goto-char 2)
    (execute-kbd-macro (kbd "C-c p u"))
    (should (equal (string-trim (buffer-string)) "foo"))))

(ert-deftest config-test/pairs-space-and-newline-between-braces ()
  (config-test/with-fingertip
    (config-test/pair-type "{ ")
    (should (equal (buffer-string) "{  }"))
    (should (= (point) 3)))
  (config-test/with-fingertip
    (config-test/pair-type "{")
    (execute-kbd-macro (kbd "RET"))
    (should (equal (buffer-string)
                   (concat "{\n" (make-string typescript-ts-mode-indent-offset ?\s)
                           "\n}")))))

(ert-deftest config-test/pairs-comments-and-operators-stay-literal ()
  (config-test/with-fingertip
    (insert "// comment ")
    (config-test/pair-type "(\"'")
    (should (equal (buffer-string) "// comment (\"'")))
  (dolist (operator '("<" ">" "<<" ">>" "=>" "->" "%" "="))
    (config-test/with-fingertip
      (config-test/pair-type (concat "a" operator "b"))
      (should (equal (buffer-string) (concat "a" operator "b"))))))

(ert-deftest config-test/pairs-rust-apostrophes-stay-literal ()
  (skip-unless (treesit-ready-p 'rust t))
  (dolist (text '("'" "'a" "'static" "'outer: loop {}" "&'a"
                  "fn f<'a" "Box<'a" "'x'" "let c = 'x'"))
    (config-test/with-pair-buffer #'rust-ts-mode
      (should fingertip-mode)
      (config-test/pair-type text)
      (should (equal (buffer-string) text)))))

(ert-deftest config-test/pairs-toggle-literal-insertion-and-help ()
  (config-test/with-fingertip
    (should (eq (key-binding (kbd "C-c p ?")) #'pairs/help))
    (execute-kbd-macro (kbd "C-c p q ("))
    (should (equal (buffer-string) "("))
    (execute-kbd-macro (kbd "C-c p t"))
    (should-not fingertip-mode)
    (config-test/pair-type "[")
    (should (equal (buffer-string) "(["))
    (should (eq (key-binding (kbd "C-q")) #'quoted-insert))))

(ert-deftest config-test/pairs-preserve-snippet-eldoc-and-register-keys ()
  (dolist (key '("M-{" "M-}" "M-n" "M-p" "M-'" "M-:" "C-j" "%" "="))
    (should-not (lookup-key fingertip-mode-map (kbd key)))))

(ert-deftest config-test/pairs-do-not-reprocess-snippet-insertion ()
  (config-test/with-fingertip
    (tempel-insert '("(" (p "value") ")"))
    (should (equal (buffer-string) "(value)"))
    (tempel-done)))

(ert-deftest config-test/pairs-so-long-disables-and-restores-fingertip ()
  (config-test/with-fingertip
    (should (memq 'fingertip-mode so-long-minor-modes))
    (so-long 'so-long-minor-mode)
    (should-not fingertip-mode)
    (let ((noninteractive nil)) (so-long-revert))
    (should fingertip-mode)))

(provide 'pairs-tests)
;;; pairs-tests.el ends here
