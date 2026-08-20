;;; nix.el --- Nix language support -*- lexical-binding: t; -*-

(require 'packages)

(treesit/register-language 'nix)

(packages/declare 'nix-ts-mode)
(use-package nix-ts-mode
  :ensure nil
  :mode "\\.nix\\'"
  :hook ((nix-ts-mode . eglot-ensure)
         (nix-mode . eglot-ensure)))

(defun nix/eglot-workspace-configuration (_server)
  "Configure Nixd to format Nix buffers with Alejandra."
  (when (derived-mode-p 'nix-ts-mode 'nix-mode)
    '(:nixd (:formatting (:command ["alejandra" "-q" "-"])))))

(with-eval-after-load 'eglot
  ;; Keep the server choice deterministic when both `nil' and `nixd' are
  ;; installed, and handle both the Tree-sitter and fallback modes.
  (add-to-list 'eglot-server-programs '(nix-ts-mode . ("nixd")))
  (add-to-list 'eglot-server-programs '(nix-mode . ("nixd")))
  (setq-default eglot-workspace-configuration
                #'nix/eglot-workspace-configuration))

(defun nix/configure-apheleia ()
  "Use Alejandra for Nix buffers when Eglot is not formatting them."
  (setf (alist-get 'alejandra apheleia-formatters)
        '("alejandra" "-q" "-"))
  (setf (alist-get 'nix-ts-mode apheleia-mode-alist) 'alejandra)
  (setf (alist-get 'nix-mode apheleia-mode-alist) 'alejandra))

(with-eval-after-load 'apheleia
  (nix/configure-apheleia))

;;; nix.el ends here
