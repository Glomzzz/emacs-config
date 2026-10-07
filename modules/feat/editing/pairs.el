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

(defgroup pairs nil
  "Optional policies on top of Smartparens' language rules."
  :group 'editing)

(defcustom pairs/enabled-modes '(prog-mode conf-mode markdown-mode org-mode)
  "Parent/major modes that opt into automatic Smartparens activation."
  :type '(repeat symbol) :group 'pairs)
(defcustom pairs/automatic-angle-pairing nil
  "Use upstream automatic angle-bracket rules in JavaScript/TypeScript/Rust.
Nil keeps ambiguous operators literal and allows explicit wrapping only.
This policy is applied when language rules load; restart after changing it."
  :type 'boolean :group 'pairs)
(defcustom pairs/pair-escaped-quotes nil
  "Automatically insert a second escaped quote using upstream rules.
Nil leaves manual escapes literal.  Restart after changing this policy."
  :type 'boolean :group 'pairs)

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
  (when (and (apply #'derived-mode-p pairs/enabled-modes)
             (not (minibufferp))
             (not buffer-read-only)
             (not (derived-mode-p 'special-mode 'comint-mode))
             (buffers/small-p))
    (smartparens-mode 1)))

(use-package smartparens
  :ensure nil
  :commands (smartparens-mode sp-cheat-sheet)
  :hook (after-change-major-mode . pairs/enable)
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
  (unless pairs/pair-escaped-quotes
    (sp-pair "\\\"" nil :actions '(wrap navigate))))

;;; pairs.el ends here
