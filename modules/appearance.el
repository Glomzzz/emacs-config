;;; appearance.el --- Theme loading and appearance-specific face behavior -*- lexical-binding: t; -*-

(use-package gruber-darker-theme
  :defer t)

(when (file-exists-p custom-file)
  (load custom-file nil 'nomessage))
