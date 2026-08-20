;;; persistence.el --- Persistent editor state -*- lexical-binding: t; -*-

(use-package recentf
  :ensure nil
  :custom
  (recentf-save-file (cache/file "recentf"))
  (recentf-max-saved-items 200)
  :init
  (recentf-mode 1))

(use-package saveplace
  :ensure nil
  :custom
  (save-place-file (cache/file "places"))
  :init
  (save-place-mode 1))

(use-package winner
  :ensure nil
  :init
  (winner-mode 1))

(use-package repeat
  :ensure nil
  :init
  (repeat-mode 1))

;;; persistence.el ends here
