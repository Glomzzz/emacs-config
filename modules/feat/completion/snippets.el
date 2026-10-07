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

;; Eglot advertises LSP snippet support only when Yasnippet is available.
;; Bridge its snippet expansion to Tempel so servers that return snippet
;; completions (HLS, TypeScript Server, and others) expand editable fields.
(packages/declare 'eglot-tempel)
(use-package eglot-tempel
  :ensure nil
  :after eglot
  :config
  (eglot-tempel-mode 1))

;;; snippets.el ends here
