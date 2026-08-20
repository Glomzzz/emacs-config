;;; context.el --- Contextual completion metadata and actions -*- lexical-binding: t; -*-

(require 'packages)

;; Filter commands by context and expose contextual actions through mouse menus.
(packages/declare 'emacs)
(use-package emacs
  :ensure nil
  :custom
  (context-menu-mode t)
  (read-extended-command-predicate #'command-completion-default-include-p))

;; Marginalia adds contextual annotations such as command docs and file sizes.
(packages/declare 'marginalia)
(use-package marginalia
  :ensure nil
  :custom
  ;; Keep annotations aligned without pushing candidates around.
  (marginalia-align 'right)
  :bind (:map minibuffer-local-map
              ("M-A" . marginalia-cycle))
  :init
  (marginalia-mode))

;; Prefix annotated candidates with icons when a Nerd Font is available.
(packages/declare 'nerd-icons-completion)
(use-package nerd-icons-completion
  :ensure nil
  ;; Load eagerly so icons are active even though Marginalia was enabled above.
  :demand t
  :config
  (add-hook 'marginalia-mode-hook
            #'nerd-icons-completion-marginalia-setup)
  (nerd-icons-completion-mode 1))

;; Embark provides context-sensitive actions for the candidate or object at
;; point, independent of which command produced it.
(packages/declare 'embark)
(use-package embark
  :ensure nil
  :bind
  (("C-." . embark-act)
   ("C-;" . embark-dwim)
   ("C-h B" . embark-bindings))
  :init
  ;; Prefix help itself becomes a completion prompt with available actions.
  (setq prefix-help-command #'embark-prefix-help-command)
  ;; Install the autoloaded hook now so right-click can load Embark on demand.
  (add-hook 'context-menu-functions #'embark-context-menu 100)
  :config
  ;; Collect buffers are transient views, so their mode line adds little value.
  (add-to-list 'display-buffer-alist
               '("\\`\\*Embark Collect \\(Live\\|Completions\\)\\*"
                 nil
                 (window-parameters (mode-line-format . none)))))

;; Preserve Embark actions and exports for candidates produced by Consult.
(packages/declare 'embark-consult)
(use-package embark-consult
  :ensure nil
  :after (embark consult))

;;; context.el ends here
