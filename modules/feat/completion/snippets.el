;;; snippets.el --- Tempel snippet completion -*- lexical-binding: t; -*-

(require 'packages)
(require 'seq)

(declare-function tempel-done "tempel" (&optional all))
(defvar tempel--active)

(packages/declare 'tempel 'tempel-collection)

(defun snippets/finish-outside ()
  "Finish active Tempel snippets when point leaves all their ranges.
Keep fields editable at either boundary and inside enclosing snippets."
  (when (and (bound-and-true-p tempel--active)
             ;; Tempel has no public range API.  Only inspect its range overlays;
             ;; let the public finish command run post actions and remove fields.
             (not (seq-some
                   (lambda (state)
                     (let ((range (caar state)))
                       (and (overlayp range)
                            (eq (overlay-buffer range) (current-buffer))
                            (<= (overlay-start range) (point) (overlay-end range)))))
                   tempel--active)))
    (tempel-done t)))

(defun snippets/setup-capf ()
  "Add Tempel completion and snippet cleanup to the current buffer."
  (setq-local completion-at-point-functions
              (cons #'tempel-expand
                    (remove #'tempel-expand completion-at-point-functions)))
  (add-hook 'post-command-hook #'snippets/finish-outside nil t))

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
