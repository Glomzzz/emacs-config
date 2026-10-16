;;; ui.el --- UI package setup -*- lexical-binding: t; -*-

;;; colorful-mode (show color in code)
;;; better rainbow-mode
;;; it can work with hl-mode
(packages/declare 'colorful-mode)

(defun ui/colorful-maybe ()
  "Preview colors in local, reasonably-sized source buffers."
  (when (and (fboundp 'colorful-mode)
             (not (file-remote-p default-directory))
             (or (null buffers/color-preview-size-limit)
                 (buffers/small-p buffers/color-preview-size-limit)))
    (colorful-mode 1)))

(use-package colorful-mode
  :ensure nil
  :config
  (add-hook 'prog-mode-hook #'ui/colorful-maybe)
  (add-hook 'text-mode-hook #'ui/colorful-maybe)
  (add-hook 'conf-mode-hook #'ui/colorful-maybe))

;;; Delimiter nesting colors complement Show Paren and Fingertip.
(packages/declare 'rainbow-delimiters)

(defun ui/rainbow-delimiters-maybe ()
  "Color delimiter nesting in local, reasonably-sized source buffers."
  (when (and (not (minibufferp))
             (not (file-remote-p default-directory))
             (not (derived-mode-p 'special-mode))
             (buffers/small-p))
    (rainbow-delimiters-mode 1)))

(use-package rainbow-delimiters
  :ensure nil
  :commands (rainbow-delimiters-mode)
  :hook ((prog-mode conf-mode yaml-mode yaml-ts-mode)
         . ui/rainbow-delimiters-maybe)
  :custom
  (rainbow-delimiters-max-face-count 5))

;;; auto-dim-other-buffers
(packages/declare 'auto-dim-other-buffers)
(use-package auto-dim-other-buffers
  :ensure nil
  :config
  (auto-dim-other-buffers-mode 1))

;;; zoom
(packages/declare 'zoom)
(use-package zoom
  :ensure nil
  :custom
  (zoom-size '(0.618 . 0.618))
  :config
  (zoom-mode 1))

;;; transient
(packages/declare 'transient)
(use-package transient
  :ensure nil
  :custom
  (transient-history-file (cache/file "transient/history.el"))
  (transient-levels-file (cache/file "transient/levels.el"))
  (transient-values-file (cache/file "transient/values.el")))

;;; whichkey
(packages/declare 'which-key)
(use-package which-key
  :ensure nil
  :init (which-key-mode)
  :diminish which-key-mode
  :custom
  (which-key-idle-delay 0.5)
  :config
  (which-key-setup-side-window-right-bottom)
  )



;;; ui.el ends here
