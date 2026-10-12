;;; help.el --- Rich, on-demand Emacs Lisp help -*- lexical-binding: t; -*-

(require 'packages)

;; Keep inspection lazy and use only Helpful's public commands.  The original
;; describe commands remain available through M-x for ordinary built-in help.
(packages/declare 'helpful)
(use-package helpful
  :ensure nil
  :bind (("C-h f" . helpful-callable)
         ("C-h v" . helpful-variable)
         ("C-h k" . helpful-key)
         ("C-h x" . helpful-command)
         ("C-h C-." . helpful-at-point)))

;;; help.el ends here
