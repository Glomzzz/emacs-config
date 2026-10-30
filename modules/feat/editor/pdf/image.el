;;; image.el --- Highlights painted into Reader's page images -*- lexical-binding: t; -*-

;; Emacs Reader shows each page as a P6 PPM in its overlay's display
;; property.  Highlights are painted into a copy of those bytes, so Reader
;; keeps rendering the page and only the image spec changes.  Reader replaces
;; the display property when it redraws, so the base image is re-read from
;; the overlay each time.

(require 'cl-lib)
(require 'pdf-text)

(declare-function reader-current-doc-overlay "ext:reader" (&optional window))
(declare-function reader-current-doc-pagenumber "ext:reader" (&optional window))
(declare-function pdf/select-groups "select" (page))
(declare-function pdf/search-groups "search" (page))

(defvar-local pdf--rotation 0
  "Quarter turns clockwise that Reader shows the page at, from 0 to 3.")

(defun pdf--ppm-data-start (data)
  "Return the offset of the pixel bytes of the P6 string DATA, or nil."
  (and (stringp data)
       (string-match
        "\\`P6[[:space:]]+[0-9]+[[:space:]]+[0-9]+[[:space:]]+255[[:space:]]"
        data)
       (match-end 0)))

(defun pdf--display-size (width height angle)
  "Return (WIDTH . HEIGHT) of a page with WIDTH and HEIGHT turned ANGLE times."
  (if (memq angle '(1 3))
      (cons height width)
    (cons width height)))

(defun pdf--to-display (x y angle width height)
  "Return the display point of page point X, Y turned ANGLE quarter turns."
  (pcase angle
    (1 (cons (- height y) x))
    (2 (cons (- width x) (- height y)))
    (3 (cons y (- width x)))
    (_ (cons x y))))

(defun pdf--from-display (x y angle width height)
  "Return the page point of display point X, Y; inverse of `pdf--to-display'."
  (pcase angle
    (1 (cons y (- height x)))
    (2 (cons (- width x) (- height y)))
    (3 (cons (- width y) x))
    (_ (cons x y))))

(defun pdf--pixel-scales (angle width height image-width image-height)
  "Return (SX . SY) converting display points to pixels of the image."
  (let ((display (pdf--display-size width height angle)))
    (cons (/ (float image-width) (car display))
          (/ (float image-height) (cdr display)))))

(defun pdf-rect-to-pixels (rect angle width height image-width image-height)
  "Convert RECT (X0 Y0 X1 Y1) in page points to a pixel rect of the image."
  (pcase-let* ((`(,x0 ,y0 ,x1 ,y1) rect)
               (`(,sx . ,sy)
                (pdf--pixel-scales angle width height image-width image-height))
               (corners (mapcar (lambda (p)
                                  (pdf--to-display (car p) (cdr p) angle
                                                   width height))
                                (list (cons x0 y0) (cons x1 y0)
                                      (cons x0 y1) (cons x1 y1))))
               (xs (mapcar (lambda (c) (* sx (car c))) corners))
               (ys (mapcar (lambda (c) (* sy (cdr c))) corners)))
    (list (floor (apply #'min xs)) (floor (apply #'min ys))
          (ceiling (apply #'max xs)) (ceiling (apply #'max ys)))))

(defun pdf-pixel-to-page (px py angle width height image-width image-height)
  "Return the page point (X . Y) under image pixel PX, PY."
  (pcase-let ((`(,sx . ,sy)
               (pdf--pixel-scales angle width height image-width image-height)))
    (pdf--from-display (/ px sx) (/ py sy) angle width height)))

(defun pdf--channel-table (value alpha)
  "Return a 256-entry table blending channel VALUE over bytes at ALPHA."
  (let ((table (make-vector 256 0)))
    (dotimes (i 256)
      (aset table i (/ (+ (* i (- 255 alpha)) (* value alpha) 127) 255)))
    table))

(defun pdf--color-rgb (color)
  "Return the (RED GREEN BLUE) bytes of COLOR, a #RRGGBB string.
Other colour names go through `color-values', which needs a frame."
  (if (string-match "\\`#\\([[:xdigit:]]\\{2\\}\\)\\([[:xdigit:]]\\{2\\}\\)\\([[:xdigit:]]\\{2\\}\\)\\'" color)
      (mapcar (lambda (n) (string-to-number (match-string n color) 16)) '(1 2 3))
    (mapcar (lambda (v) (/ v 257)) (color-values color))))

(defun pdf--paint (data offset width height rects color alpha)
  "Blend COLOR at ALPHA over the pixel RECTS of the P6 bytes DATA, in place.
The pixel data starts at OFFSET; WIDTH and HEIGHT give the image size."
  (pcase-let ((`(,red ,green ,blue)
               (mapcar (lambda (v) (pdf--channel-table v alpha))
                       (pdf--color-rgb color))))
    (dolist (rect rects)
      (pcase-let* ((`(,rx0 ,ry0 ,rx1 ,ry1) rect)
                   (x0 (max 0 rx0))
                   (y0 (max 0 ry0))
                   (x1 (min width rx1))
                   (y1 (min height ry1)))
        (when (and (< x0 x1) (< y0 y1))
          (cl-loop for y from y0 below y1 do
                   (let ((i (+ offset (* 3 (+ x0 (* y width))))))
                     (cl-loop repeat (- x1 x0) do
                              (aset data i (aref red (aref data i)))
                              (aset data (+ i 1)
                                    (aref green (aref data (+ i 1))))
                              (aset data (+ i 2)
                                    (aref blue (aref data (+ i 2))))
                              (cl-incf i 3)))))))))

(defun pdf--composite (base groups)
  "Return a copy of the image spec BASE with GROUPS painted into it.
Each group is (RECTS COLOR ALPHA), where RECTS are pixel rects."
  (let* ((plist (copy-sequence (cdr base)))
         (data (copy-sequence (plist-get plist :data)))
         (offset (pdf--ppm-data-start data)))
    (when offset
      (dolist (group groups)
        (pdf--paint data offset (plist-get plist :width) (plist-get plist :height)
                    (nth 0 group) (nth 1 group) (nth 2 group))))
    (cons 'image (plist-put plist :data data))))

(defun pdf--page-groups (buffer page)
  "Return the highlight groups of PAGE in BUFFER, with rects in page points."
  (with-current-buffer buffer
    (append (pdf/select-groups page) (pdf/search-groups page))))

(defun pdf--refresh-window (window buffer)
  "Repaint the highlights of WINDOW's page of BUFFER into its overlay."
  (let ((overlay (reader-current-doc-overlay window)))
    (when (and (overlayp overlay) (eq (overlay-buffer overlay) buffer))
      (let* ((page (reader-current-doc-pagenumber window))
             (current (overlay-get overlay 'display))
             (composite (overlay-get overlay 'pdf-composite))
             (base (if (and composite (eq current composite))
                       (overlay-get overlay 'pdf-base)
                     current))
             (groups (pdf--page-groups buffer page)))
        (cond
         ((null groups)
          (when composite
            (overlay-put overlay 'display base)
            (overlay-put overlay 'pdf-composite nil)
            (overlay-put overlay 'pdf-base nil)
            (overlay-put overlay 'pdf-key nil)
            (image-flush composite)))
         (t
          (let* ((layer (pdf/text-page (buffer-local-value 'buffer-file-name buffer)
                                       page))
                 (angle (buffer-local-value 'pdf--rotation buffer))
                 (iw (plist-get (cdr base) :width))
                 (ih (plist-get (cdr base) :height))
                 (key (list page angle iw ih groups)))
            (unless (and composite (eq current composite)
                         (equal key (overlay-get overlay 'pdf-key)))
              (let* ((pixel-groups
                      (mapcar (lambda (group)
                                (list (mapcar (lambda (rect)
                                                (pdf-rect-to-pixels
                                                 rect angle
                                                 (pdf-text-width layer)
                                                 (pdf-text-height layer)
                                                 iw ih))
                                              (nth 0 group))
                                      (nth 1 group) (nth 2 group)))
                              groups))
                     (new (pdf--composite base pixel-groups))
                     (old-base (overlay-get overlay 'pdf-base)))
                (overlay-put overlay 'display new)
                (overlay-put overlay 'pdf-base base)
                (overlay-put overlay 'pdf-composite new)
                (overlay-put overlay 'pdf-key key)
                (when (and composite (not (eq composite new)))
                  (image-flush composite))
                (when (and old-base (not (eq old-base base)))
                  (image-flush old-base)))))))))))

(defun pdf/image-refresh (&optional buffer)
  "Repaint BUFFER's highlights into each window that shows it."
  (let ((buffer (or buffer (current-buffer))))
    (when (and (buffer-live-p buffer)
               (eq (buffer-local-value 'major-mode buffer) 'reader-mode))
      (dolist (window (get-buffer-window-list buffer nil t))
        (pdf--refresh-window window buffer)))))

(defun pdf--turn (delta)
  "Turn the current page's rotation by DELTA quarter turns and repaint."
  (when (derived-mode-p 'reader-mode)
    (setq pdf--rotation (mod (+ pdf--rotation delta) 4))))

(provide 'pdf-image)
;;; image.el ends here
