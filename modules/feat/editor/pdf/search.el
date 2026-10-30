;;; search.el --- Search PDF text with on-page highlights -*- lexical-binding: t; -*-

;; Matches come from the text layer of `pdf-text'.  Jumping to a match turns
;; to its page with `reader-goto-page'; every match on the page is highlighted,
;; and the current one is highlighted more strongly.

(require 'cl-lib)
(require 'seq)
(require 'pdf-text)
(require 'pdf-image)

(declare-function reader-current-doc-pagenumber "ext:reader" (&optional window))
(declare-function reader-goto-page "ext:reader" (n))
(defvar reader-current-doc-pagecount)

(defcustom pdf/search-color "#ffcc80"
  "Colour of the other matches on a PDF page."
  :type 'color
  :group 'pdf)

(defcustom pdf/search-alpha 90
  "Opacity, from 0 to 255, of the other PDF matches."
  :type 'natnum
  :group 'pdf)

(defcustom pdf/search-current-color "#ff8a65"
  "Colour of the current PDF match."
  :type 'color
  :group 'pdf)

(defcustom pdf/search-current-alpha 150
  "Opacity, from 0 to 255, of the current PDF match."
  :type 'natnum
  :group 'pdf)

(defvar-local pdf--query nil
  "The current PDF search string, or nil.")

(defvar-local pdf--match nil
  "The current match as (PAGE START END), with character indexes on PAGE.")

(defun pdf--search-find (file count query page after backward)
  "Return (PAGE START . END) for the next match of QUERY in FILE after AFTER.
Search PAGE first, then the following pages, wrapping over COUNT pages.
With BACKWARD, search the other way."
  (cl-loop for offset from 0 to count
           for p = (1+ (mod (+ (1- page) (if backward (- offset) offset)) count))
           for ranges = (pdf/text-search (pdf/text-page file p) query)
           for hit = (cond ((and (= offset 0) backward)
                            (car (last (seq-filter (lambda (r) (< (car r) after))
                                                   ranges))))
                           ((= offset 0)
                            (seq-find (lambda (r) (> (car r) after)) ranges))
                           (backward (car (last ranges)))
                           (t (car ranges)))
           when hit return (cons p hit)))

(defun pdf--search-show (match)
  "Turn to MATCH, a list (PAGE START END), and repaint the highlights."
  (pcase-let ((`(,page ,start ,end) match))
    (unless (eql page (reader-current-doc-pagenumber))
      (reader-goto-page page))
    (setq pdf--match (list page start end))
    (pdf/image-refresh (current-buffer))))

(defun pdf--search-step (backward)
  "Move to the next match of the current query, or the previous one if BACKWARD."
  (unless pdf--query
    (user-error "No PDF search yet; press / to search"))
  (let* ((page (reader-current-doc-pagenumber))
         (after (cond ((and pdf--match (= (nth 0 pdf--match) page))
                       (nth 1 pdf--match))
                      (backward most-positive-fixnum)
                      (t -1)))
         (hit (pdf--search-find buffer-file-name reader-current-doc-pagecount
                                pdf--query page after backward)))
    (if hit
        (pdf--search-show (list (car hit) (cadr hit) (cddr hit)))
      (message "No match for \"%s\"" pdf--query))))

(defun pdf/search-new (query)
  "Search this PDF for QUERY and show the first match from the current page."
  (interactive (list (read-string "Search PDF: " nil nil pdf--query)))
  (when (string-empty-p query)
    (user-error "Empty search"))
  (setq pdf--query query
        pdf--match nil)
  (pdf--search-step nil))

(defun pdf/search-forward ()
  "Show the next match of the PDF search, or ask for a search first."
  (interactive)
  (if pdf--query
      (pdf--search-step nil)
    (call-interactively #'pdf/search-new)))

(defun pdf/search-backward ()
  "Show the previous match of the PDF search, or ask for a search first."
  (interactive)
  (if pdf--query
      (pdf--search-step t)
    (call-interactively #'pdf/search-new)))

(defun pdf/search-clear ()
  "Clear the PDF search and its highlights."
  (interactive)
  (when (or pdf--query pdf--match)
    (setq pdf--query nil
          pdf--match nil)
    (pdf/image-refresh (current-buffer))))

(defun pdf/search-groups (page)
  "Return the search highlight groups on PAGE, with rects in page points."
  (when pdf--query
    (let* ((layer (pdf/text-page buffer-file-name page))
           (current (and pdf--match (= (nth 0 pdf--match) page)
                         (cons (nth 1 pdf--match) (nth 2 pdf--match))))
           (others (seq-remove (lambda (range) (equal range current))
                               (pdf/text-search layer pdf--query))))
      (delq nil
            (list (and others
                       (list (apply #'append
                                    (mapcar (lambda (range)
                                              (pdf/text-boxes layer (car range)
                                                              (cdr range)))
                                            others))
                             pdf/search-color pdf/search-alpha))
                  (and current
                       (list (pdf/text-boxes layer (car current) (cdr current))
                             pdf/search-current-color
                             pdf/search-current-alpha)))))))

(provide 'pdf-search)
;;; search.el ends here
