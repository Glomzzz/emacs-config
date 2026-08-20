;;; keys.el --- Keybindings  -*- lexical-binding: t; -*-


(global-set-key (kbd "C-,") #'funcs/duplicate-line)
(global-set-key (kbd "C-S-z") #'funcs/mark-whole-line)
(global-set-key (kbd "C-o") #'funcs/open-line-below)
(global-set-key (kbd "C-S-o") #'funcs/open-line-above)

(global-set-key (kbd "C-c d") 'kill-whole-line)
(global-set-key (kbd "C-c f") #'funcs/format-buffer)
(global-set-key (kbd "C-S-v") 'yank)
(global-set-key (kbd "C-S-c") 'kill-ring-save)
(global-set-key (kbd "C-c i m") 'imenu)
(global-set-key (kbd "C-z") 'set-mark-command)
(global-set-key (kbd "C-M-z") 'rectangle-mark-mode)
(global-set-key (kbd "C-x C-b") #'ibuffer)

(global-set-key (kbd "C-S-<left>")  'windmove-left)
(global-set-key (kbd "C-S-<down>")  'windmove-down)
(global-set-key (kbd "C-S-<up>")    'windmove-up)
(global-set-key (kbd "C-S-<right>") 'windmove-right)

(with-eval-after-load 'compile
  (define-key compilation-mode-map (kbd "r") #'compile)
  (define-key compilation-mode-map (kbd "C-c C-c") #'delete-process))
