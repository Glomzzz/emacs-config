;;; debug.el --- Debug Adapter Protocol integration -*- lexical-binding: t; -*-

(require 'packages)

(defvar debug/dape-language-configs nil
  "Dape configurations registered by language-specific modules.

Each entry is an alist element of the form (NAME . CONFIG), where NAME is a
symbol and CONFIG is a Dape configuration plist.  The list is kept separately
from Dape so language modules can register configurations before Dape loads.")

(defun debug/apply-language-configs ()
  "Apply registered language configurations to `dape-configs'."
  (when (boundp 'dape-configs)
    (dolist (entry debug/dape-language-configs)
      (setf (alist-get (car entry) dape-configs)
            (cdr entry)))))

(defun debug/register-config (name config)
  "Register Dape CONFIG under NAME.

Language modules can call this function without loading Dape eagerly.  Dape's
built-in configurations are not copied here; use this for adapters or launch
conventions that are specific to a project or language mode.  A matching NAME
intentionally replaces an existing Dape entry."
  (unless (symbolp name)
    (signal 'wrong-type-argument (list 'symbolp name)))
  (setf (alist-get name debug/dape-language-configs) config)
  (if (featurep 'dape)
      (debug/apply-language-configs)
    (with-eval-after-load 'dape
      (debug/apply-language-configs)))
  name)

(packages/declare 'dape)
(use-package dape
  :ensure nil
  :commands (dape
             dape-breakpoint-toggle
             dape-breakpoint-remove-all
             dape-breakpoint-load
             dape-breakpoint-save)
  :custom
  ;; Keep downloaded adapters and breakpoint state in the shared cache.
  (dape-adapter-dir (cache/folder "debug-adapters"))
  (dape-default-breakpoints-file (cache/file "dape-breakpoints"))
  ;; A side window keeps source buffers focused while debugging.
  (dape-buffer-window-arrangement 'right)
  :config
  (debug/apply-language-configs))

;;; debug.el ends here
