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

(ert-deftest config-test/project-finder-preserves-git-and-ignores ()
  (config-test/with-directory
    (should (zerop (call-process "git" nil nil nil "init" "--quiet" root)))
    (config-test/file root "package.json" "{}")
    (config-test/file root ".gitignore" "ignored.txt\n")
    (config-test/file root "kept.txt")
    (config-test/file root "ignored.txt")
    (let ((project (project-current nil root)))
      (should (eq (car project) 'vc))
      (should (eq (cadr project) 'Git))
      (should (member (expand-file-name "kept.txt" root) (project-files project)))
      (should-not (member (expand-file-name "ignored.txt" root)
                          (project-files project))))))

(ert-deftest config-test/project-finder-prefers-nearer-haskell-cradle ()
  (config-test/with-directory
    (config-test/file root "package.json" "{}")
    (config-test/file root "haskell/hie.yaml" "cradle: {}")
    (make-directory (expand-file-name "haskell/src/" root))
    (let ((project (project-current nil (expand-file-name "haskell/src/" root))))
      (should (equal (project-root project) (expand-file-name "haskell/" root)))
      (should (eq (car project) 'vc)))))

(ert-deftest config-test/project-finder-prefers-nearer-javascript-manifest ()
  (config-test/with-directory
    (config-test/file root "stack.yaml")
    (config-test/file root "web/package.json" "{}")
    (make-directory (expand-file-name "web/src/" root))
    (should (equal
             (project-root (project-current nil (expand-file-name "web/src/" root)))
             (expand-file-name "web/" root)))))

(ert-deftest config-test/nested-manifest-keeps-git-backend ()
  (config-test/with-directory
    (should (zerop (call-process "git" nil nil nil "init" "--quiet" root)))
    (config-test/file root "web/package.json" "{}")
    (let ((project (project-current nil (expand-file-name "web/" root))))
      (should (equal (project-root project) (expand-file-name "web/" root)))
      (should (eq (cadr project) 'Git)))))

(ert-deftest config-test/project-finder-matches-dotted-cabal-file ()
  (config-test/with-directory
    (config-test/file root "example.test.cabal")
    (make-directory (expand-file-name "src/" root))
    (should (equal (project-root
                    (project-current nil (expand-file-name "src/" root)))
                   root))))

(ert-deftest config-test/javascript-selects-nearest-manifest ()
  (config-test/with-directory
    (config-test/file root "deno.json" "{}")
    (config-test/file root "inner/package.json" "{}")
    (make-directory (expand-file-name "inner/src/" root))
    (should (equal
             (javascript--marker-root (expand-file-name "inner/src/" root))
             (expand-file-name "inner/" root)))))

(ert-deftest config-test/lockfiles-do-not-create-projects ()
  (config-test/with-directory
    (config-test/file root "bun.lock")
    (let ((locate-dominating-stop-dir-regexp
           (concat "\\`" (regexp-quote root) "\\'")))
      (should-not (javascript--marker-root root))
      (should-not (project-current nil root)))))

(ert-deftest config-test/javascript-tools-use-javascript-manifest ()
  (config-test/with-directory
    (config-test/file root "package.json" "{}")
    (config-test/file root "haskell/hie.yaml")
    (let ((default-directory (expand-file-name "haskell/" root)))
      (should (equal (javascript/project-root) root)))))

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
