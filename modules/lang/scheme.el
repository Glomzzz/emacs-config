;;; scheme.el --- Scheme editing defaults and language server wiring -*- lexical-binding: t; -*-

(defun my/scheme-lsp-server-available-p ()
  "Return non-nil when a Scheme language server is installed."
  (executable-find "scheme-langserver"))

(defun my/scheme-maybe-eglot-ensure ()
  "Start Eglot when a Scheme language server is available."
  (when (my/scheme-lsp-server-available-p)
    (my/eglot-ensure-idle)))

(add-to-list 'auto-mode-alist '("\\.ss\\'" . scheme-mode))
(add-to-list 'auto-mode-alist '("\\.scm\\'" . scheme-mode))
(add-hook 'scheme-mode-hook #'my/scheme-maybe-eglot-ensure)

;;; scheme.el ends here
