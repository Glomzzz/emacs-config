;;; undo.el --- Branching undo history -*- lexical-binding: t; -*-

(require 'packages)

;; The tree is kept in memory and saved only by the explicit menu commands.
;; Those write under the cache root, not beside the edited files.
(packages/declare 'undo-tree)
(use-package undo-tree
  :ensure nil
  :init
  (global-undo-tree-mode)
  :after hydra
  :bind ("C-x C-h u" . hydra-undo-tree/body)
  :hydra (hydra-undo-tree (:hint nil)
                          "
 _p_: undo _n_: redo _s_: save _l_: load  "
                          ("p" undo-tree-undo)
                          ("n" undo-tree-redo)
                          ("s" undo-tree-save-history)
                          ("l" undo-tree-load-history)
                          ("u" undo-tree-visualize "visualize" :color blue)
                          ("q" nil "quit" :color blue))
  :custom
  (undo-tree-auto-save-history nil)
  (undo-tree-history-directory-alist `(("." . ,(cache/folder "undo-tree")))))

;;; undo.el ends here
