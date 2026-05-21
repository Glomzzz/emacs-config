;;; rust.el --- Rust tree-sitter mode and Eglot integration -*- lexical-binding: t; -*-

(add-hook 'rust-ts-mode-hook #'eglot-ensure)
