;;; pairs.el --- Language-aware pairing and structural editing -*- lexical-binding: t; -*-

(require 'packages)

;; Only one engine may own insertion, skipping, and pair deletion.  This also
;; disables the old global engine when this module is reloaded in a session.
(use-package elec-pair
  :ensure nil
  :init
  (electric-pair-mode -1))

;; The MELPA pin lives in core/packages.el, before archive metadata is read.
(packages/declare 'smartparens)

(declare-function smartparens-mode "smartparens" (&optional arg))
(declare-function sp-wrap-with-pair "smartparens" (pair))
(declare-function sp-pair "smartparens" (open close &rest arguments))
(declare-function sp-get-pair "smartparens" (id &optional prop))

(defun pairs/wrap-angle ()
  "Wrap the region or next expression in angle brackets when supported."
  (interactive "*")
  (unless (memq 'wrap (sp-get-pair "<" :actions))
    (user-error "Angle wrapping is not defined for %s" major-mode))
  (sp-wrap-with-pair "<"))

(defun pairs/enable ()
  "Enable non-strict Smartparens in ordinary structured editing buffers.
Do not install pairing hooks in minibuffers, special/read-only buffers,
or very large buffers.  Plain prose and process buffers do not opt in."
  (unless (or (minibufferp)
              buffer-read-only
              (derived-mode-p 'special-mode 'comint-mode)
              (not (buffers/small-p)))
    (smartparens-mode 1)))

(use-package smartparens
  :ensure nil
  :commands (smartparens-mode sp-cheat-sheet)
  :hook ((prog-mode . pairs/enable)
         (conf-mode . pairs/enable)
         (markdown-mode . pairs/enable)
         (org-mode . pairs/enable))
  :custom
  ;; Skip at the actual end of an expression, never jump across its contents.
  (sp-autoskip-closing-pair 'always-end)
  :bind (:map smartparens-mode-map
              ("C-c p (" . sp-wrap-round)
              ("C-c p [" . sp-wrap-square)
              ("C-c p {" . sp-wrap-curly)
              ("C-c p <" . pairs/wrap-angle)
              ("C-c p s" . sp-forward-slurp-sexp)
              ("C-c p S" . sp-backward-slurp-sexp)
              ("C-c p b" . sp-forward-barf-sexp)
              ("C-c p B" . sp-backward-barf-sexp)
              ("C-c p u" . sp-splice-sexp)
              ("C-c p r" . sp-raise-sexp)
              ("C-c p n" . sp-forward-sexp)
              ("C-c p p" . sp-backward-sexp)
              ("C-c p q" . quoted-insert)
              ("C-c p t" . smartparens-mode)
              ("C-c p ?" . sp-cheat-sheet))
  :config
  ;; Let upstream own syntax/context rules, including Lisp quotes, Haskell
  ;; primes, Rust lifetimes, and Markdown code spans.  Strict mode stays off:
  ;; normal deletion, kill/yank, and temporarily unbalanced code remain valid.
  (require 'smartparens-config)
  ;; An escaped quote inside a string is content, not a nested string.  The
  ;; upstream escaped-quote pair otherwise inserts a second escape as well.
  ;; Retain explicit wrapping/navigation, but leave manual escapes literal.
  (sp-pair "\\\"" nil :actions '(wrap navigate)))

;;; pairs.el ends here
