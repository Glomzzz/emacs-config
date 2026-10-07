;;; theme.el --- Gruber Darker theme setup -*- lexical-binding: t; -*-

(require 'packages)
(require 'cl-lib)
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
  "Normalize obsolete attributes only in Gruber Darker's face ARGS."
  (apply orig theme
         (if (eq theme 'gruber-darker)
             (mapcar #'theme--replace-nil-face-attributes args)
           args)))

(defun theme/load-gruber-darker ()
  "Load Gruber Darker with a compatibility wrapper scoped to this load."
  (let ((original (symbol-function 'custom-theme-set-faces)))
    (cl-letf (((symbol-function 'custom-theme-set-faces)
               (lambda (theme &rest args)
                 (apply #'theme--custom-theme-set-faces original theme args))))
      (load-theme 'gruber-darker t))))

(let ((warning-inhibit-types
       (cons '(files missing-lexbind-cookie) warning-inhibit-types)))
  (when (file-readable-p custom-file)
    (load custom-file nil 'nomessage))
  (when (package-installed-p 'gruber-darker-theme)
    (theme/load-gruber-darker)))

(provide 'theme)

;;; theme.el ends here
