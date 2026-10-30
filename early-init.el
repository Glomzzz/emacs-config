;;; early-init.el --- Early package setup -*- lexical-binding: t; -*-

(setq package-enable-at-startup nil)

;; Give startup enough allocation room to avoid repeated garbage collections.
;; These values are restored by `init.el' once the modules have loaded.
(defvar emacs--startup-file-name-handler-alist file-name-handler-alist)
(setq gc-cons-threshold (* 64 1024 1024)
      gc-cons-percentage 0.6
      file-name-handler-alist nil
      inhibit-redisplay t)

(load (expand-file-name "modules/core/cache.el" user-emacs-directory)
      nil 'nomessage)

(cache/configure-state-paths)

(when (fboundp 'startup-redirect-eln-cache)
  (startup-redirect-eln-cache (cache/eln)))

;;; early-init.el ends here
