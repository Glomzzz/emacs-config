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

;; Compilation-error menu adapted from the hydra wiki's "Compilation" example.
;; The wiki also binds `C-x `' to the menu.  Here `C-x `' keeps its built-in
;; `next-error', and the menu lives on C-x C-h c.
(use-package compile
  :ensure nil
  :after hydra
  :bind (("C-x C-h c" . hydra-next-error/body))
  :hydra (hydra-next-error
          (:color red)
          "
Compilation errors: _j_ next  _k_ previous  _h_ first  _l_ last  _`_ next  _q_ quit"
          ("`" next-error)
          ("j" next-error)
          ("k" previous-error)
          ("h" first-error)
          ("l" (condition-case nil
                  (while t
                    (next-error))
                (user-error nil)))
          ("q" nil :color blue)))

;;; tasks.el ends here
