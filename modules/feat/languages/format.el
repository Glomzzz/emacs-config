;;; format.el --- External formatter integration -*- lexical-binding: t; -*-

(require 'packages)

(declare-function eglot-managed-p "eglot" ())
(declare-function eglot-server-capable "eglot" (&rest feats))

(defvar-local format/apheleia-owns nil
  "When non-nil, Apheleia owns manual and save-time formatting here.
Language modules set this when the Eglot server's formatting request is
synchronous and can block Emacs, for example while the server loads a
project cradle.")

(defun format/eglot-owns-p (&optional region)
  "Return non-nil when Eglot can own formatting in the current buffer.
When REGION is non-nil, require range-formatting support instead of
whole-buffer formatting.  Respect the language's Apheleia preference
and any capabilities explicitly ignored in Eglot."
  (and (not format/apheleia-owns)
       (fboundp 'eglot-managed-p)
       (eglot-managed-p)
       (fboundp 'eglot-server-capable)
       (eglot-server-capable (if region
                                 :documentRangeFormattingProvider
                               :documentFormattingProvider))))

(defun format/inhibit-eglot ()
  "Return non-nil when Eglot owns save-time formatting here."
  (format/eglot-owns-p))

(defun format/mode-maybe ()
  "Enable Apheleia unless Eglot owns whole-buffer formatting."
  (unless (format/inhibit-eglot)
    (require 'apheleia)
    (apheleia-mode 1)))

(defun format/arm-on-save ()
  "Let the first save decide whether Apheleia formats this buffer.
Eglot usually takes over shortly after a buffer opens, so checking at open
time loaded Apheleia into buffers that Eglot then formats.  Enabling Apheleia
from `before-save-hook' still formats the save that triggered it."
  (add-hook 'before-save-hook #'format/mode-maybe nil t))

(packages/declare 'apheleia)
(use-package apheleia
  :ensure nil
  :hook (prog-mode . format/arm-on-save)
  :config
  (add-hook 'apheleia-inhibit-functions #'format/inhibit-eglot)
  (add-hook 'apheleia-skip-functions #'format/inhibit-eglot))

;;; format.el ends here
