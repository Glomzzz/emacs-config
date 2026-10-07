;;; bootstrap.el --- Standalone first-run package installation -*- lexical-binding: t; -*-

;; Run with: emacs --batch -Q -l /path/to/emacs/scripts/bootstrap.el
;; Resolve the checkout, not the caller's current directory or ~/.emacs.d.
(unless noninteractive
  (user-error "Run this bootstrap in a separate --batch -Q Emacs"))
(setq user-emacs-directory
      (file-name-as-directory
       (file-name-directory
        (directory-file-name (file-name-directory load-file-name))))
      user-init-file (expand-file-name "init.el" user-emacs-directory)
      ;; Install eager dependencies before their use-package forms run.
      packages/bootstrap-mode t
      native-comp-jit-compilation nil
      package-native-compile nil)

(load user-init-file nil 'nomessage)
(message "Bootstrap complete: %d declared packages; cache: %s"
         (length packages/declared) cache/root)

;;; bootstrap.el ends here
