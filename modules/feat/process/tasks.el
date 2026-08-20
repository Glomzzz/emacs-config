;;; tasks.el --- Asynchronous task dashboard integration -*- lexical-binding: t; -*-

(let ((package-directory (expand-file-name "pkgs" user-emacs-directory)))
  (add-to-list 'load-path package-directory))

;; Keep the dashboard parser out of startup.  The first task command loads the
;; local package through these explicit autoloads.
(autoload 'task-dashboard "task-dashboard" nil t)
(autoload 'task-dashboard-run-shell-command "task-dashboard" nil t)

;; Keep task controls in an unused `C-c' namespace.  `C-c d' is already used
;; by the editing configuration, so it intentionally remains untouched.
(global-set-key (kbd "C-c T") #'task-dashboard)
(global-set-key (kbd "C-c C-T") #'task-dashboard-run-shell-command)

;;; tasks.el ends here
