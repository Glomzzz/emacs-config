;;; environment.el --- Project environment integration -*- lexical-binding: t; -*-

(require 'packages)

(packages/declare 'envrc)
(use-package envrc
  :ensure nil
  :custom
  ;; Direnv only needs to inspect buffers where source/project environments are
  ;; meaningful.  This avoids a globalized hook on Dired, Magit, and UI buffers.
  (envrc-global-modes '(prog-mode text-mode conf-mode eshell-mode))
  :commands (envrc-mode envrc-allow envrc-deny envrc-reload)
  :init
  (when (executable-find "direnv")
    (envrc-global-mode 1)
    (define-key global-map (kbd "C-c e") envrc-command-map)))

;;; environment.el ends here
