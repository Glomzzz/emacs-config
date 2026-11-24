;;; fff-tests.el --- fff project search contract -*- lexical-binding: t; -*-

(require 'ert)
(require 'cl-lib)

(ert-deftest config-test/fff-declares-pinned-git-source ()
  (let ((source (alist-get 'fff packages/vc-sources)))
    (should source)
    (should (equal (plist-get source :url)
                   "https://github.com/Cbeck527/fff-emacs"))
    (should (eq (plist-get source :vc-backend) 'Git))
    (should (equal (plist-get source :lisp-dir) "lisp"))
    (should (equal (plist-get source :rev)
                   "4d00123b738fa6c4493f6e89e3eb916278c910b4"))))

(ert-deftest config-test/fff-owns-c-c-s-and-moves-ripgrep ()
  (should (eq (key-binding (kbd "C-c s")) 'fff/grep))
  (should (eq (key-binding (kbd "C-c S")) 'consult-ripgrep))
  (should (eq (key-binding (kbd "C-c F")) 'fff-find-file)))

(ert-deftest config-test/fff-grep-falls-back-to-ripgrep-outside-project ()
  (let (called)
    (cl-letf (((symbol-function 'project-current) (lambda (&rest _) nil))
              ((symbol-function 'consult-ripgrep)
               (lambda (&rest _) (setq called 'ripgrep)))
              ((symbol-function 'fff-grep)
               (lambda (&rest _) (setq called 'fff))))
      (fff/grep)
      (should (eq called 'ripgrep)))))

(ert-deftest config-test/fff-grep-uses-fff-inside-project ()
  (let (called)
    (cl-letf (((symbol-function 'project-current)
               (lambda (&rest _) '(transient "/tmp/")))
              ((symbol-function 'consult-ripgrep)
               (lambda (&rest _) (setq called 'ripgrep)))
              ((symbol-function 'fff-grep)
               (lambda (&rest _) (setq called 'fff))))
      (fff/grep)
      (should (eq called 'fff)))))

(ert-deftest config-test/fff-helper-searches-a-project ()
  "The real helper answers file and content searches for a scratch project."
  (skip-unless (and (executable-find "fff-emacs-helper")
                    (require 'fff nil t)))
  (let* ((root (file-name-as-directory (make-temp-file "fff-project-" t)))
         (cache (make-temp-file "fff-cache-" t))
         (process-environment
          (cons (format "XDG_CACHE_HOME=%s" cache) process-environment)))
    (unwind-protect
        (progn
          (with-temp-file (expand-file-name "alpha.txt" root)
            (insert "needle here\n"))
          (fff-stop)
          (cl-letf (((symbol-function 'fff--request-root) (lambda () root)))
            (let* ((files (fff-search-files-sync "alpha" 10))
                   (hits (fff-grep-files-sync "needle" 10)))
              (should (cl-some
                       (lambda (item)
                         (equal (fff--alist-get 'relative_path item) "alpha.txt"))
                       (fff--alist-get 'items files)))
              (should (= 1 (length (fff--alist-get 'items hits)))))))
      (fff-stop)
      (delete-directory root t)
      (delete-directory cache t))))

;;; fff-tests.el ends here
