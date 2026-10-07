;;; format.el --- External formatter integration -*- lexical-binding: t; -*-

(require 'packages)

(defvar-local format/apheleia-owns nil
  "When non-nil, Apheleia owns save-time formatting in this buffer.
Language modules set this when the Eglot server's formatting request is
synchronous and can block Emacs, for example while the server loads a
project cradle.")

(defun format/inhibit-eglot ()
  "Return non-nil when Eglot owns formatting in the current buffer."
  (and (not format/apheleia-owns)
       (fboundp 'eglot-managed-p)
       (eglot-managed-p)))

(defun format/mode-maybe ()
  "Enable Apheleia unless Eglot manages the current buffer."
  (unless (format/inhibit-eglot)
    (require 'apheleia)
    (apheleia-mode 1)))

(packages/declare 'apheleia)
(use-package apheleia
  :ensure nil
  :hook (prog-mode . format/mode-maybe)
  :config
  (add-hook 'apheleia-inhibit-functions #'format/inhibit-eglot)
  (add-hook 'apheleia-skip-functions #'format/inhibit-eglot))

;;; format.el ends here
