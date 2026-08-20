;;; init.el --- Minimal configuration for the `emc' launcher -*- lexical-binding: t; -*-

(unless (featurep 'cache)
  (load (expand-file-name "modules/core/cache.el" user-emacs-directory)
        nil 'nomessage))

;; `early-init.el' is skipped by `-Q' bootstrap runs.  Keep the same startup
;; budget there so package installation and clean batch checks do not trigger
;; a garbage collection for every small module.
(defvar emacs--startup-file-name-handler-alist file-name-handler-alist)
(setq gc-cons-threshold (* 64 1024 1024)
      gc-cons-percentage 0.6
      file-name-handler-alist nil
      inhibit-redisplay t)

(defun emacs/restore-startup-performance ()
  "Restore normal runtime limits after configuration startup."
  (setq gc-cons-threshold (* 16 1024 1024)
        gc-cons-percentage 0.1
        inhibit-redisplay nil
        ;; Preserve handlers installed while loading packages and any handlers
        ;; Emacs had before startup began.
        file-name-handler-alist
        (delete-dups
         (append file-name-handler-alist
                 emacs--startup-file-name-handler-alist))))

;; `early-init.el' is skipped by the `-Q' package bootstrap invocation.
(when (fboundp 'startup-redirect-eln-cache)
  (startup-redirect-eln-cache (cache/eln)))

(setq custom-file
      (cache/file "custom.el"))

;; The systemd package bootstrap runs with `-Q' and skips `early-init.el', so
;; define these paths here as a fallback as well as during normal early startup.
(setq savehist-file (cache/file "history")
      tramp-persistency-file-name (cache/file "tramp")
      ;; `early-init.el' is skipped by the `-Q' bootstrap invocation.
      transient-history-file (cache/file "transient/history.el")
      transient-levels-file (cache/file "transient/levels.el")
      transient-values-file (cache/file "transient/values.el")
      project-list-file (cache/file "projects.eld"))

(defun mod/import (paths)
  "Load PATHS relative to the file containing the call.
PATHS may be one relative path or a list of relative paths.  A path
ending in `/` loads the `mod.el` file in that directory."
  (let* ((caller-file (or load-file-name
                          (bound-and-true-p byte-compile-current-file)
                          buffer-file-name))
         (caller-directory
          (and caller-file
               (file-name-directory (expand-file-name caller-file)))))
    (unless caller-directory
      (error "Cannot resolve module imports outside a file-backed context"))
    (dolist (path (if (listp paths) paths (list paths)))
      (unless (stringp path)
        (signal 'wrong-type-argument (list 'stringp path)))
      (when (file-name-absolute-p path)
        (error "Module import path must be relative: %s" path))
      (when (string-suffix-p "/" path)
        (setq path (concat path "mod.el")))
      (load (expand-file-name path caller-directory) nil 'nomessage))))


(condition-case error
    (progn
      (mod/import '("modules/"))
      (when (and (boundp 'packages/bootstrap-mode)
                 packages/bootstrap-mode)
        (packages/save-selection)))
  (error
   (emacs/restore-startup-performance)
   (when (daemonp)
     (message "Emacs daemon refusing to start: modules failed to load: %s"
              (error-message-string error))
     (backtrace)
     (kill-emacs 1))
   (signal (car error) (cdr error))))

(emacs/restore-startup-performance)

(provide 'init)

;;; init.el ends here
