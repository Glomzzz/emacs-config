;;; completion.el --- Built-in completion preview -*- lexical-binding: t; -*-
(packages/declare 'completion-preview)
(defun completion/preview-maybe ()
  "Enable completion previews in local programming and text buffers."
  (when (and (fboundp 'completion-preview-mode)
             (not (file-remote-p default-directory))
             (< (buffer-size) (* 2 1024 1024)))
    (completion-preview-mode 1)))

(use-package completion-preview
  :ensure nil
  :custom
  (completion-preview-idle-delay 0.2)
  (completion-preview-minimum-symbol-length 2)
  :config
  (add-hook 'prog-mode-hook #'completion/preview-maybe)
  (add-hook 'text-mode-hook #'completion/preview-maybe)
  (add-hook 'conf-mode-hook #'completion/preview-maybe))

;; Cape
(packages/declare 'cape)
(defun completion/setup-capf ()
  "Add useful Cape sources only to buffers where they are relevant."
  (when (fboundp 'cape-dabbrev)
    (add-hook 'completion-at-point-functions #'cape-dabbrev 80 t))
  (when (fboundp 'cape-file)
    (add-hook 'completion-at-point-functions #'cape-file 90 t)))

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
