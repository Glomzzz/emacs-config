;;; completion.el --- Popup completion -*- lexical-binding: t; -*-

(defun completion/sync-theme-faces (&rest _ignored)
  "Use the active theme's palette for Corfu's fallback faces.
Theme-provided Corfu faces and Customize settings take precedence."
  ;; Corfu reads the scrollbar background without resolving inheritance,
  ;; so that color needs copying when a theme is enabled or disabled.
  (dolist (spec `((corfu-default ((t (:inherit default))))
                  (corfu-current ((t (:inherit highlight :extend t))))
                  (corfu-bar ((t (:background ,(face-background 'region nil t)))))
                  (corfu-border ((t (:inherit fringe))))))
    (face-spec-set (car spec) (cadr spec) 'face-defface-spec)))

(defun completion/limit-auto (&optional argument)
  "Limit automatic completion when enabling Corfu with ARGUMENT.
Remote, large, and So Long buffers retain manual completion.  Run before
Corfu installs timer hooks; preserve explicit buffer-local opt-outs."
  (when (and (not (or (and (numberp argument) (<= argument 0))
                     (and (eq argument 'toggle) (bound-and-true-p corfu-mode))))
             (or (file-remote-p default-directory)
                 (not (buffers/small-p))
                 (derived-mode-p 'so-long-mode)
                 (bound-and-true-p so-long-minor-mode)))
    (setq-local corfu-auto nil)))

;; Corfu presents the normal `completion-at-point' sources in a popup.  It is
;; intentionally enabled globally so Eglot, snippets, and Cape share one UI.
(packages/declare 'corfu)
(use-package corfu
  :ensure nil
  :custom
  (corfu-auto t)
  ;; Avoid querying broad one-character candidate sets during short pauses.
  (corfu-auto-delay 0.2)
  (corfu-auto-prefix 2)
  (corfu-cycle t)
  (corfu-preselect 'prompt)
  (corfu-quit-no-match 'separator)
  :config
  ;; `corfu-popupinfo' inherits the same palette through `corfu-default'.
  (completion/sync-theme-faces)
  (add-hook 'enable-theme-functions #'completion/sync-theme-faces)
  (add-hook 'disable-theme-functions #'completion/sync-theme-faces)
  ;; The public mode must see this policy before choosing its timer hooks.
  ;; Checking only on activation avoids extra work on every keystroke.
  (advice-add 'corfu-mode :before #'completion/limit-auto)
  (global-corfu-mode 1)
  (require 'corfu-popupinfo)
  (corfu-popupinfo-mode 1))

;; Show the selected completion's documentation beside the completion popup.
(use-package corfu-popupinfo
  :ensure nil
  :after corfu
  :custom
  ;; Let selection settle before resolving documentation for a candidate.
  (corfu-popupinfo-delay '(0.5 . 0.2)))

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
  ;; eldoc-box's at-point mode suppresses display for 0.5 seconds after
  ;; motion.  A faster Eldoc reply is discarded, and the unchanged point
  ;; prevents a retry.  Request only after that suppression has expired.
  (eldoc-idle-delay 0.6))

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

(defvar-local completion--eldoc-font-remap nil
  "Cookie for the documentation buffer's source-font remapping.")

(defun completion/eldoc-sync-font (origin)
  "Match documentation text to ORIGIN's frame font and buffer text scale.
Run in the doc buffer through Eldoc Box's public setup hook, before popup
geometry is measured.  Keep its own faces, colors, and Markdown styling."
  (when (buffer-live-p origin)
    (require 'face-remap)
    (let* ((window (if (eq (window-buffer (selected-window)) origin)
                       (selected-window)
                     (get-buffer-window origin t)))
           (frame (if window (window-frame window) (selected-frame)))
           (height (face-attribute 'default :height frame))
           (family (face-attribute 'default :family frame))
           (scale (with-current-buffer origin
                    (if (bound-and-true-p text-scale-mode)
                        (expt text-scale-mode-step text-scale-mode-amount)
                      1))))
      (when completion--eldoc-font-remap
        (face-remap-remove-relative completion--eldoc-font-remap))
      (setq completion--eldoc-font-remap
            (face-remap-add-relative 'default
                                     :family family
                                     :height (max 1 (round (* height scale))))))))

(use-package eldoc-box
  :ensure nil
  :hook (eldoc-box-buffer-setup . completion/eldoc-sync-font)
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
  :custom
  ;; Fallback word completion should not scan every same-mode buffer.
  (cape-dabbrev-buffer-function #'current-buffer)
  :config
  (add-hook 'prog-mode-hook #'completion/setup-capf)
  (add-hook 'conf-mode-hook #'completion/setup-capf)
  (add-hook 'text-mode-hook #'completion/setup-text-capf))

;;; completion.el ends here
