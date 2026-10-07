;;; completion.el --- Popup completion -*- lexical-binding: t; -*-

;; Corfu presents the normal `completion-at-point' sources in a popup.  It is
;; intentionally enabled globally so Eglot, snippets, and Cape share one UI.
(packages/declare 'corfu)
(use-package corfu
  :ensure nil
  :custom
  (corfu-auto t)
  (corfu-auto-delay 0.15)
  (corfu-auto-prefix 1)
  (corfu-cycle t)
  (corfu-preselect 'prompt)
  (corfu-quit-no-match 'separator)
  :config
  (global-corfu-mode 1)
  (require 'corfu-popupinfo)
  (corfu-popupinfo-mode 1))

;; Show the selected completion's documentation beside the completion popup.
(use-package corfu-popupinfo
  :ensure nil
  :after corfu
  :custom
  (corfu-popupinfo-delay '(0.2 . 0.1)))

;; Cape

(packages/declare 'cape)
(defun completion/setup-capf ()
  "Add useful Cape sources only to buffers where they are relevant."
  (when (fboundp 'cape-dabbrev)
    (add-hook 'completion-at-point-functions #'cape-dabbrev 80 t))
  (when (fboundp 'cape-file)
    (add-hook 'completion-at-point-functions #'cape-file 90 t)))

(packages/declare 'emacs)
(use-package eldoc
  :ensure nil
  :custom
  (eldoc-idle-delay 0.3))

(packages/declare 'eldoc-box)

(defun completion/eldoc-popup-maybe ()
  "Use public Eldoc/Box modes for automatic documentation."
  (eldoc-mode 1)
  (when (and (display-graphic-p)
             (require 'eldoc-box nil t)
             (not (bound-and-true-p eldoc-box-hover-at-point-mode)))
    (eldoc-box-hover-at-point-mode 1)))

(defun completion/eldoc-show-at-point ()
  "Show documentation with Eldoc Box, or normal Eldoc in terminals."
  (interactive)
  (if (and (display-graphic-p) (require 'eldoc-box nil t))
      (call-interactively #'eldoc-box-help-at-point)
    (eldoc-print-current-symbol-info t)))

(use-package eldoc-box
  :ensure nil
  :custom
  ;; Show both short signatures and longer documentation in the popup.
  (eldoc-box-only-multi-line nil)
  (eldoc-box-clear-with-C-g t)
  (eldoc-box-hover-display-frame-above-point nil))

(defun completion/eldoc-popup-after-frame (frame)
  "Enable documentation popups in programming buffers after FRAME appears."
  (when (display-graphic-p frame)
    (with-selected-frame frame
      (dolist (buffer (buffer-list))
        (with-current-buffer buffer
          (when (derived-mode-p 'prog-mode)
            (completion/eldoc-popup-maybe)))))))

(add-hook 'prog-mode-hook #'completion/eldoc-popup-maybe)
(add-hook 'eglot-managed-mode-hook #'completion/eldoc-popup-maybe)
(add-hook 'after-make-frame-functions #'completion/eldoc-popup-after-frame)

(with-eval-after-load 'prog-mode
  (keymap-set prog-mode-map "C-M-d" #'completion/eldoc-show-at-point))

(defun completion/setup-text-capf ()
  "Add dictionary completion to ordinary text buffers."
  (completion/setup-capf)
  (when (fboundp 'cape-dict)
    (add-hook 'completion-at-point-functions #'cape-dict 100 t)))

(use-package cape
  :ensure nil
  :config
  (add-hook 'prog-mode-hook #'completion/setup-capf)
  (add-hook 'conf-mode-hook #'completion/setup-capf)
  (add-hook 'text-mode-hook #'completion/setup-text-capf))

;;; completion.el ends here
