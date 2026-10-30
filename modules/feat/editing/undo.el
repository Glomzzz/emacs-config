;;; undo.el --- Branching undo history -*- lexical-binding: t; -*-

(require 'packages)

;; Keep the undo tree in memory only: nothing is written under the cache root.
(packages/declare 'undo-tree)
(use-package undo-tree
  :ensure nil
  :init
  (global-undo-tree-mode)
  :custom
  (undo-tree-auto-save-history nil))

;;; undo.el ends here
