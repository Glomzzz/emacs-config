;;; java.el --- Java tree-sitter mode and Eglot integration -*- lexical-binding: t; -*-

(add-hook 'java-ts-mode-hook #'eglot-ensure)
