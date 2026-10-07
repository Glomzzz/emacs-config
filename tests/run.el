;;; run.el --- Batch configuration regression runner -*- lexical-binding: t; -*-

(require 'cl-lib)
(require 'ert)

(setq user-emacs-directory
      (file-name-as-directory
       (file-name-directory
        (directory-file-name (file-name-directory load-file-name)))))
(setq native-comp-jit-compilation nil
      package-native-compile nil)

(load (expand-file-name "early-init.el" user-emacs-directory)
      nil 'nomessage)

;; Reuse installed packages without touching the user's history, Customize,
;; quickstart file, or other state.  Normal startup never installs packages.
(let* ((package-directory (cache/folder "elpa"))
       (state-directory (make-temp-file "emacs-config-tests-" t))
       (cache/root (file-name-as-directory state-directory))
       (original-cache-folder (symbol-function 'cache/folder))
       stats)
  (unwind-protect
      (cl-letf (((symbol-function 'cache/folder)
                 (lambda (path)
                   (if (equal path "elpa")
                       package-directory
                     (funcall original-cache-folder path)))))
        (load (expand-file-name "init.el" user-emacs-directory)
              nil 'nomessage)
        (load (expand-file-name "tests/configuration-tests.el"
                                user-emacs-directory)
              nil 'nomessage)
        (setq stats (ert-run-tests-batch "^config-test/")))
    (dolist (mode '(savehist-mode recentf-mode save-place-mode))
      (when (fboundp mode)
        (funcall mode -1)))
    (delete-directory state-directory t))
  (kill-emacs (if (and stats
                       (zerop (ert-stats-completed-unexpected stats)))
                  0
                1)))

;;; run.el ends here
