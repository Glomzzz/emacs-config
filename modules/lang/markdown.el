;;; markdown.el --- Markdown editing defaults and LSP startup -*- lexical-binding: t; -*-

(defvar typst-mode-hook)
(defvar typst-ts-mode-hook)

(defun my/markdown-typst-mode ()
  "Fontify Markdown Typst code fences with the best available Typst mode."
  (interactive)
  (let (typst-mode-hook typst-ts-mode-hook)
    (cond
     ((and (require 'treesit nil t)
           (fboundp 'typst-ts-mode)
           (treesit-ready-p 'typst))
      (typst-ts-mode))
     ((fboundp 'typst-mode)
      (typst-mode))
     (t
      (text-mode)))))

(use-package markdown-mode
  :mode ("\\.md\\'" . markdown-mode)
  :custom
  (markdown-fontify-code-blocks-natively t)
  :config
  (dolist (entry '(("typst" . my/markdown-typst-mode)
                   ("typ" . my/markdown-typst-mode)))
    (add-to-list 'markdown-code-lang-modes entry)))

(add-hook 'markdown-mode-hook #'my/eglot-ensure-idle)
