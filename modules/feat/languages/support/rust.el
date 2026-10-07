;;; rust.el --- Rust language support -*- lexical-binding: t; -*-

(require 'packages)

(declare-function sp-local-pair "smartparens" (modes open close &rest arguments))
(defvar eglot-server-programs)
(defvar apheleia-formatters)
(defvar apheleia-mode-alist)

;; rust-ts-mode is built into Emacs; rust-mode is the non-Tree-sitter
;; fallback and comes from MELPA.
(treesit/register-language 'rust)

(packages/declare 'rust-mode)
(use-package rust-mode
  :ensure nil
  :mode "\\.rs\\'"
  :hook (rust-mode . eglot-ensure))

;; rust-ts-mode is built into Emacs, so no package is declared.
(add-hook 'rust-ts-mode-hook #'eglot-ensure)

(with-eval-after-load 'eglot
  ;; Keep the server choice deterministic: rust-analyzer for both modes.
  (add-to-list 'eglot-server-programs '(rust-mode . ("rust-analyzer")))
  (add-to-list 'eglot-server-programs '(rust-ts-mode . ("rust-analyzer"))))

(with-eval-after-load 'smartparens-config
  (require 'smartparens-rust)
  ;; Preserve upstream lifetime/character rules, but make angle-bracket
  ;; insertion explicit so compact comparisons such as `a<b` stay literal.
  (sp-local-pair '(rust-mode rust-ts-mode) "<" ">" :actions '(wrap)))

(defun rust/configure-apheleia ()
  "Use rustfmt for Rust buffers when Eglot is not formatting them."
  (setf (alist-get 'rustfmt apheleia-formatters)
        '("rustfmt" "--emit" "stdout"))
  (setf (alist-get 'rust-mode apheleia-mode-alist) 'rustfmt)
  (setf (alist-get 'rust-ts-mode apheleia-mode-alist) 'rustfmt))

(with-eval-after-load 'apheleia
  (rust/configure-apheleia))

;; Dape already ships mode-scoped `lldb-dap' and `lldb-vscode'
;; configurations for the Rust modes, so no adapter registration is needed
;; here.  Install LLDB (or an equivalent adapter) to use them.

;;; rust.el ends here
