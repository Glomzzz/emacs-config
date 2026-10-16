;;; patch-fingertip.el --- Build-time declarations for Fingertip -*- lexical-binding: t; -*-

;; Run from the Fingertip checkout before package-vc compiles it:
;; emacs --batch -Q -l /path/to/patch-fingertip.el -f pairs/patch-fingertip
;; Declarations must be in the source, not the parent Emacs process, because
;; asynchronous native-compilation workers do not load this configuration.

(defun pairs/patch-fingertip (&optional file)
  "Add missing optional-function declarations to Fingertip's FILE.
FILE defaults to fingertip.el in `default-directory'.  Leave existing
upstream declarations intact and do not rewrite an already patched file."
  (let ((file (or file (expand-file-name "fingertip.el" default-directory)))
        (declarations
         '((declare-function sgml-skip-tag-forward "sgml-mode" (arg))
           (declare-function sgml-skip-tag-backward "sgml-mode" (arg))
           (declare-function web-mode-element-beginning-position "ext:web-mode" (&optional pos))
           (declare-function web-mode-element-end-position "ext:web-mode" (&optional pos))
           (declare-function web-mode-element-parent-position "ext:web-mode" (&optional pos))
           (declare-function web-mode-insert-text-at-pos "ext:web-mode" (text pos))
           (declare-function web-mode-element-parent "ext:web-mode" ())
           (declare-function web-mode-element-vanish "ext:web-mode" (&optional arg))
           (declare-function ielm-return "ielm" (&optional for-effect))))
        missing)
    (with-temp-buffer
      (insert-file-contents file)
      (dolist (declaration declarations)
        (goto-char (point-min))
        (unless (re-search-forward
                 (concat "^(declare-function[ \t\n]+"
                         (regexp-quote (symbol-name (cadr declaration))) "\\_>")
                 nil t)
          (push declaration missing)))
      (when missing
        (goto-char (point-min))
        (unless (re-search-forward "^;;; Code:[ \t]*$" nil t)
          (error "Cannot locate Fingertip's code section in %s" file))
        (end-of-line)
        (insert "\n\n;; Optional integrations; keep them unloaded during compilation.\n"
                (mapconcat #'prin1-to-string (nreverse missing) "\n"))
        (write-region (point-min) (point-max) file nil 'silent)))))

;;; patch-fingertip.el ends here
