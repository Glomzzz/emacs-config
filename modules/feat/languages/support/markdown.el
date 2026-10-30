;;; markdown.el --- Markdown language support -*- lexical-binding: t; -*-

(require 'packages)

(declare-function markdown-export-file-name "markdown-mode" (&optional extension))
(declare-function markdown-export "markdown-mode" (&optional output-file))
(declare-function markdown-export-and-preview "markdown-mode" ())
(declare-function markdown-live-preview-get-filename "markdown-mode" ())

;; markdown-mode provides the editing mode and the preview commands:
;; `markdown-live-preview-mode' (C-c C-c l) renders the buffer in an Emacs
;; window, and `markdown-export-and-preview' (C-c C-c v) opens the exported
;; HTML in the browser.  Emacs also ships `markdown-ts-mode', but it derives
;; from text-mode and would drop these commands, so markdown is deliberately
;; not registered with treesit-auto.
(packages/declare 'markdown-mode)
(use-package markdown-mode
  :ensure nil
  :mode (("\\.md\\'" . markdown-mode)
         ("\\.markdown\\'" . markdown-mode)
         ("\\.mdx\\'" . markdown-mode)
         ("README\\(?:\\.md\\)?\\'" . gfm-mode))
  :after hydra
  ;; The menu lives in the mode map, so it only runs in Markdown buffers.
  :bind (:map markdown-mode-map
              ("C-x C-h M" . hydra-markdown/body))
  ;; Menu adapted from the hydra wiki's markdown-mode example.
  :hydra (hydra-markdown
          (:hint nil)
          "
Format: _s_ bold  _e_ italic  _c_ code  _b_ blockquote  _p_ pre
Heading: _h_ auto  _1_ h1  _2_ h2  _3_ h3  _4_ h4
Lists: _m_ item  _l_ promote  _r_ demote  _u_ move up  _d_ move down
Links: _L_ link  _U_ uri  _F_ footnote  _W_ wiki link  _R_ reference  _q_ quit"
          ("s" markdown-insert-bold)
          ("e" markdown-insert-italic)
          ("b" markdown-insert-blockquote :color blue)
          ("p" markdown-insert-pre :color blue)
          ("c" markdown-insert-code)
          ("h" markdown-insert-header-dwim)
          ("1" markdown-insert-header-atx-1)
          ("2" markdown-insert-header-atx-2)
          ("3" markdown-insert-header-atx-3)
          ("4" markdown-insert-header-atx-4)
          ("m" markdown-insert-list-item)
          ("l" markdown-promote)
          ("r" markdown-demote)
          ("d" markdown-move-down)
          ("u" markdown-move-up)
          ("L" markdown-insert-link :color blue)
          ("U" markdown-insert-uri :color blue)
          ("F" markdown-insert-footnote :color blue)
          ("W" markdown-insert-wiki-link :color blue)
          ("R" markdown-insert-reference-link :color blue)
          ("q" nil :color blue))
  :custom
  ;; pandoc converts on stdin/stdout; gfm matches GitHub-flavored Markdown.
  (markdown-command '("pandoc" "--from=gfm" "--to=html5" "--standalone")))

(defvar markdown/preview-directory
  (expand-file-name "emacs/markdown-preview/" temporary-file-directory)
  "Directory for markdown preview HTML exports.
Defaults to /tmp/emacs/markdown-preview/ through
`temporary-file-directory'.")

(defun markdown/preview-file ()
  "Return the preview-directory HTML path for the current buffer.
The name keeps the source base name plus a hash of the source path so
files that share a base name cannot collide.  Returns nil when the
buffer does not visit a file."
  (when-let* ((file (markdown-export-file-name ".html")))
    (let ((dir (file-name-as-directory markdown/preview-directory)))
      (make-directory dir t)
      (expand-file-name
       (concat (file-name-base file)
               "-" (substring (sha1 file) 0 8) ".html")
       dir))))

(defun markdown/live-preview-filename (_orig)
  "Redirect live-preview exports to `markdown/preview-directory'."
  (markdown/preview-file))

(defun markdown/export-and-preview (_orig)
  "Export to `markdown/preview-directory' and browse the result."
  (if-let* ((file (markdown/preview-file)))
      (browse-url-of-file (markdown-export file))
    (user-error "Buffer %s does not visit a file" (current-buffer))))

;; markdown-mode writes preview HTML next to the source file by default;
;; keep the project tree clean instead.  `markdown-preview' (C-c C-c p)
;; already renders from a temporary file, so only the live preview and the
;; export-and-preview commands need the redirect.
(with-eval-after-load 'markdown-mode
  (unless (advice-member-p #'markdown/live-preview-filename
                           #'markdown-live-preview-get-filename)
    (advice-add 'markdown-live-preview-get-filename
                :around
                #'markdown/live-preview-filename))
  (unless (advice-member-p #'markdown/export-and-preview
                           #'markdown-export-and-preview)
    (advice-add 'markdown-export-and-preview
                :around
                #'markdown/export-and-preview)))

;;; markdown.el ends here
