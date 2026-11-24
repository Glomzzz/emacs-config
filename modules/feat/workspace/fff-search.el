;;; fff-search.el --- Project file and grep search through fff -*- lexical-binding: t; -*-

(require 'packages)

(declare-function consult-ripgrep "consult" (&optional dir initial))

;; The Elisp client and Consult frontend come from upstream Git, pinned to the
;; commit that `pkgs/fff-emacs-helper.nix' in the system flake builds into
;; `fff-emacs-helper'.  The JSON Lines protocol is the contract between them:
;; move both pins together.
(packages/declare-vc
 'fff
 '(:url "https://github.com/Cbeck527/fff-emacs"
   :vc-backend Git
   :lisp-dir "lisp"
   :rev "4d00123b738fa6c4493f6e89e3eb916278c910b4"))

(defun fff/grep ()
  "Grep the current project with fff, or with ripgrep outside a project.
fff indexes one project root, so `project-current' decides which tool runs.
Use \\[consult-ripgrep] (C-c S) to force ripgrep."
  (interactive)
  (if (project-current)
      (fff-grep)
    (consult-ripgrep)))

(use-package fff
  :ensure nil
  :commands (fff-find-file fff-grep fff-grep-symbol-at-point
             fff-diagnostics fff-show-log fff-stop fff-restart)
  :custom
  ;; NixOS installs the helper on the session PATH, including the daemon's.
  (fff-helper-program "fff-emacs-helper")
  :bind (("C-c s" . fff/grep)
         ("C-c F" . fff-find-file)))

(provide 'fff-search)

;;; fff-search.el ends here
