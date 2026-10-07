;;; lsp.el  -*- lexical-binding: t; -*-

(require 'seq)

(declare-function eglot-format "eglot" (&optional beg end))
(declare-function eglot-execute "eglot" (server action))
(declare-function eglot-current-server "eglot" ())
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
  "Return workspace settings for SERVER using Eglot's major-mode context.
Eglot calls `eglot-workspace-configuration' in a temporary buffer whose
major mode matches the server's language.  Use that public contract
rather than inspecting private server slots."
  (when-let* ((function (cdr (assq major-mode lsp/workspace-configurations))))
    (funcall function server)))

;;; completion commands
(defgroup lsp-tools nil
  "Language-server integration policies."
  :group 'tools)

(defcustom lsp/completion-command-support t
  "Execute commands attached to accepted Eglot completion items.
This compatibility bridge uses Eglot's candidate item property because
there is no public command-execution hook.  Disable it if a future Eglot
version handles completion commands itself."
  :type 'boolean :group 'lsp-tools
  :set (lambda (symbol value)
         (set-default symbol value)
         (when (fboundp 'lsp/configure-completion-commands)
           (lsp/configure-completion-commands))))

(defun lsp/completion-resolve-command (original server method &rest arguments)
  "Call ORIGINAL request and retain a resolved completion command.
Eglot caches resolved items separately from the candidate's original
item.  Copy just the command back to that item, so accepting a cached
completion does not need a second resolve request."
  (let ((result (apply original server method arguments)))
    (when (and lsp/completion-command-support
               (eq method :completionItem/resolve)
               (fboundp 'eglot-current-server)
               (eq server (eglot-current-server))
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
  (if (and lsp/completion-command-support
           (consp capf)
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

(defun lsp/configure-completion-commands ()
  "Install or remove the optional, narrowly scoped completion bridge."
  (when (featurep 'eglot)
    (advice-remove 'eglot-completion-at-point #'lsp/completion-command-filter)
    (advice-remove 'jsonrpc-request #'lsp/completion-resolve-command)
    (when lsp/completion-command-support
      (advice-add 'eglot-completion-at-point :filter-return
                  #'lsp/completion-command-filter)
      ;; JSONRPC's public request API preserves Eglot's resolution cache.
      ;; The wrapper only handles resolve replies from the current server.
      (advice-add 'jsonrpc-request :around #'lsp/completion-resolve-command))))

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
  ;; Eglot feeds server documentation through Eldoc's normal display.
  ;; The completion module owns the idle delay, including popup timing.
  (setq eldoc-echo-area-use-multiline-p t
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
  (lsp/configure-completion-commands))

;;; lsp.el ends here
