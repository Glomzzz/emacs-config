;;; typst.el --- Typst language support -*- lexical-binding: t; -*-

(require 'packages)

(defvar eglot-server-programs)
(defvar apheleia-formatters)
(defvar apheleia-mode-alist)

;; Enter a grammar-free mode first so treesit-auto can offer installation
;; after mode selection, rather than typst-ts-mode failing before its hooks.
(define-derived-mode typst-mode text-mode "Typst (fallback)"
  "Edit Typst as text when its Tree-sitter grammar is unavailable.
Tinymist and Typstyle remain available.  Install the grammar and reopen
or revert the buffer for syntax-aware `typst-ts-mode'.")

(treesit/register-language 'typst)

(packages/declare 'typst-ts-mode)
(use-package typst-ts-mode
  :ensure nil
  :mode ("\\.typ\\'" . typst-mode)
  :hook ((typst-ts-mode . typst/eglot-ensure)
         (typst-mode . typst/eglot-ensure)
         (typst-ts-mode . format/mode-maybe)
         (typst-mode . format/mode-maybe))
  :config
  ;; The package also adds a direct association when loaded.  Keep the safe
  ;; fallback first even if the grammar disappears later in this session.
  (add-to-list 'auto-mode-alist '("\\.typ\\'" . typst-mode)))

(defun typst/eglot-workspace-configuration (_server)
  "Configure Tinymist to use Typstyle for Typst formatting."
  '(:tinymist (:formatterMode "typstyle")))

(defun typst/eglot-ensure ()
  "Start Tinymist for Typst buffers."
  (eglot-ensure))

(with-eval-after-load 'eglot
  ;; Tinymist is the language server for both the fallback and Tree-sitter
  ;; modes.  The explicit `lsp' subcommand is unnecessary; it is the default.
  (add-to-list 'eglot-server-programs '(typst-mode . ("tinymist")))
  (add-to-list 'eglot-server-programs '(typst-ts-mode . ("tinymist")))
  (lsp/register-workspace-configuration '(typst-mode typst-ts-mode)
                                        #'typst/eglot-workspace-configuration))

(defun typst/configure-apheleia ()
  "Use Typstyle for Typst buffers when Eglot is not formatting them."
  (setf (alist-get 'typstyle apheleia-formatters)
        '("typstyle"))
  (setf (alist-get 'typst-mode apheleia-mode-alist) 'typstyle)
  (setf (alist-get 'typst-ts-mode apheleia-mode-alist) 'typstyle))

(with-eval-after-load 'apheleia
  (typst/configure-apheleia))

;;; typst.el ends here
