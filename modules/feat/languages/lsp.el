;;; lsp.el  -*- lexical-binding: t; -*-

(declare-function eglot-format "eglot" (&optional beg end))
(declare-function eglot-execute "eglot" (server action))
(declare-function eglot--major-modes "eglot" (server))
(defvar format/apheleia-owns)
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

;;; completion commands
(defun lsp/completion-command-execute (original proxy status)
  "Call ORIGINAL completion exit, then run the item's server command.
Servers such as HLS attach an `extend import' command to completions of
unimported names; Eglot does not execute `CompletionItem.command' by
itself."
  (let ((item (and (stringp proxy)
                   (get-text-property 0 'eglot--lsp-item proxy)))
        (server (and (fboundp 'eglot-current-server)
                     (eglot-current-server))))
    (funcall original proxy status)
    (when (and server item (memq status '(finished exact)))
      (when-let* ((command (plist-get item :command)))
        (eglot-execute server command)))))

(defun lsp/completion-command-filter (capf)
  "Wrap CAPF's exit function so `CompletionItem.command' is executed."
  (when (and (consp capf)
             (functionp (plist-get (cdddr capf) :exit-function)))
    (let* ((plist (cdddr capf))
           (exit (plist-get plist :exit-function)))
      (setcdr (cddr capf)
              (plist-put plist :exit-function
                         (lambda (proxy status)
                           (lsp/completion-command-execute exit proxy status))))))
  capf)

;;; eglot
(defun lsp/format-on-save ()
  "Enable Eglot formatting only in buffers managed by Eglot.
Buffers with `format/apheleia-owns' set keep Apheleia enabled instead,
because a synchronous Eglot formatting request can block saving."
  (if (and (not format/apheleia-owns)
           (fboundp 'eglot-managed-p)
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
  (remove-hook 'before-save-hook #'eglot-format)
  :config
  ;; Run server-provided completion commands (for example HLS's
  ;; `extend import') after a completion is accepted.
  (unless (advice-member-p #'lsp/completion-command-filter
                           'eglot-completion-at-point)
    (advice-add 'eglot-completion-at-point :filter-return
                #'lsp/completion-command-filter)))

;;; lsp.el ends here
