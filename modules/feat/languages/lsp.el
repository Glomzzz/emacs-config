;;; lsp.el  -*- lexical-binding: t; -*-

(declare-function eglot-format "eglot" (&optional beg end))
(declare-function eglot--major-modes "eglot" (server))
(defvar eglot-workspace-configuration)

;;; workspace configuration
(defvar lsp/workspace-configurations nil
  "Alist of major modes to Eglot workspace configuration functions.
Each function is called with the Eglot server and returns a plist that
Eglot sends as workspace settings for that server.")

(defun lsp/register-workspace-configuration (modes function)
  "Register FUNCTION as the workspace configuration for MODES."
  (dolist (mode (if (listp modes) modes (list modes)))
    (setf (alist-get mode lsp/workspace-configurations) function)))

(defun lsp/workspace-configuration (server)
  "Return the workspace configuration registered for SERVER's mode.
Eglot evaluates `eglot-workspace-configuration' in a temporary buffer,
so a buffer-local value would be ignored.  Language modules register
their configuration functions here instead."
  (when-let* ((mode (car (eglot--major-modes server)))
              (function (cdr (assq mode lsp/workspace-configurations))))
    (funcall function server)))

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
  ;; Eglot evaluates workspace configuration in a temporary buffer, so the
  ;; shared dispatcher must be the global value; languages register above.
  (setq-default eglot-workspace-configuration #'lsp/workspace-configuration)
  ;; Disable inlay hints until they are explicitly requested.
  (setq eglot-ignored-server-capabilities '(:inlayHintProvider))
  ;; Older versions of this configuration added a global hook.  Remove it for
  ;; an already-running session before installing the buffer-local hook above.
  (remove-hook 'prog-mode-hook #'eglot-ensure)
  (remove-hook 'before-save-hook #'eglot-format))

;;; lsp.el ends here
