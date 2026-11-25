;;; patch-majutsu.el --- Build-time declarations for Majutsu -*- lexical-binding: t; -*-

;; Run from the Majutsu checkout before package-vc compiles it:
;; emacs --batch -Q -l /path/to/patch-majutsu.el -f jujutsu/patch-majutsu
;; Declarations must be in the source, not the parent Emacs process, because
;; asynchronous native-compilation workers do not load this configuration.

(defun jujutsu/patch-majutsu (&optional file)
  "Declare Majutsu's cross-file call to `majutsu-jjdescription-apply-descriptions'.
FILE defaults to majutsu-diff.el in `default-directory'.  Leave an existing
declaration intact and do not rewrite an already patched file."
  (let ((file (or file (expand-file-name "majutsu-diff.el" default-directory)))
        (declaration
         (concat "(declare-function majutsu-jjdescription-apply-descriptions\n"
                 "  \"majutsu-jjdescription\" (descriptions &optional extra-args))")))
    (with-temp-buffer
      (insert-file-contents file)
      (unless (re-search-forward
               "^(declare-function[ \t\n]+majutsu-jjdescription-apply-descriptions\\_>"
               nil t)
        (goto-char (point-min))
        (unless (re-search-forward "^;;; Code:[ \t]*$" nil t)
          (error "Cannot locate Majutsu's code section in %s" file))
        (end-of-line)
        (insert "\n\n;; Defined by majutsu-jjdescription, which majutsu.el loads first.\n"
                declaration)
        (write-region (point-min) (point-max) file nil 'silent)))))

;;; patch-majutsu.el ends here
