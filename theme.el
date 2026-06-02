;;; -*- lexical-binding: t -*-
(custom-set-variables
 ;; custom-set-variables was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 '(custom-enabled-themes '(gruber-darker))
 '(custom-safe-themes
   '("e13beeb34b932f309fb2c360a04a460821ca99fe58f69e65557d6c1b10ba18c7"
     default))
 '(display-line-numbers-type 'relative)
 '(package-selected-packages
   '(corfu eldoc-box envrc flycheck-eglot flycheck-pycheckers
           flycheck-rust flylisp flymake flymake-clippy
           flymake-diagnostic-at-point flymake-flycheck
           gruber-darker-theme kotlin-ts-mode leetcode markdown-mode
           nix-ts-mode racket-mode treesit-auto typst-ts-mode vterm)))
(custom-set-faces
 ;; custom-set-faces was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 '(corfu-annotations ((t (:foreground "#95a99f"))))
 '(corfu-bar ((t (:background "#ffdd33"))))
 '(corfu-border ((t (:background "#52494e"))))
 '(corfu-current ((t (:background "#453d41" :foreground "#f4f4ff" :weight bold))))
 '(corfu-default ((t (:background "#181818" :foreground "#e4e4ef"))))
 '(corfu-deprecated ((t (:foreground "#cc8c3c" :strike-through t)))))

;; Corfu style for gruber-darker
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

