;;; snippets.el --- Tempel snippet completion -*- lexical-binding: t; -*-

(require 'packages)

(packages/declare 'tempel 'tempel-collection)

(defun snippets/setup-capf ()
  "Add Tempel expansion to the current buffer's completion sources."
  (setq-local completion-at-point-functions
              (cons #'tempel-expand
                    (remove #'tempel-expand completion-at-point-functions))))

(use-package tempel
  :ensure nil
  :bind (("M-+" . tempel-complete)
         ("M-*" . tempel-insert))
  :hook ((prog-mode . snippets/setup-capf)
         (text-mode . snippets/setup-capf)
         (conf-mode . snippets/setup-capf)))

(use-package tempel-collection
  :ensure nil
  :after tempel)

;;; snippets.el ends here
