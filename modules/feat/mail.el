;;; mail.el --- Local mail with mu4e and msmtp -*- lexical-binding: t; -*-

(require 'packages)

(defgroup mail-client nil
  "Local Maildir mail through mu4e, mbsync, and msmtp."
  :group 'mail)

(defcustom mail/special-folders nil
  "Verified special-folder mappings for the Infomaniak mailbox.
An alist of sent, drafts, trash, and archive to mu4e paths, such as
\"/infomaniak/Sent\".  Leave unset until after the first mbsync run.
Use `mail/configure-folders' to choose from synchronized Maildirs."
  :type '(alist :key-type (choice (const sent) (const drafts)
                                 (const trash) (const archive))
                :value-type string)
  :group 'mail-client)

(defun mail/folder (kind &optional _message)
  "Return the verified special folder for KIND, or refuse the action.
_MESSAGE is accepted for mu4e's public folder-function interface."
  (let ((folder (alist-get kind mail/special-folders)))
    (unless (and (stringp folder)
                 (string-prefix-p "/infomaniak/" folder)
                 (not (member ".." (split-string folder "/" t)))
                 (let ((directory (expand-file-name
                                   (substring folder 1) "~/Maildir")))
                   (cl-every (lambda (part)
                               (file-directory-p
                                (expand-file-name part directory)))
                             '("cur" "new" "tmp"))))
      (user-error "Verify the %s folder with M-x mail/configure-folders first"
                  kind))
    folder))

(defun mail/configure-folders ()
  "Choose and save all four special folders from synchronized Maildirs.
Check their roles in webmail first; names alone do not identify roles.
No messages are moved and no folders are created by this command."
  (interactive)
  (require 'mu4e)
  (let ((folders (seq-filter
                  (lambda (folder) (string-prefix-p "/infomaniak/" folder))
                  (mu4e-get-maildirs)))
        mappings)
    (unless folders
      (user-error "Sync mail, open mu4e, and update its index first"))
    (dolist (kind '(sent drafts trash archive))
      (push (cons kind (completing-read
                        (format "Verified %s folder: " kind)
                        folders nil t nil nil
                        (alist-get kind mail/special-folders)))
            mappings))
    (when (yes-or-no-p "Save these verified special-folder mappings? ")
      (customize-save-variable 'mail/special-folders (nreverse mappings)))))

;; Supplied by Nix alongside the matching mu binary, NOT from ELPA/MELPA.
;; Do not use packages/declare: bootstrap must not install another mu4e.
(use-package mu4e
  :ensure nil
  :commands (mu4e mu4e-compose-new)
  :bind (("C-c M" . mu4e))
  :init
  (setq user-mail-address "me@glomzzz.com"
        user-full-name "Glom Zhao"
        mail-user-agent 'mu4e-user-agent)
  ;; Built-in compose-mail also needs the lazy mu4e user-agent entry point.
  (autoload 'mu4e-user-agent "mu4e" nil t)
  :config
  (setq mu4e-mu-binary (executable-find "mu")
        ;; Match Home Manager's programs.mu.home even before the next login.
        ;; Current mu4e reads its root Maildir from mu init, not mu4e-maildir.
        mu4e-mu-home (or (getenv "MUHOME")
                         (expand-file-name
                          "mu" (or (getenv "XDG_CACHE_HOME") "~/.cache")))
        ;; systemd retrieves mail independently; mu4e alone owns indexing.
        mu4e-get-mail-command "true"
        mu4e-update-interval 300
        mu4e-change-filenames-when-moving t
        mu4e-sent-folder (apply-partially #'mail/folder 'sent)
        mu4e-drafts-folder (apply-partially #'mail/folder 'drafts)
        mu4e-trash-folder (apply-partially #'mail/folder 'trash)
        mu4e-refile-folder (apply-partially #'mail/folder 'archive)
        mu4e-sent-messages-behavior 'sent
        mu4e-maildir-shortcuts '((:maildir "/infomaniak/INBOX" :key ?i))
        mu4e-attachment-dir (expand-file-name "~/Downloads")
        message-send-mail-function #'message-send-mail-with-sendmail
        send-mail-function #'sendmail-send-it
        sendmail-program (or (executable-find "msmtp") "msmtp")
        message-sendmail-f-is-evil t
        message-sendmail-extra-arguments '("--read-envelope-from")
        message-kill-buffer-on-exit t))

;;; mail.el ends here
