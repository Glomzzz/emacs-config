;;; completion.el --- Completion UI built around Corfu and popup info -*- lexical-binding: t; -*-

(use-package yasnippet
  :demand t)

(defun my/parenthesized-expression-after-point-p ()
  "Return non-nil when point is followed by a balanced parenthesized form."
  (save-excursion
    (skip-chars-forward " \t")
    (and (eq (char-after) ?\()
         (condition-case nil
             (progn (forward-sexp 1) t)
           (scan-error nil)))))

(defun my/eglot-completion-snippet (snippet)
  "Normalize an Eglot completion SNIPPET for the text after point.

When point is already followed by a balanced parenthesized form,
drop the trailing argument list (and the final `$0' placeholder) from
the snippet so accepting a completion does not duplicate the parens.
The snippet text is otherwise left untouched: stripping characters
here used to mangle legitimate snippets (e.g. generic or multi-argument
completions), so any server-specific cleanup must be scoped to that
server's `eglot-managed-mode' hook instead."
  (if (and (my/parenthesized-expression-after-point-p)
           (string-match
            "\\`\\(.*?\\)(\\(?:.\\|\n\\)*)\\(\\(?:\\$0\\|\\${0}\\)\\)?\\'"
            snippet))
      (concat (match-string 1 snippet)
              (or (match-string 2 snippet) ""))
    snippet))

(defun my/eglot-snippet-expander (expander)
  "Wrap EXPANDER to normalize completion snippets before expansion."
  (when expander
    (lambda (snippet &rest args)
      (apply expander (my/eglot-completion-snippet snippet) args))))

(with-eval-after-load 'eglot
  (unless (advice-member-p #'my/eglot-snippet-expander
                           #'eglot--snippet-expansion-fn)
    (advice-add #'eglot--snippet-expansion-fn
                :filter-return
                #'my/eglot-snippet-expander)))

(use-package corfu
  :hook (after-init . global-corfu-mode)
  :custom
  (corfu-auto t)
  (corfu-auto-delay 0.1)
  (corfu-auto-prefix 2)
  :init
  (with-eval-after-load 'corfu
    (require 'corfu-popupinfo nil t))
  :bind
  (:map corfu-map
        ("M-d" . corfu-popupinfo-toggle)
        ("M-l" . corfu-popupinfo-location)
        ("M-p" . corfu-popupinfo-scroll-down)
        ("M-n" . corfu-popupinfo-scroll-up)))

(with-eval-after-load 'corfu-popupinfo
  (setq corfu-popupinfo-delay '(0.4 . 0.2)
        corfu-popupinfo-max-width 80
        corfu-popupinfo-max-height 20)
  (corfu-popupinfo-mode 1))
