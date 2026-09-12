;;; lsp.el  -*- lexical-binding: t; -*-

(declare-function eglot-format "eglot" (&optional beg end))

;;; eglot
(defun lsp/format-on-save ()
  "Enable Eglot formatting only in buffers managed by Eglot."
  (if (and (fboundp 'eglot-managed-p)
           (eglot-managed-p))
      (progn
        (add-hook 'before-save-hook #'eglot-format nil t)
        (when (bound-and-true-p apheleia-mode)
          (apheleia-mode -1)))
    (remove-hook 'before-save-hook #'eglot-format t)
    (when (fboundp 'format/mode-maybe)
      (format/mode-maybe))))

(use-package eglot
  :ensure nil
  :hook (eglot-managed-mode . lsp/format-on-save)
  :init
  ;; Show hover/signature documentation after the cursor has rested briefly.
  ;; Eglot feeds server documentation through Eldoc's normal display.
  (setq eldoc-idle-delay 0.3
        eldoc-echo-area-use-multiline-p t
        eglot-autoshutdown t)
  ;; Disable inlay hints until they are explicitly requested.
  (setq eglot-ignored-server-capabilities '(:inlayHintProvider))
  ;; Older versions of this configuration added a global hook.  Remove it for
  ;; an already-running session before installing the buffer-local hook above.
  (remove-hook 'prog-mode-hook #'eglot-ensure)
  (remove-hook 'before-save-hook #'eglot-format))

;;; lsp.el ends here
