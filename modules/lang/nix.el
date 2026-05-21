;;; nix.el --- Nix tree-sitter mode and Eglot integration -*- lexical-binding: t; -*-

(use-package nix-ts-mode
  :mode "\\.nix\\'")

(add-hook 'nix-ts-mode-hook #'eglot-ensure)
