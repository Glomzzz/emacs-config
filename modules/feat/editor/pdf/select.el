;;; select.el --- Text selection on Emacs Reader pages -*- lexical-binding: t; -*-

;; Mouse and keyboard selection over a page's characters.  The selection is
;; painted by `pdf-image' and copied from the text layer of `pdf-text'.

(require 'cl-lib)
(require 'pdf-text)
(require 'pdf-image)

(declare-function reader-current-doc-pagenumber "ext:reader" (&optional window))
(declare-function reader-current-doc-overlay "ext:reader" (&optional window))

(defcustom pdf/select-color "#ffe066"
  "Colour of selected PDF text."
  :type 'color
  :group 'pdf)

(defcustom pdf/select-alpha 110
  "Opacity, from 0 to 255, of the selection highlight."
  :type 'natnum
  :group 'pdf)

(defvar-local pdf--selection nil
  "Selection as (PAGE ANCHOR POINT), with character indexes on PAGE.")

(defvar-local pdf--cursor nil
  "Keyboard cursor as (PAGE . INDEX), used when there is no selection.")

(defun pdf--char-class (string)
  "Return the word class of the character STRING."
  (cond ((string-match-p "\\`[[:space:]]" string) 'space)
        ((pdf/text-cjk-p string) 'cjk)
        ((string-match-p "\\`[[:alnum:]]" string) 'word)
        (t 'punct)))

(defun pdf--nearest-index (layer x y)
  "Return the index of the character of LAYER whose centre is nearest X, Y."
  (let ((chars (pdf-text-chars layer))
        (best 0)
        (best-distance 1.0e30))
    (dotimes (k (length chars))
      (let* ((c (aref chars k))
             (dx (- (/ (+ (aref c 1) (aref c 3)) 2.0) x))
             (dy (- (/ (+ (aref c 2) (aref c 4)) 2.0) y))
             (distance (+ (* dx dx) (* dy dy))))
        (when (< distance best-distance)
          (setq best k
                best-distance distance))))
    best))

(defun pdf--hit (posn)
  "Return (BUFFER PAGE . INDEX) for POSN on a page image, or nil."
  (let ((window (posn-window posn))
        (xy (posn-object-x-y posn))
        (image (posn-object posn)))
    (when (and (windowp window) (consp xy) (consp image)
               (eq (car image) 'image))
      (with-current-buffer (window-buffer window)
        (when (and (derived-mode-p 'reader-mode)
                   (reader-current-doc-overlay window))
          (let* ((page (reader-current-doc-pagenumber window))
                 (layer (pdf/text-page buffer-file-name page)))
            (when (> (length (pdf-text-chars layer)) 0)
              (let ((point (pdf-pixel-to-page
                            (car xy) (cdr xy) pdf--rotation
                            (pdf-text-width layer) (pdf-text-height layer)
                            (plist-get (cdr image) :width)
                            (plist-get (cdr image) :height))))
                (cons (current-buffer)
                      (cons page
                            (pdf--nearest-index layer (car point)
                                                (cdr point))))))))))))

(defun pdf--select-set (buffer page anchor point)
  "Select characters ANCHOR to POINT on PAGE of BUFFER and repaint it."
  (with-current-buffer buffer
    (setq pdf--selection (list page anchor point)
          pdf--cursor (cons page point))
    (pdf/image-refresh buffer)))

(defun pdf/select-clear ()
  "Clear the text selection of the current PDF buffer."
  (interactive)
  (when pdf--selection
    (setq pdf--selection nil)
    (pdf/image-refresh (current-buffer))))

(defun pdf/select-page-changed (page)
  "Drop the selection unless it lies on PAGE."
  (when (and pdf--selection (/= (car pdf--selection) page))
    (setq pdf--selection nil)))

(defun pdf/select-groups (page)
  "Return the selection highlight group on PAGE, with rects in page points."
  (when (and pdf--selection (= (car pdf--selection) page))
    (let* ((layer (pdf/text-page buffer-file-name page))
           (anchor (nth 1 pdf--selection))
           (point (nth 2 pdf--selection)))
      (list (list (pdf/text-boxes layer (min anchor point) (max anchor point))
                  pdf/select-color pdf/select-alpha)))))

(defun pdf--word-range (chars index)
  "Return (START . END) of the word around INDEX in CHARS."
  (let* ((line (aref (aref chars index) 5))
         (class (pdf--char-class (aref (aref chars index) 0)))
         (start index)
         (end index))
    (unless (eq class 'cjk)
      (cl-flet ((same-p (k)
                  (and (<= 0 k) (< k (length chars))
                       (= (aref (aref chars k) 5) line)
                       (eq (pdf--char-class (aref (aref chars k) 0)) class))))
        (while (same-p (1- start)) (cl-decf start))
        (while (same-p (1+ end)) (cl-incf end))))
    (cons start end)))

(defun pdf--line-range (chars index)
  "Return (START . END) of the line around INDEX in CHARS."
  (let* ((line (aref (aref chars index) 5))
         (start index)
         (end index))
    (while (and (> start 0) (= (aref (aref chars (1- start)) 5) line))
      (cl-decf start))
    (while (and (< (1+ end) (length chars))
                (= (aref (aref chars (1+ end)) 5) line))
      (cl-incf end))
    (cons start end)))

(defun pdf--select-range-at (posn range-function)
  "Select the RANGE-FUNCTION range around the character at POSN."
  (when-let* ((hit (pdf--hit posn)))
    (pcase-let ((`(,buffer ,page . ,index) hit))
      (with-current-buffer buffer
        (let* ((layer (pdf/text-page buffer-file-name page))
               (range (funcall range-function (pdf-text-chars layer) index)))
          (pdf--select-set buffer page (car range) (cdr range)))))))

(defun pdf/select-mouse-start (event)
  "Start a text selection where the mouse button went down on a page."
  (interactive "e")
  (when-let* ((hit (pdf--hit (event-start event))))
    (pcase-let ((`(,buffer ,page . ,index) hit))
      (pdf--select-set buffer page index index))))

(defun pdf/select-mouse-extend (event)
  "Extend the selection to the character under the dragged mouse."
  (interactive "e")
  (when-let* ((hit (pdf--hit (event-end event))))
    (pcase-let ((`(,buffer ,page . ,index) hit))
      (with-current-buffer buffer
        (when (and pdf--selection (= page (nth 0 pdf--selection)))
          (setf (nth 2 pdf--selection) index)
          (setq pdf--cursor (cons page index))
          (pdf/image-refresh buffer))))))

(defun pdf/select-mouse-end (event)
  "Finish a drag; a plain click leaves no selection."
  (interactive "e")
  (when (and pdf--selection
             (= (nth 1 pdf--selection) (nth 2 pdf--selection)))
    (pdf/select-clear))
  (ignore event))

(defun pdf/select-word (event)
  "Select the word under the mouse at EVENT."
  (interactive "e")
  (pdf--select-range-at (event-start event) #'pdf--word-range))

(defun pdf/select-line (event)
  "Select the line under the mouse at EVENT."
  (interactive "e")
  (pdf--select-range-at (event-start event) #'pdf--line-range))

(defun pdf/select-copy ()
  "Copy the selected text to the kill ring and clear the selection."
  (interactive)
  (unless pdf--selection
    (user-error "No PDF text selected"))
  (let* ((page (nth 0 pdf--selection))
         (anchor (nth 1 pdf--selection))
         (point (nth 2 pdf--selection))
         (layer (pdf/text-page buffer-file-name page))
         (text (pdf/text-range layer (min anchor point) (max anchor point))))
    (kill-new text)
    (pdf/select-clear)
    (message "Copied %d characters" (length text))))

(defun pdf--cursor-index (page)
  "Return the keyboard index on PAGE: the selection point, cursor, or 0."
  (cond ((and pdf--selection (= (nth 0 pdf--selection) page))
         (nth 2 pdf--selection))
        ((and pdf--cursor (= (car pdf--cursor) page))
         (cdr pdf--cursor))
        (t 0)))

(defun pdf/select-start ()
  "Start a selection at the keyboard cursor."
  (interactive)
  (let* ((page (reader-current-doc-pagenumber))
         (index (pdf--cursor-index page)))
    (pdf--select-set (current-buffer) page index index)))

(defun pdf--move (step)
  "Move the keyboard cursor, and any selection's point, using STEP.
STEP receives the characters of the page and the current index."
  (let* ((page (reader-current-doc-pagenumber))
         (layer (pdf/text-page buffer-file-name page))
         (chars (pdf-text-chars layer)))
    (if (zerop (length chars))
        (message "No text on this PDF page")
      (let ((new (funcall step chars (pdf--cursor-index page))))
        (setq pdf--cursor (cons page new))
        (when (and pdf--selection (= (nth 0 pdf--selection) page))
          (setf (nth 2 pdf--selection) new))
        (pdf/image-refresh (current-buffer))))))

(defun pdf--next-line-index (chars index)
  "Return the index of the first character of the line after INDEX."
  (let ((line (aref (aref chars index) 5))
        (k index))
    (while (and (< k (1- (length chars)))
                (= (aref (aref chars k) 5) line))
      (cl-incf k))
    k))

(defun pdf--previous-line-index (chars index)
  "Return the index of the first character of the line before INDEX."
  (let ((line (aref (aref chars index) 5))
        (k index))
    (while (and (> k 0) (= (aref (aref chars k) 5) line))
      (cl-decf k))
    (if (= k index)
        index
      (car (pdf--line-range chars k)))))

(defun pdf/select-forward-word ()
  "Move the keyboard cursor, or the selection's point, to the next word."
  (interactive)
  (pdf--move (lambda (chars index)
               (min (1- (length chars))
                    (1+ (cdr (pdf--word-range chars index)))))))

(defun pdf/select-backward-word ()
  "Move the keyboard cursor, or the selection's point, to the previous word."
  (interactive)
  (pdf--move (lambda (chars index)
               (let ((start (car (pdf--word-range chars index))))
                 (car (pdf--word-range chars (max 0 (1- start))))))))

(defun pdf/select-next-line ()
  "Move the keyboard cursor, or the selection's point, to the next line."
  (interactive)
  (pdf--move #'pdf--next-line-index))

(defun pdf/select-previous-line ()
  "Move the keyboard cursor, or the selection's point, to the previous line."
  (interactive)
  (pdf--move #'pdf--previous-line-index))

(provide 'pdf-select)
;;; select.el ends here
