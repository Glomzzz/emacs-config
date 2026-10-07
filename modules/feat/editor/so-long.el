;;; so-long.el  -*- lexical-binding: t; -*-
;; Large-file optimization
(packages/declare 'so-long)
(use-package so-long
  :ensure nil
  :custom
  (so-long-threshold 10000)

  :init
  (global-so-long-mode 1)

  :config
  ;; Don't waste time maintaining these in huge buffers
  (add-to-list 'so-long-variable-overrides
               '(font-lock-maximum-decoration . 1))
  (add-to-list 'so-long-variable-overrides
               '(save-place-alist . nil))

  ;; This is a disable list: removing modes would keep them running.
  ;; Corfu's timer hooks must also stop when So Long handles minified files.
  (dolist (mode '(font-lock-mode display-line-numbers-mode corfu-mode))
    (add-to-list 'so-long-minor-modes mode))

  ;; Don't make huge buffers read-only
  (setf (alist-get 'buffer-read-only
                   so-long-variable-overrides
                   nil nil)
        nil))
;;; so-long.el ends here
