;;; lsp.el  -*- lexical-binding: t; -*-

(require 'seq)

(declare-function eglot-format "eglot" (&optional beg end))
(declare-function eglot-execute "eglot" (server action))
(declare-function eglot-current-server "eglot" ())
(declare-function eglot--major-modes "eglot" (server))
(declare-function format/eglot-owns-p "format" (&optional region))
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
(defun lsp/completion-resolve-command (original server method &rest arguments)
  "Call ORIGINAL request and retain a resolved completion command.
Eglot caches resolved items separately from the candidate's original
item.  Copy just the command back to that item, so accepting a cached
completion does not need a second resolve request."
  (let ((result (apply original server method arguments)))
    (when (and (eq method :completionItem/resolve)
               (consp (car arguments))
               (plist-member result :command))
      (let* ((item (car arguments))
             (command (copy-tree (plist-get result :command)))
             (entry (plist-member item :command)))
        ;; `plist-put' may return a new head when the key is absent; retain
        ;; the original cons cells referenced by Eglot's candidates/cache.
        (if entry
            (setcar (cdr entry) command)
          (nconc item (list :command command)))))
    result))

(defun lsp/completion-command-execute
    (original proxy status buffer server table)
  "Call ORIGINAL exit in BUFFER, then execute the completion command.
SERVER and TABLE belong to the originating completion session.  Look
up property-less candidates from the *Completions* buffer in TABLE.
Only execute a command after Eglot has successfully applied its edits."
  (when (buffer-live-p buffer)
    (with-current-buffer buffer
      (let ((item
             (and (stringp proxy)
                  (memq status '(finished exact))
                  (or (get-text-property 0 'eglot--lsp-item proxy)
                      (when-let* ((candidate
                                   (seq-find
                                    (lambda (candidate)
                                      (string= proxy candidate))
                                    (all-completions "" table))))
                        (get-text-property 0 'eglot--lsp-item candidate))))))
        (funcall original proxy status)
        (when (and server item (memq status '(finished exact)))
          (when-let* ((command (plist-get item :command)))
            ;; `eglot-execute' may destructively remove the command's title.
            (eglot-execute server (copy-tree command))))))))

(defun lsp/completion-command-filter (capf)
  "Wrap CAPF's exit function so `CompletionItem.command' is executed."
  (if (and (consp capf)
           (functionp (plist-get (cdddr capf) :exit-function)))
      (let* ((buffer (current-buffer))
             (server (eglot-current-server))
             (table (nth 2 capf))
             (plist (copy-sequence (cdddr capf)))
             (exit (plist-get plist :exit-function)))
        (append (seq-take capf 3)
                (plist-put plist :exit-function
                           (lambda (proxy status)
                             (lsp/completion-command-execute
                              exit proxy status buffer server table)))))
    capf))

;;; eglot
(defun lsp/format-on-save ()
  "Enable save formatting with the language's supported formatter.
Use Apheleia when preferred by the language or when Eglot does not
advertise whole-buffer formatting."
  (if (format/eglot-owns-p)
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
                #'lsp/completion-command-filter))
  (unless (advice-member-p #'lsp/completion-resolve-command 'eglot--request)
    (advice-add 'eglot--request :around #'lsp/completion-resolve-command)))

;;; lsp.el ends here
