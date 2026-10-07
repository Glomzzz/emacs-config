;;; funcs.el --- Custom functions  -*- lexical-binding: t; -*-

(declare-function eglot-format "eglot" (&optional beg end))
(declare-function format/eglot-owns-p "format" (&optional region))

(defun funcs/duplicate-line ()
  "Duplicate the current line and preserve the cursor column."
  (interactive)
  (let ((column (- (point) (line-beginning-position)))
        (line (buffer-substring
               (line-beginning-position)
               (line-end-position))))
    (end-of-line)
    (newline)
    (insert line)
    (beginning-of-line)
    (forward-char column)))

(defun funcs/mark-whole-line ()
  "Mark the entire current line."
  (interactive)
  (beginning-of-line)
  (set-mark (line-end-position))
  (activate-mark))

(defun funcs/open-line-below ()
  "Open a new line below the current line and move to it."
  (interactive)
  (end-of-line)
  (newline))

(defun funcs/open-line-above ()
  "Open a new line above the current line and move to it."
  (interactive)
  (beginning-of-line)
  (newline)
  (forward-line -1))

(defun funcs/format-buffer ()
  "Format with the language's preferred and supported formatter.
Eglot formats an active region when supported, otherwise the whole
buffer.  Use Apheleia when preferred or Eglot cannot format the buffer."
  (interactive)
  (cond
   ((and (fboundp 'format/eglot-owns-p)
         (format/eglot-owns-p (region-active-p)))
    (call-interactively #'eglot-format))
   ((and (fboundp 'format/eglot-owns-p)
         (format/eglot-owns-p))
    ;; A server may support whole-buffer formatting but not range formatting.
    ;; Do not call Apheleia here: it correctly skips Eglot-owned buffers.
    (eglot-format))
   ((or (fboundp 'apheleia-format-buffer)
        (require 'apheleia nil t))
    (call-interactively #'apheleia-format-buffer))
   (t
    (user-error "No formatter is available for this buffer"))))

;;; funcs.el ends here
