;;; multi-cursor.el --- Multiple-cursor editing -*- lexical-binding: t; -*-

(require 'packages)

(packages/declare 'multiple-cursors)
(use-package multiple-cursors
  :init
  (setq mc/list-file (cache/file "multiple-cursors.el"))
  (unless (file-exists-p (file-name-directory mc/list-file))
    (make-directory (file-name-directory mc/list-file) t))
  :bind (("C-c C-S-c" . mc/edit-lines)
         ("C->"         . mc/mark-next-like-this)
         ("C-<"         . mc/mark-previous-like-this)
         ("C-c C-<"     . mc/mark-all-like-this)
         ("C-\""        . mc/skip-to-next-like-this)
         ("C-:"         . mc/skip-to-previous-like-this)))


;;; multi-cursor.el ends here
