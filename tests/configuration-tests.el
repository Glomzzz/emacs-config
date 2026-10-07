;;; configuration-tests.el --- Configuration regressions -*- lexical-binding: t; -*-

(require 'cl-lib)
(require 'ert)
(require 'eglot)
(require 'project)

(defmacro config-test/with-directory (&rest body)
  "Run BODY with a temporary project ROOT, then remove it."
  (declare (indent 0) (debug t))
  `(let* ((root (file-name-as-directory
                (make-temp-file "emacs-config-test-" t)))
          (default-directory root)
          (project-vc-cache-timeout 0)
          (project-vc-non-essential-cache-timeout 0))
     (unwind-protect
         (progn ,@body)
       (delete-directory root t))))

(defun config-test/file (root path &optional content)
  "Write CONTENT to PATH below ROOT and return its absolute name."
  (let ((file (expand-file-name path root)))
    (make-directory (file-name-directory file) t)
    (write-region (or content "") nil file nil 'silent)
    file))

(ert-deftest config-test/workspace-settings-are-separated ()
  (dolist (entry '((nix-ts-mode . :nixd)
                   (typst-ts-mode . :tinymist)
                   (typescript-ts-mode . :typescript)
                   (haskell-mode . :haskell)))
    (with-temp-buffer
      (setq major-mode (car entry))
      (cl-letf (((symbol-function 'eglot--major-modes)
                 (lambda (_server) (list (car entry)))))
        (should (plist-member (lsp/workspace-configuration 'server)
                              (cdr entry)))))))

(provide 'configuration-tests)
;;; configuration-tests.el ends here
