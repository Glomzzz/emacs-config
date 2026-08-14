;;; fish.el --- Fish editing and command completion support -*- lexical-binding: t; -*-

(use-package fish-mode
  :mode "\\.fish\\'"
  :interpreter "fish")

(use-package fish-completion
  :if (executable-find "fish")
  :hook ((shell-mode eshell-mode) . fish-completion-mode)
  :custom
  (fish-completion-command
   (or (executable-find "fish-completion-shell")
       (executable-find "fish"))))

;;; fish.el ends here
