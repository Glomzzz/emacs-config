;;; text.el --- Character boxes of PDF pages -*- lexical-binding: t; -*-

;; Emacs Reader draws pages as images, so selection and search need the
;; characters and their boxes.  MuPDF's stext output gives both, in page
;; points with y growing downward.  Layers are cached per file version.

(require 'cl-lib)
(require 'dom)

(defgroup pdf nil
  "PDF reading with Emacs Reader in graphical frames."
  :group 'multimedia)

(cl-defstruct (pdf-text (:constructor pdf-text--make) (:copier nil))
  "Text layer of one PDF page.
WIDTH and HEIGHT give the page size in points.  CHARS is a vector of
[STRING X0 Y0 X1 Y1 LINE] vectors in reading order.  STRING is the page
text, with a space at line breaks between Latin words.  INDEX maps each
position of STRING to a character index, and STARTS maps each character
index to its first position in STRING."
  width height chars string index starts)

(defvar pdf--text-cache (make-hash-table :test 'equal)
  "Text layers keyed by (FILE . PAGE), valued (STAMP . LAYER).")

(defconst pdf--text-cache-limit 64
  "Number of text layers kept before the cache is cleared.")

(defun pdf--text-program ()
  "Return the mutool that extracts page text, or nil.
Prefer the copy `pdf/build' rooted, so it matches Reader's MuPDF version."
  (or (let ((rooted (expand-file-name "mupdf-bin/bin/mutool"
                                      (cache/folder "pdf"))))
        (and (file-executable-p rooted) rooted))
      (executable-find "mutool")))

(defun pdf--text-xml (file page)
  "Return the parsed stext document of PAGE (1-based) in FILE."
  (let ((program (or (pdf--text-program)
                     (user-error "mutool not found; run M-x pdf/build"))))
    (with-temp-buffer
      (unless (zerop (call-process program nil (list (current-buffer) nil) nil
                                   "draw" "-F" "stext" "-o" "-"
                                   file (number-to-string page)))
        (user-error "mutool could not read page %d of %s" page file))
      (libxml-parse-xml-region (point-min) (point-max)))))

(defun pdf/text-cjk-p (string)
  "Return non-nil when the first character of STRING is CJK."
  (and (> (length string) 0)
       (memq (aref char-script-table (string-to-char string))
             '(han cjk-misc hiragana katakana hangul))))

(defun pdf--text-box (quad)
  "Return (X0 Y0 X1 Y1) bounding the eight numbers of QUAD."
  (let* ((numbers (mapcar #'string-to-number (split-string quad)))
         (xs (cl-loop for n in numbers for i from 0 when (cl-evenp i) collect n))
         (ys (cl-loop for n in numbers for i from 0 when (cl-oddp i) collect n)))
    (list (apply #'min xs) (apply #'min ys) (apply #'max xs) (apply #'max ys))))

(defun pdf--text-entries (page)
  "Return the character vectors of the stext PAGE node in reading order."
  (let ((line-index -1) entries)
    (dolist (line (dom-by-tag page 'line))
      (cl-incf line-index)
      (dolist (char (dom-by-tag line 'char))
        (let ((text (dom-attr char 'c))
              (quad (dom-attr char 'quad)))
          (when (and quad text (> (length text) 0))
            (push (apply #'vector text
                         (append (pdf--text-box quad) (list line-index)))
                  entries)))))
    (vconcat (nreverse entries))))

(defun pdf--text-assemble (entries)
  "Return (STRING INDEX STARTS) for the character vectors ENTRIES."
  (let ((parts nil) (index nil) (pos 0) (previous nil)
        (starts (make-vector (length entries) 0)))
    (cl-flet ((emit (string k)
                (push string parts)
                (dotimes (_ (length string)) (push k index))
                (cl-incf pos (length string))))
      (cl-loop for entry across entries for k from 0 do
               (let ((text (aref entry 0)))
                 (when (and previous
                            (/= (aref entry 5) (aref previous 5))
                            (not (pdf/text-cjk-p (aref previous 0)))
                            (not (pdf/text-cjk-p text)))
                   (emit " " k))
                 (aset starts k pos)
                 (emit text k)
                 (setq previous entry))))
    (list (apply #'concat (nreverse parts))
          (vconcat (nreverse index))
          starts)))

(defun pdf--text-build (document)
  "Return the `pdf-text' layer of the stext DOCUMENT."
  (let* ((root (if (symbolp (car document)) document (car document)))
         (page (car (dom-by-tag root 'page)))
         (width (string-to-number (or (dom-attr page 'width) "0")))
         (height (string-to-number (or (dom-attr page 'height) "0")))
         (entries (pdf--text-entries page))
         (assembled (pdf--text-assemble entries)))
    (pdf-text--make :width width :height height :chars entries
                    :string (nth 0 assembled) :index (nth 1 assembled)
                    :starts (nth 2 assembled))))

(defun pdf/text-page (file page)
  "Return the `pdf-text' layer of PAGE (1-based) in FILE, cached per version."
  (let* ((true (file-truename file))
         (key (cons true page))
         (stamp (file-attribute-modification-time (file-attributes true)))
         (cached (gethash key pdf--text-cache)))
    (if (and cached (equal (car cached) stamp))
        (cdr cached)
      (when (>= (hash-table-count pdf--text-cache) pdf--text-cache-limit)
        (clrhash pdf--text-cache))
      (let ((layer (pdf--text-build (pdf--text-xml true page))))
        (puthash key (cons stamp layer) pdf--text-cache)
        layer))))

(defun pdf/text-search (layer query)
  "Return (START . END) character-index ranges where QUERY occurs in LAYER.
Matching ignores case unless QUERY contains an uppercase letter."
  (when (and layer (> (length query) 0))
    (let ((case-fold-search (let ((case-fold-search nil))
                              (not (string-match-p "[[:upper:]]" query))))
          (text (pdf-text-string layer))
          (index (pdf-text-index layer))
          (pos 0)
          ranges)
      (while (and (< pos (length text))
                  (string-match (regexp-quote query) text pos))
        (let ((begin (match-beginning 0))
              (end (match-end 0)))
          (push (cons (aref index begin) (aref index (1- end))) ranges)
          (setq pos end)))
      (nreverse ranges))))

(defun pdf/text-range (layer start end)
  "Return the text of LAYER from character index START through END."
  (let* ((chars (pdf-text-chars layer))
         (from (aref (pdf-text-starts layer) start))
         (to (+ (aref (pdf-text-starts layer) end)
                (length (aref (aref chars end) 0)))))
    (substring (pdf-text-string layer) from to)))

(defun pdf/text-boxes (layer start end)
  "Return the boxes (X0 Y0 X1 Y1) covering characters START to END, one per line."
  (let ((chars (pdf-text-chars layer))
        boxes line box)
    (cl-loop for k from start to end do
             (let* ((c (aref chars k))
                    (current (aref c 5))
                    (b (list (aref c 1) (aref c 2) (aref c 3) (aref c 4))))
               (if (and box (eql current line))
                   (setq box (list (min (nth 0 box) (nth 0 b))
                                   (min (nth 1 box) (nth 1 b))
                                   (max (nth 2 box) (nth 2 b))
                                   (max (nth 3 box) (nth 3 b))))
                 (when box (push box boxes))
                 (setq line current
                       box b))))
    (when box (push box boxes))
    (nreverse boxes)))

(provide 'pdf-text)
;;; text.el ends here
