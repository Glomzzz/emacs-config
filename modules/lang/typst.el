;;; typst.el --- Typst support, project roots, and language server selection -*- lexical-binding: t; -*-

(defun my/typst-local-project (dir)
  "Treat any directory containing a .typst-root file as a project root."
  (when-let ((root (locate-dominating-file dir ".typst-root")))
    (cons 'transient root)))

(defun my/typst-eglot-command ()
  "Pick an available Typst language server without downloading on startup."
  (eglot-alternatives
   (delq nil
         (list (and (boundp 'typst-ts-lsp-download-path)
                    typst-ts-lsp-download-path)
               "tinymist"
               "typst-lsp"))))

(add-hook 'project-find-functions #'my/typst-local-project)
(add-hook 'typst-ts-mode-hook #'eglot-ensure)

(use-package typst-ts-mode
  :mode ("\\.typ\\'" . typst-ts-mode))

(with-eval-after-load 'eglot
  (add-to-list 'eglot-server-programs
               `((typst-ts-mode) . ,(my/typst-eglot-command))))
