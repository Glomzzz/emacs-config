;;; appearance.el --- Theme loading and appearance-specific face behavior -*- lexical-binding: t; -*-

(use-package gruber-darker-theme
  :defer t)

(when (file-exists-p custom-file)
  (load custom-file nil 'nomessage))

;; Corfu popup styling tuned for the gruber-darker background.
;; Hand-written faces live here rather than in the custom-file so that
;; Customize rewrites of theme.el never duplicate or lose them.
(with-eval-after-load 'corfu
  (custom-set-faces
   ;; popup background
   '(corfu-default
     ((t (:background "#181818" :foreground "#e4e4ef"))))

   ;; selected candidate
   '(corfu-current
     ((t (:background "#453d41" :foreground "#f4f4ff" :weight bold))))

   ;; popup border
   '(corfu-border
     ((t (:background "#52494e"))))

   ;; annotation text on the right
   '(corfu-annotations
     ((t (:foreground "#95a99f"))))

   ;; scrollbar / side bar
   '(corfu-bar
     ((t (:background "#ffdd33"))))

   ;; deprecated candidates
   '(corfu-deprecated
     ((t (:foreground "#cc8c3c" :strike-through t))))))

;;; appearance.el ends here
