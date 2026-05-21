;;; racket.el --- Racket editing support and buffer-local diagnostics helpers -*- lexical-binding: t; -*-

(use-package racket-mode
  :mode ("\\.rkt\\'" "\\.rktl\\'")
  :hook ((racket-mode . racket-xp-mode)
         (racket-mode . my/lsp-buffer-setup)))
