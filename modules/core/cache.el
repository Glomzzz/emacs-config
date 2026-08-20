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

(provide 'cache)

;;; cache.el ends here
