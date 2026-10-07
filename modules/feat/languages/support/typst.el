;;; typst.el --- Typst language support -*- lexical-binding: t; -*-

(require 'packages)

(defvar eglot-server-programs)
(defvar apheleia-formatters)
(defvar apheleia-mode-alist)

;; `treesit-auto' supplies the grammar source and remaps typst-mode to
;; typst-ts-mode when the grammar is installed.
(treesit/register-language 'typst)

(packages/declare 'typst-ts-mode)
(use-package typst-ts-mode
  :ensure nil
  :mode "\\.typ\\'"
  :hook ((typst-ts-mode . typst/eglot-ensure)
         (typst-mode . typst/eglot-ensure)
         (typst-ts-mode . format/mode-maybe)
         (typst-mode . format/mode-maybe)))

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
