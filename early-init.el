;;; early-init.el --- Startup optimizations -*- lexical-binding: t; -*-

(require 'warnings)

;; Anonymous buffers have no source file where Emacs can add a dialect cookie.
;; Keep the Emacs 31 warning enabled for every named Lisp file.
(add-to-list 'warning-suppress-log-types
             '(files missing-lexbind-cookie eval-buffer))

(defconst my/emacs-cache-dir
  (expand-file-name ".cache/" user-emacs-directory))

(defconst my/emacs-package-dir
  (expand-file-name "elpa/" my/emacs-cache-dir))

(defconst my/emacs-package-quickstart-file
  (expand-file-name "package-quickstart.el" my/emacs-cache-dir))

(defconst my/emacs-auto-save-dir
  (expand-file-name "auto-save-list/" my/emacs-cache-dir))

(defconst my/emacs-eln-cache-dir
  (expand-file-name "eln-cache/" my/emacs-cache-dir))

(defconst my/emacs-tree-sitter-dir
  (expand-file-name "tree-sitter/" my/emacs-cache-dir))

(defconst my/emacs-url-dir
  (expand-file-name "url/" my/emacs-cache-dir))

(dolist (dir (list my/emacs-cache-dir
                   my/emacs-package-dir
                   my/emacs-auto-save-dir
                   my/emacs-eln-cache-dir
                   my/emacs-tree-sitter-dir
                   my/emacs-url-dir))
  (make-directory dir t))

(setq frame-inhibit-implied-resize t
      load-prefer-newer t
      gc-cons-threshold most-positive-fixnum
      gc-cons-percentage 0.6
      package-user-dir my/emacs-package-dir
      package-quickstart t
      package-quickstart-file my/emacs-package-quickstart-file
      url-history-file (expand-file-name "url/history" my/emacs-cache-dir)
      url-configuration-directory my/emacs-url-dir
      auto-save-list-file-prefix
      (expand-file-name ".saves-" my/emacs-auto-save-dir)
      tramp-persistency-file-name (expand-file-name "tramp" my/emacs-cache-dir)
      transient-history-file (expand-file-name "transient/history.el" my/emacs-cache-dir)
      bookmark-default-file (expand-file-name "bookmarks" my/emacs-cache-dir)
      recentf-save-file (expand-file-name "recentf" my/emacs-cache-dir)
      savehist-file (expand-file-name "history" my/emacs-cache-dir)
      project-list-file (expand-file-name "projects" my/emacs-cache-dir)
      treesit-extra-load-path (list my/emacs-tree-sitter-dir))

(when (fboundp 'startup-redirect-eln-cache)
  (startup-redirect-eln-cache
   my/emacs-eln-cache-dir))

(defvar my/default-file-name-handler-alist file-name-handler-alist)

(setq file-name-handler-alist nil)

(add-hook
 'emacs-startup-hook
 (lambda ()
   (setq gc-cons-threshold (* 64 1024 1024)
         gc-cons-percentage 0.1
         file-name-handler-alist
         (append my/default-file-name-handler-alist
                 file-name-handler-alist))))

;;; early-init.el ends here
