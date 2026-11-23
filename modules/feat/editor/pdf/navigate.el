;;; navigate.el --- PDF page history and remembered fit -*- lexical-binding: t; -*-

;; History moves back and forward through the pages a PDF buffer showed.  The
;; fit (height or width) that was chosen last is saved per file, so reopening
;; the PDF applies it again.  Zoom values are restored by Reader's own
;; bookmark, which records the scale.

(require 'cl-lib)
(require 'seq)
(require 'pdf-select)
(require 'pdf-search)

(declare-function emureader-current-doc-pagenumber "ext:emureader" (&optional window))
(declare-function emureader-goto-page "ext:emureader" (n))
(declare-function emureader-fit-to-height "ext:emureader" ())
(declare-function emureader-fit-to-width "ext:emureader" ())
(declare-function emureader-enlarge-size "ext:emureader" (&optional scaling-factor))
(declare-function emureader-shrink-size "ext:emureader" (&optional scaling-factor))
(declare-function emureader-reset-size "ext:emureader" ())

(defvar-local pdf--page nil
  "The page this buffer last showed, for the history.")

(defvar-local pdf--back nil
  "Pages `pdf/history-back' returns to, most recent first.")

(defvar-local pdf--forward nil
  "Pages `pdf/history-forward' returns to, most recent first.")

(defvar-local pdf--fit nil
  "The fit last chosen with H or W: `height', `width', or nil.")

(defconst pdf--history-limit 100
  "Number of pages kept in the back history.")

(defun pdf/navigate-note-page ()
  "Record a page change made by a Reader command in the history."
  (when (derived-mode-p 'emureader-mode)
    (let ((page (emureader-current-doc-pagenumber)))
      (cond ((null pdf--page)
             (setq pdf--page page))
            ((eql page pdf--page))
            (t
             (push pdf--page pdf--back)
             (setq pdf--back (seq-take pdf--back pdf--history-limit)
                   pdf--forward nil
                   pdf--page page)
             (pdf/select-page-changed page))))))

(defun pdf--history-goto (page)
  "Show PAGE as the current page, keeping the history bookkeeping in step."
  (emureader-goto-page page)
  (setq pdf--page page)
  (pdf/select-page-changed page)
  (pdf/image-refresh (current-buffer)))

(defun pdf/history-back ()
  "Return to the page this PDF showed before the current one."
  (interactive)
  (if (null pdf--back)
      (message "No earlier PDF page")
    (push (emureader-current-doc-pagenumber) pdf--forward)
    (pdf--history-goto (pop pdf--back))))

(defun pdf/history-forward ()
  "Go forward again after `pdf/history-back'."
  (interactive)
  (if (null pdf--forward)
      (message "No later PDF page")
    (push (emureader-current-doc-pagenumber) pdf--back)
    (pdf--history-goto (pop pdf--forward))))

(defun pdf--views-file ()
  "Return the file that remembers each PDF's fit."
  (cache/file "pdf/views.eld"))

(defun pdf--views-read ()
  "Return the saved fits as an alist of (FILE . FIT)."
  (let ((file (pdf--views-file)))
    (when (file-readable-p file)
      (with-temp-buffer
        (insert-file-contents file)
        (ignore-errors (read (current-buffer)))))))

(defun pdf--views-write (alist)
  "Save ALIST of (FILE . FIT) as the remembered fits."
  (with-temp-file (pdf--views-file)
    (prin1 alist (current-buffer))))

(defun pdf--fit-save ()
  "Remember this PDF's fit, or forget it when the last zoom was manual."
  (when buffer-file-name
    (let* ((key (file-truename buffer-file-name))
           (alist (assoc-delete-all key (pdf--views-read))))
      (pdf--views-write (if pdf--fit
                            (cons (cons key pdf--fit) alist)
                          alist)))))

(defun pdf--fit-restore ()
  "Apply the fit remembered for this PDF, if there is one."
  (let ((fit (cdr (assoc (file-truename buffer-file-name) (pdf--views-read)))))
    (setq pdf--fit fit)
    (pcase fit
      ('height (emureader-fit-to-height))
      ('width (emureader-fit-to-width)))))

(defun pdf/fit-height ()
  "Fit the page to the window height, and remember that fit."
  (interactive)
  (emureader-fit-to-height)
  (setq pdf--fit 'height))

(defun pdf/fit-width ()
  "Fit the page to the window width, and remember that fit."
  (interactive)
  (emureader-fit-to-width)
  (setq pdf--fit 'width))

(defun pdf/zoom-in ()
  "Enlarge the page; a manual zoom replaces the remembered fit."
  (interactive)
  (call-interactively #'emureader-enlarge-size)
  (setq pdf--fit nil))

(defun pdf/zoom-out ()
  "Shrink the page; a manual zoom replaces the remembered fit."
  (interactive)
  (call-interactively #'emureader-shrink-size)
  (setq pdf--fit nil))

(defun pdf/zoom-reset ()
  "Reset the page to its natural size; a manual zoom replaces the fit."
  (interactive)
  (call-interactively #'emureader-reset-size)
  (setq pdf--fit nil))

(defun pdf/clear ()
  "Clear the PDF selection and search highlights, or quit as usual."
  (interactive)
  (if (or pdf--selection pdf--query)
      (progn
        (pdf/select-clear)
        (pdf/search-clear))
    (keyboard-quit)))

(provide 'pdf-navigate)
;;; navigate.el ends here
