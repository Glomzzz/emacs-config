;;; markdown.el --- Markdown editing defaults and LSP startup -*- lexical-binding: t; -*-

(use-package markdown-mode
  :mode ("\\.md\\'" . markdown-mode)
  :custom
  (markdown-fontify-code-blocks-natively t))

(add-hook 'markdown-mode-hook #'eglot-ensure)
