;;; completion.el --- Completion UI built around Corfu and popup info -*- lexical-binding: t; -*-

(use-package corfu
  :hook (after-init . global-corfu-mode)
  :custom
  (corfu-auto t)
  (corfu-auto-delay 0.1)
  (corfu-auto-prefix 2)
  :init
  (with-eval-after-load 'corfu
    (require 'corfu-popupinfo nil t))
  :bind
  (:map corfu-map
        ("M-d" . corfu-popupinfo-toggle)
        ("M-l" . corfu-popupinfo-location)
        ("M-p" . corfu-popupinfo-scroll-down)
        ("M-n" . corfu-popupinfo-scroll-up)))

(with-eval-after-load 'corfu-popupinfo
  (setq corfu-popupinfo-delay '(0.4 . 0.2)
        corfu-popupinfo-max-width 80
        corfu-popupinfo-max-height 20)
  (corfu-popupinfo-mode 1))
