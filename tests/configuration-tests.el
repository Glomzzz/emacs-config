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

(ert-deftest config-test/trust-excludes-shared-tmp-and-downloads ()
  (dolist (file (list (expand-file-name "config-test.el" temporary-file-directory)
                      (expand-file-name "Downloads/config-test.el" "~/")))
    (with-temp-buffer
      (setq buffer-file-name file
            buffer-file-truename file)
      (should-not (trusted-content-p)))))

(ert-deftest config-test/trust-includes-development-and-config ()
  (dolist (file (list (expand-file-name "git/config-test.el" "~/")
                      (expand-file-name "init.el" user-emacs-directory)))
    (with-temp-buffer
      (setq buffer-file-name file
            buffer-file-truename file)
      (should (trusted-content-p)))))

(provide 'configuration-tests)
;;; configuration-tests.el ends here
