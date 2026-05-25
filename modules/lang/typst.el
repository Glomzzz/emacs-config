;;; typst.el --- Typst support, project roots, and language server selection -*- lexical-binding: t; -*-

(define-derived-mode typst-mode text-mode "Typst"
  "Fallback Typst mode used until the tree-sitter grammar is available.")

(defun my/typst-use-ts-mode-p ()
  "Return non-nil when `typst-ts-mode' is ready for use."
  (and (require 'treesit nil t)
       (fboundp 'typst-ts-mode)
       (treesit-ready-p 'typst)))

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

(defun my/register-typst-auto-mode ()
  "Prefer `typst-mode` until the tree-sitter grammar is ready."
  (setq auto-mode-alist
        (cl-remove-if (lambda (entry)
                        (and (stringp (car entry))
                             (string= (car entry) "\\.typ\\'")))
                      auto-mode-alist))
  (add-to-list 'auto-mode-alist
               `("\\.typ\\'" . ,(if (my/typst-use-ts-mode-p)
                                    'typst-ts-mode
                                  'typst-mode))))

(my/register-typst-auto-mode)
(add-hook 'project-find-functions #'my/typst-local-project)
(add-hook 'typst-mode-hook #'eglot-ensure)
(add-hook 'typst-ts-mode-hook #'eglot-ensure)

(with-eval-after-load 'typst-ts-mode
  (my/register-typst-auto-mode))

(with-eval-after-load 'eglot
  (add-to-list 'eglot-server-programs
               `(typst-mode . ,(my/typst-eglot-command)))
  (add-to-list 'eglot-server-programs
               `((typst-ts-mode) . ,(my/typst-eglot-command))))
