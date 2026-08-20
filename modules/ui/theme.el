;;; theme.el --- Gruber Darker theme setup -*- lexical-binding: t; -*-

(require 'packages)
(require 'warnings)
(packages/declare 'gruber-darker-theme)

(defun theme--replace-nil-face-attributes (value)
  "Replace nil foreground/background values in a theme face spec.

Emacs 31 no longer accepts nil for these attributes, while older themes used
it to mean that the face should inherit the terminal default."
  (cond
   ((consp value)
    (if (and (keywordp (car value))
             (memq (car value) '(:foreground :background))
             (consp (cdr value))
             (null (cadr value)))
        (cons (car value)
              (cons 'unspecified
                    (theme--replace-nil-face-attributes (cddr value))))
      (cons (theme--replace-nil-face-attributes (car value))
            (theme--replace-nil-face-attributes (cdr value)))))
   (t value)))

(defun theme--custom-theme-set-faces (orig theme &rest args)
  "Apply theme face ARGS after normalising obsolete nil attributes."
  (apply orig theme
         (mapcar #'theme--replace-nil-face-attributes args)))

(unless (advice-member-p #'theme--custom-theme-set-faces
                         #'custom-theme-set-faces)
  (advice-add 'custom-theme-set-faces
              :around
              #'theme--custom-theme-set-faces))

(let ((warning-inhibit-types
       (cons '(files missing-lexbind-cookie) warning-inhibit-types)))
  (when (file-readable-p custom-file)
    (load custom-file nil 'nomessage))
  (when (package-installed-p 'gruber-darker-theme)
    (load-theme 'gruber-darker t)))

(provide 'theme)

;;; theme.el ends here
