;;; appearance.el --- Theme loading and appearance-specific face behavior -*- lexical-binding: t; -*-

(use-package gruber-darker-theme)

(when (file-exists-p custom-file)
  (load custom-file nil 'nomessage))
