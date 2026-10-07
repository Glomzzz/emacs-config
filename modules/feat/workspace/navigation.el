;;; navigation.el --- Consult navigation and search commands -*- lexical-binding: t; -*-

(require 'packages)
(declare-function consult--customize-put "consult" (cmds prop form))

(packages/declare 'consult)
(use-package consult
  :ensure nil
  :custom
  ;; A short debounce keeps previews responsive without opening every transient
  ;; candidate while typing quickly.
  (consult-preview-key '(:debounce 0.2 any))
  ;; Press `<', then a source key, to narrow multi-source commands.
  (consult-narrow-key "<")
  (register-preview-delay 0.5)
  (xref-show-definitions-function #'consult-xref)
  (xref-show-xrefs-function #'consult-xref)
  ;; Keep the stock commands available through familiar keys while replacing
  ;; their UI with Consult's richer candidates and live previews.
  :bind (;; C-c bindings in `mode-specific-map'
         ("C-c s" . consult-ripgrep)
         ("C-c r" . consult-recent-file)
         ("C-c M-x" . consult-mode-command)
         ("C-c h" . consult-history)
         ("C-c k" . consult-kmacro)
         ("C-c m" . consult-man)
         ("C-c i" . consult-info)
         ([remap Info-search] . consult-info)
         ;; C-x bindings in `ctl-x-map'
         ("C-x M-:" . consult-complex-command)     ;; orig. repeat-complex-command
         ("C-x b" . consult-buffer)                ;; orig. switch-to-buffer
         ("C-x 4 b" . consult-buffer-other-window) ;; orig. switch-to-buffer-other-window
         ("C-x 5 b" . consult-buffer-other-frame)  ;; orig. switch-to-buffer-other-frame
         ("C-x t b" . consult-buffer-other-tab)    ;; orig. switch-to-buffer-other-tab
         ("C-x r b" . consult-bookmark)            ;; orig. bookmark-jump
         ("C-x p b" . consult-project-buffer)      ;; orig. project-switch-to-buffer
         ;; Custom M-# bindings for fast register access
         ("M-#" . consult-register-load)
         ("M-'" . consult-register-store)          ;; orig. abbrev-prefix-mark
         ("C-M-#" . consult-register)
         ;; Other custom bindings
         ("M-y" . consult-yank-pop)                ;; orig. yank-pop
         ;; M-g bindings in `goto-map'
         ("M-g e" . consult-compile-error)
         ("M-g r" . consult-grep-match)
         ("M-g f" . consult-flymake)               ;; Alternative: consult-flycheck
         ("M-g g" . consult-goto-line)             ;; orig. goto-line
         ("M-g M-g" . consult-goto-line)           ;; orig. goto-line
         ("M-g o" . consult-outline)               ;; Alternative: consult-org-heading
         ("M-g m" . consult-mark)
         ("M-g k" . consult-global-mark)
         ("M-g i" . consult-imenu)
         ("M-g I" . consult-imenu-multi)
         ;; M-s bindings in `search-map'
         ("M-s d" . consult-find)                  ;; Alternative: consult-fd
         ("M-s c" . consult-locate)
         ("M-s g" . consult-grep)
         ("M-s G" . consult-git-grep)
         ("M-s r" . consult-ripgrep)
         ("M-s l" . consult-line)
         ("M-s L" . consult-line-multi)
         ("M-s k" . consult-keep-lines)
         ("M-s u" . consult-focus-lines)
         ;; Isearch integration
         ("M-s e" . consult-isearch-history)
         :map isearch-mode-map
         ("M-e" . consult-isearch-history)         ;; orig. isearch-edit-string
         ("M-s e" . consult-isearch-history)       ;; orig. isearch-edit-string
         ("M-s l" . consult-line)                  ;; needed by consult-line
         ("M-s L" . consult-line-multi)            ;; needed by consult-line
         ;; Minibuffer history
         :map minibuffer-local-map
         ("M-s" . consult-history)                 ;; orig. next-matching-history-element
         ("M-r" . consult-history))                ;; orig. previous-matching-history-element
  :config
  ;; Use Consult's compact register preview for built-in register commands too.
  (unless (advice-member-p #'consult-register-window #'register-preview)
    (advice-add #'register-preview :override #'consult-register-window))

  ;; Expensive commands wait slightly longer before previewing than local
  ;; candidate lists such as buffers and lines.
  (consult-customize
   consult-theme
   consult-ripgrep consult-git-grep consult-grep consult-man
   consult-bookmark consult-recent-file consult-xref
   :preview-key '(:debounce 0.4 any))

  ;; `< ?' displays available narrowing keys through Embark.
  (keymap-set consult-narrow-map
              (concat (or consult-narrow-key "<") " ?")
              #'embark-prefix-help-command))

(packages/declare 'consult-dir)
(use-package consult-dir
  :ensure nil
  ;; The current release has an Emacs 31 native-compiler warning while its
  ;; source plist variables are defined later in the file.  Keep the package
  ;; autoloaded until a directory command is actually used.
  :bind (:map minibuffer-local-completion-map
              ("C-x C-d" . consult-dir)
              ("C-x C-j" . consult-dir-jump-file)
              :map minibuffer-local-filename-completion-map
              ("C-x C-d" . consult-dir)
              ("C-x C-j" . consult-dir-jump-file)))

;;; navigation.el ends here
