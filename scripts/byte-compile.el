;;; byte-compile.el --- Byte-compile configuration modules -*- lexical-binding: t; -*-

;; Run with: emacs --batch -Q -l /path/to/emacs/scripts/byte-compile.el
;; Load the configuration first so `use-package' and `mod/import' expand
;; correctly, then compile the hand-written modules and local packages.
;; `init.el' sets `load-prefer-newer', so an edit made after compiling wins
;; over its older `.elc' without a recompile.
(unless noninteractive
  (user-error "Run this byte compilation in a separate --batch Emacs"))
(setq user-emacs-directory
      (file-name-as-directory
       (file-name-directory
        (directory-file-name (file-name-directory load-file-name)))))
(load (expand-file-name "early-init.el" user-emacs-directory) nil 'nomessage)
(load (expand-file-name "init.el" user-emacs-directory) nil 'nomessage)
(dolist (directory '("modules/" "pkgs/"))
  (byte-recompile-directory
   (expand-file-name directory user-emacs-directory) 0 t))
(message "Byte compilation complete: %s" user-emacs-directory)

;;; byte-compile.el ends here
