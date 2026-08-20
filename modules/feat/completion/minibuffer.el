;;; minibuffer.el --- Minibuffer UI and history -*- lexical-binding: t; -*-

(require 'packages)

;; Keep the prompt predictable before layering a completion UI on top.
(packages/declare 'emacs)
(use-package emacs
  :ensure nil
  :custom
  ;; TAB cycles immediately when only a few candidates remain.
  (completion-cycle-threshold 3)
  ;; Keep hidden directories such as `.git/' visible in Vertico while still
  ;; suppressing generated-file suffixes such as `.elc' and `.o'.
  (completion-ignored-extensions
   (cl-remove-if
    (lambda (extension)
      (and (string-prefix-p "." extension)
           (string-suffix-p "/" extension)))
    completion-ignored-extensions))
  ;; Recursive minibuffers let commands such as M-x be used from a prompt.
  (enable-recursive-minibuffers t)
  ;; Prevent accidental edits to the prompt while keeping it visually distinct.
  (minibuffer-prompt-properties
   '(read-only t cursor-intangible t face minibuffer-prompt))
  ;; TAB first indents and then offers completion when indentation is complete.
  (tab-always-indent 'complete)
  :init
  ;; Show recursive prompt depth and hide defaults once they no longer apply.
  (minibuffer-depth-indicate-mode 1)
  (minibuffer-electric-default-mode 1)
  :hook
  ;; Activate the `cursor-intangible' prompt property configured above.
  (minibuffer-setup . cursor-intangible-mode))

;; Persist frequently used candidates and search text across daemon restarts.
(packages/declare 'savehist)
(use-package savehist
  :ensure nil
  :init
  (setq savehist-file (cache/file "history"))
  (savehist-mode)
  :custom
  (history-delete-duplicates t)
  (history-length 1000)
  (savehist-additional-variables
   '(extended-command-history
     file-name-history
     buffer-name-history
     minibuffer-history))
  (savehist-autosave-interval 60))


;; Vertico supplies a compact vertical view while leaving Emacs' completion
;; machinery and metadata intact.
(packages/declare 'vertico)
(use-package vertico
  :ensure nil
  :custom
  ;; Grow to the number of visible candidates without shrinking between input.
  (vertico-count 12)
  (vertico-cycle t)
  (vertico-resize 'grow-only)
  (vertico-scroll-margin 2)
  :init
  (vertico-mode)
  :bind
  (:map vertico-map
        ("M-?" . minibuffer-completion-help)
        ("M-RET" . minibuffer-force-complete-and-exit)
        ("M-TAB" . minibuffer-complete)))

;; `vertico-directory' ships inside Vertico, so configure the extension through
;; a second declaration of its parent package instead of installing it alone.
(packages/declare 'vertico)

(defun completion/vertico-rename-prompt-p ()
  "Return non-nil when the minibuffer asks for a rename destination."
  (let ((prompt (minibuffer-prompt)))
    (and prompt
         (string-match-p "\\`\\(?:Rename\\|Move\\) .* to" prompt))))

(defun completion/vertico-rename-bindings ()
  "Make RET accept typed input in rename destination prompts."
  (when (and (minibufferp)
             (bound-and-true-p vertico--input)
             (completion/vertico-rename-prompt-p)
             (current-local-map))
    (let ((map (make-sparse-keymap)))
      (set-keymap-parent map (current-local-map))
      (keymap-set map "RET" #'vertico-exit-input)
      (use-local-map map))))

(use-package vertico
  :ensure nil
  :config
  (require 'vertico-directory)
  ;; RET enters directories or accepts the selected file candidate.
  (keymap-set vertico-map "RET" #'vertico-directory-enter)
  ;; TAB performs ordinary prefix completion without submitting the prompt.
  (keymap-set vertico-map "TAB" #'minibuffer-complete)
  (keymap-set vertico-map "DEL" #'vertico-directory-delete-char)
  (keymap-set vertico-map "M-DEL" #'vertico-directory-delete-word)
  (keymap-set vertico-map "C-l" #'vertico-directory-up)
  ;; Run after Vertico installs its per-minibuffer map.
  (add-hook 'minibuffer-setup-hook #'completion/vertico-rename-bindings 90)
  (add-hook 'rfn-eshadow-update-overlay-hook #'vertico-directory-tidy))

;;; minibuffer.el ends here
