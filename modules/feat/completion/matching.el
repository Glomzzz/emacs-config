;;; matching.el --- Completion matching policy -*- lexical-binding: t; -*-
(require 'packages)

;; Matching defaults belong here rather than in the minibuffer presentation.
(packages/declare 'emacs)
(use-package emacs
  :ensure nil
  :custom
  ;; Orderless is the global matcher below; file names retain Emacs' component-
  ;; aware partial completion for paths such as `u/l/b'.
  (completion-category-defaults nil)
  (completion-category-overrides '((file (styles partial-completion))))
  (completion-ignore-case t)
  (read-buffer-completion-ignore-case t)
  (read-file-name-completion-ignore-case t))

;; Orderless matches every space-separated component in any order.
(packages/declare 'orderless)
(use-package orderless
  :ensure nil
  :custom
  ;; Split on unescaped spaces, so `foo\ bar' remains one component.
  (orderless-component-separator #'orderless-escapable-split)
  ;; Affixes select a matching style: `!foo' excludes, `~foo' is fuzzy,
  ;; `=foo' is literal, and `,foo' matches initials.
  (orderless-style-dispatchers '(orderless-affix-dispatch))
  (completion-styles '(orderless basic))
  (orderless-smart-case t)
  :init
  ;; Emacs 31 can match partial file components as substrings.
  (when (boundp 'completion-pcm-leading-wildcard)
    (setq completion-pcm-leading-wildcard t)))

;;; matching.el ends here
