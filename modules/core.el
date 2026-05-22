;;; core.el --- Core editor defaults and shared environment helpers -*- lexical-binding: t; -*-

(setq inhibit-startup-screen t
      inhibit-startup-message t
      initial-scratch-message nil
      ring-bell-function #'ignore
      make-backup-files nil
      create-lockfiles nil
      auto-save-default nil
      tab-width 4
      compilation-scroll-output t
      read-process-output-max (* 1024 1024)
      eldoc-echo-area-use-multiline-p nil)

(let ((my/posix-shell (or (executable-find "bash")
                          (executable-find "sh")))
      (my/nu-shell (executable-find "nu")))
  (when my/posix-shell
    (setq shell-file-name my/posix-shell
          explicit-shell-file-name my/posix-shell))
  (when my/nu-shell
    (setenv "SHELL" my/nu-shell)))

(setq-default indent-tabs-mode nil
              display-line-numbers-type 'relative)

(define-key key-translation-map [right-shift] [ignore])
(global-set-key [right-shift] #'ignore)
(global-set-key (kbd "C-c f") #'find-file-at-point)

(defun my/prepend-to-path (dir)
  "Prepend DIR to PATH and `exec-path' when present."
  (when (file-directory-p dir)
    (unless (member dir exec-path)
      (push dir exec-path))
    (unless (string-match-p (regexp-quote dir) (or (getenv "PATH") ""))
      (setenv "PATH" (concat dir path-separator (getenv "PATH"))))))

(my/prepend-to-path (expand-file-name "~/.cargo/bin"))
(my/prepend-to-path (expand-file-name "~/.local/bin"))

(use-package envrc
  :hook (after-init . envrc-global-mode))
