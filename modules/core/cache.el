;;; cache.el --- Shared cache path helpers -*- lexical-binding: t; -*-


(defconst cache/root
  (file-name-as-directory
   (expand-file-name
    "emacs"
    (or (getenv "XDG_CACHE_HOME") "~/.cache"))))

(defun cache/folder (path)
  (let ((directory
         (file-name-as-directory
          (expand-file-name path cache/root))))
    (make-directory directory t)
    directory))

(defun cache/file (path)
  (let ((file (expand-file-name path cache/root)))
    (make-directory (file-name-directory file) t)
    file))

(defun cache/tree-sitter ()
  "Return the cache directory for Tree-sitter grammar libraries."
  (cache/folder "tree-sitter"))

(defun cache/eln ()
  "Return the cache directory for native-compilation artifacts."
  (cache/folder "eln"))

(defun cache/configure-state-paths ()
  "Point Emacs' persistent state variables below `cache/root'.
Called by `early-init.el' and `init.el', so `-Q' bootstrap runs, which skip
early-init, get the same paths.  Safe to call more than once."
  (setq custom-file (cache/file "custom.el")
        package-user-dir (cache/folder "elpa")
        package-quickstart-file (cache/file "package-quickstart.el")
        savehist-file (cache/file "history")
        bookmark-default-file (cache/file "bookmarks")
        project-list-file (cache/file "projects.eld")
        tramp-persistency-file-name (cache/file "tramp")
        tramp-auto-save-directory (cache/folder "tramp-auto-save")
        transient-history-file (cache/file "transient/history.el")
        transient-levels-file (cache/file "transient/levels.el")
        transient-values-file (cache/file "transient/values.el")
        auto-save-list-file-prefix (cache/file "auto-save-list/.saves-")
        backup-directory-alist `(("." . ,(cache/folder "backups")))
        ;; The non-nil third element keeps each source file's auto-save distinct.
        auto-save-file-name-transforms
        `((".*" ,(cache/folder "auto-save-files") t))))

(provide 'cache)

;;; cache.el ends here
