;;; terminal.el --- Vterm terminal integration -*- lexical-binding: t; -*-

(require 'packages)

(packages/declare 'vterm)
(use-package vterm
  :ensure nil
  :commands (vterm vterm-other-window)
  :custom
  (vterm-shell (or (getenv "SHELL")
                   (executable-find "fish")
                   "/bin/sh"))
  (vterm-max-scrollback 10000)
  :bind (("C-c t" . vterm-other-window)))

;;; terminal.el ends here
