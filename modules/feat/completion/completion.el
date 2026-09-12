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

(defun completion/eldoc-in-comment-p ()
  "Return non-nil when point is inside a syntax comment."
  (nth 4 (syntax-ppss)))

(defun completion/eldoc-update-maybe (original)
  "Refresh Eldoc with ORIGINAL unless point is inside a comment."
  (if (completion/eldoc-in-comment-p)
      (eldoc--message nil)
    (funcall original)))

(with-eval-after-load 'eldoc
  (advice-add #'eldoc--update :around #'completion/eldoc-update-maybe))

(packages/declare 'eldoc-box)
(defun completion/eldoc-popup-maybe ()
  "Prepare documentation popups in programming buffers."
  (when (and (display-graphic-p)
             (require 'eldoc-box nil t))
    ;; Keep the renderer positioned at point, but do not enable Eldoc here:
    ;; documentation is requested explicitly with `C-M-d'.
    (when (bound-and-true-p eldoc-box-hover-at-point-mode)
      (eldoc-box-hover-at-point-mode -1))
    (setq-local eldoc-box-position-function
                eldoc-box-at-point-position-function)
    (eldoc-box-hover-mode 1)
    ;; Route manual documentation only to Eldoc Box.  In particular, do not
    ;; retain `eldoc-display-in-buffer', which creates or updates `*eldoc*'.
    (setq-local eldoc-display-functions
                (list #'eldoc-box--eldoc-display-function))))

(defun completion/eldoc-manual-mode ()
  "Disable automatic Eldoc requests in the current buffer."
  (when (bound-and-true-p eldoc-mode)
    (eldoc-mode -1)))

(defun completion/eldoc-ignore-code-actions ()
  "Remove Eglot code-action suggestions from documentation sources."
  (when (boundp 'eldoc-documentation-functions)
    (setq-local eldoc-documentation-functions
                (remove #'eglot-code-action-suggestion
                        eldoc-documentation-functions))))

(defun completion/eldoc-show-at-point ()
  "Show documentation for the symbol at point on demand."
  (interactive)
  (if (completion/eldoc-in-comment-p)
      (progn
        (when (fboundp 'eldoc-box-quit-frame)
          (eldoc-box-quit-frame))
        (message "No documentation in comments"))
    (require 'eldoc)
    (when (fboundp 'eldoc-box-quit-frame)
      (eldoc-box-quit-frame))
    ;; The request may be asynchronous for language servers; Eldoc Box is
    ;; already installed as the display function and will show the response.
    (eldoc-print-current-symbol-info t)))

(use-package eldoc-box
  :ensure nil
  :custom
  ;; Show both short signatures and longer documentation in the popup.
  (eldoc-box-only-multi-line nil)
  (eldoc-box-clear-with-C-g t)
  (eldoc-box-hover-display-frame-above-point nil)
  ;; Movement commands should let Eldoc's 0.3s timer refresh the popup instead
  ;; of being treated like unrelated commands that hide an existing popup.
  (eldoc-box-self-insert-command-list
   '(self-insert-command
     forward-char backward-char right-char left-char
     next-line previous-line forward-line
     beginning-of-line end-of-line beginning-of-buffer end-of-buffer
     scroll-up-command scroll-down-command
     mouse-set-point)))

(defun completion/eldoc-popup-after-frame (frame)
  "Enable documentation popups in programming buffers after FRAME appears."
  (when (display-graphic-p frame)
    (with-selected-frame frame
      (dolist (buffer (buffer-list))
        (with-current-buffer buffer
          (when (derived-mode-p 'prog-mode)
            (completion/eldoc-popup-maybe)))))))

(add-hook 'prog-mode-hook #'completion/eldoc-popup-maybe)
(add-hook 'prog-mode-hook #'completion/eldoc-manual-mode)
(add-hook 'eglot-managed-mode-hook #'completion/eldoc-manual-mode)
(add-hook 'eglot-managed-mode-hook #'completion/eldoc-ignore-code-actions t)
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
