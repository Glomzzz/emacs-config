;;; gc.el --- Idle-aware garbage collection thresholds -*- lexical-binding: t; -*-

(require 'packages)

;; gcmh keeps collections rare while a command runs and collects while Emacs is
;; idle.  Its default high threshold is 1 GiB, which lets the heap grow
;; unbounded during long editing sessions, so cap it.  The low threshold matches
;; the runtime limit `init.el' restores after startup.
(packages/declare 'gcmh)
(use-package gcmh
  :ensure nil
  :demand t
  :custom
  (gcmh-low-cons-threshold (* 16 1024 1024))
  (gcmh-high-cons-threshold (* 128 1024 1024))
  :config
  (gcmh-mode 1))

;;; gc.el ends here
