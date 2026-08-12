;;; version-control.el --- Git workflows with Magit -*- lexical-binding: t; -*-

(use-package magit
  :commands (magit-dispatch magit-file-dispatch magit-status)
  :bind
  (("C-x g" . magit-status)
   ("C-x M-g" . magit-dispatch)
   ("C-c M-g" . magit-file-dispatch)))

;;; version-control.el ends here
