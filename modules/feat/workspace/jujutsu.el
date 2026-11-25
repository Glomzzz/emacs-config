;;; jujutsu.el --- Jujutsu integration -*- lexical-binding: t; -*-

(require 'packages)

;; Patch the source before byte/native compilation, including on VC upgrades.
(let ((source
       `(:url "https://github.com/0WD0/majutsu"
         :vc-backend Git
         :shell-command
         ,(mapconcat #'shell-quote-argument
                     (list (expand-file-name invocation-name invocation-directory)
                           "--batch" "-Q" "--load"
                           (expand-file-name "scripts/patch-majutsu.el"
                                             user-emacs-directory)
                           "--funcall" "jujutsu/patch-majutsu")
                     " "))))
  (with-eval-after-load 'package-vc
    ;; Authorize only this package's build command, not arbitrary VC builds.
    (unless (eq package-vc-allow-build-commands t)
      (add-to-list 'package-vc-allow-build-commands 'majutsu))
    ;; Already installed checkouts also need the build step on their next upgrade.
    (setf (alist-get 'majutsu package-vc-selected-packages) source))
  (packages/declare-vc 'majutsu source))
(use-package majutsu
  :ensure nil
  :commands (majutsu majutsu-log majutsu-dispatch)
  :bind (("C-x g" . majutsu-log)
         ("C-x M-g" . majutsu-dispatch)
         ("C-x j" . majutsu-log)
         ("C-x M-j" . majutsu-dispatch)))

;;; jujutsu.el ends here
