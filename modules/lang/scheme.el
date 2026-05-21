;;; scheme.el --- Scheme editing defaults and language server wiring -*- lexical-binding: t; -*-

(setq geiser-mit-binary "/home/glom/.nix-profile/bin/scheme"
      geiser-active-implementations '(mit))

(add-to-list 'auto-mode-alist '("\\.ss\\'" . scheme-mode))
(add-to-list 'auto-mode-alist '("\\.scm\\'" . scheme-mode))
