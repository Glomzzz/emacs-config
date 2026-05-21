;;; ui.el --- Frame and buffer display defaults for general editing -*- lexical-binding: t; -*-

(defun my/prog-ui-setup ()
  "Enable lighter UI features in editing buffers only."
  (display-line-numbers-mode 1))

(defun my/disable-line-numbers ()
  "Disable line numbers in buffers where they are mostly noise."
  (display-line-numbers-mode 0))

(when (fboundp 'menu-bar-mode)
  (menu-bar-mode -1))
(when (fboundp 'tool-bar-mode)
  (tool-bar-mode -1))
(when (fboundp 'scroll-bar-mode)
  (scroll-bar-mode -1))

(dolist (hook '(prog-mode-hook text-mode-hook conf-mode-hook))
  (add-hook hook #'my/prog-ui-setup))

(dolist (hook '(term-mode-hook shell-mode-hook eshell-mode-hook vterm-mode-hook))
  (add-hook hook #'my/disable-line-numbers))

(set-face-attribute 'default nil :font "JetBrainsMono Nerd Font-18")
