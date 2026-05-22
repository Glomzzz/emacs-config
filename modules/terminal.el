;;; terminal.el --- Terminal buffer integration and vterm support -*- lexical-binding: t; -*-

(use-package vterm
  :commands vterm
  :bind
  (:map vterm-mode-map
        ("M-w" . kill-ring-save))
  :config
  ;; Keep Meta-w in Emacs so region copying works inside vterm buffers.
  (add-to-list 'vterm-keymap-exceptions "M-w")
  (when-let ((nu-shell (executable-find "nu")))
    (setq vterm-shell nu-shell)))
