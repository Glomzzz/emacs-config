;;; reading.el --- EPUB reading support -*- lexical-binding: t; -*-

(require 'packages)
(require 'cl-lib)
(require 'dom)
(require 'seq)

(defgroup reading nil
  "Comfortable EPUB reading in terminal and graphical frames."
  :group 'multimedia)

(defcustom reading/nov-body-family "LXGW WenKai"
  "Proportional EPUB body font in graphical frames.
Terminal fonts and their size are controlled by the terminal instead."
  :type 'string
  :group 'reading)

(defcustom reading/nov-text-width 80
  "Default EPUB reading width in columns (about 40 full-width Han glyphs).
Narrower windows use their available width.  Use `reading/set-width' to
change the measure for an individual book without refilling its text."
  :type 'integer
  :group 'reading)

(defvar-local reading--nov-body-remap nil
  "Face remapping cookie for the current EPUB's graphical body font.")

(defvar shr-use-colors)
(defvar visual-fill-column-width)
(defvar nov-documents)
(defvar nov-documents-index)
(declare-function face-remap-add-relative "face-remap")
(declare-function face-remap-remove-relative "face-remap")
(declare-function nov-render-html "nov")
(declare-function nov-imenu-create-index "nov")
(declare-function nov-visit-relative-file "nov")
(declare-function visual-fill-column-adjust "visual-fill-column")
(declare-function visual-fill-column-mode "visual-fill-column")

(defun reading/render-html ()
  "Render a book using the active theme rather than publisher colors.
This wrapper runs on the initial render too, before `nov-mode-hook'."
  (let ((shr-use-colors nil))
    (nov-render-html)))

(defun reading/visit-content (_name filename target)
  "Visit a contents entry's FILENAME and TARGET without losing section state.
Contents links are relative to the TOC, not the currently displayed part.
Nov's Imenu handler temporarily binds the section index to zero, which
restores a stale index after jumping.  Resolve the path instead."
  (let* ((toc (cdr (aref nov-documents 0)))
         (current (cdr (aref nov-documents nov-documents-index)))
         (relative (file-relative-name
                    (if (zerop (length filename))
                        toc
                      (expand-file-name filename (file-name-directory toc)))
                    (file-name-directory current))))
    (nov-visit-relative-file relative target)))

(defun reading/contents-index ()
  "Return Nov's contents index with a state-preserving jump handler."
  (mapcar (lambda (entry)
            (setf (nth 2 entry) #'reading/visit-content)
            entry)
          (nov-imenu-create-index)))

(defun reading/set-width (&optional width)
  "Set this EPUB's reading WIDTH in columns; nil resets to the default.
Interactively, prompt for a width or use the numeric prefix argument."
  (interactive
   (list (if current-prefix-arg
             (prefix-numeric-value current-prefix-arg)
           (read-number "EPUB text width (columns): "
                        visual-fill-column-width))))
  (unless (derived-mode-p 'nov-mode)
    (user-error "This command is for EPUB reading buffers"))
  (setq width (or width reading/nov-text-width))
  (unless (and (integerp width) (>= width 20))
    (user-error "Reading width must be an integer of at least 20 columns"))
  (setq-local visual-fill-column-width width)
  ;; Use the package's public adjustment API in every view of this book.
  ;; Margins reflow the display without changing positions, links, or bookmarks.
  (dolist (window (get-buffer-window-list (current-buffer) nil t))
    (with-selected-window window
      (visual-fill-column-adjust))))

(defun reading/widen (&optional steps)
  "Widen this EPUB's text by four columns per STEPS (default one)."
  (interactive "p")
  (reading/set-width (+ visual-fill-column-width (* 4 (or steps 1)))))

(defun reading/narrow (&optional steps)
  "Narrow this EPUB's text by four columns per STEPS (default one)."
  (interactive "p")
  (reading/widen (- (or steps 1))))

(defun reading/reset-width ()
  "Reset this EPUB's text width to `reading/nov-text-width'."
  (interactive)
  (reading/set-width))

(defun reading/setup-nov ()
  "Give the current EPUB a quiet, reflowing bilingual reading layout."
  (require 'face-remap)
  ;; These settings also work if a book opened in a terminal is later viewed
  ;; by a GUI client.  Fonts and fractional leading have no effect in a TTY.
  (setq-local line-spacing 0.25)
  (when reading--nov-body-remap
    (face-remap-remove-relative reading--nov-body-remap))
  (setq reading--nov-body-remap
        (face-remap-add-relative 'variable-pitch
                                 :family reading/nov-body-family))
  (setq-local visual-fill-column-width reading/nov-text-width
              visual-fill-column-center-text t
              show-trailing-whitespace nil
              scroll-margin 1
              scroll-conservatively 101
              next-screen-context-lines 2
              imenu-create-index-function #'reading/contents-index
              mode-line-format
              '(" EPUB  "
                (:eval (format "Part %d/%d" (1+ nov-documents-index)
                               (length nov-documents)))
                "  %p  |  ? help"))
  (display-line-numbers-mode -1)
  (hl-line-mode -1)
  ;; Keep paragraphs unfilled: resizing or changing the measure must not
  ;; change saved text offsets.  Visual Line also gives screen-line motion.
  (visual-line-mode 1)
  (visual-fill-column-mode 1))

(defcustom reading/han-family "Noto Serif CJK SC"
  "Font family for Chinese text in EPUB body text, in graphical frames.
Latin text keeps `reading/nov-body-family'.  Terminal fonts belong to the
terminal, so nothing changes there."
  :type 'string
  :group 'reading)

(defconst reading--han-regexp
  "[\u3000-\u303f\u3400-\u4dbf\u4e00-\u9fff\uf900-\ufaff\uff00-\uffef]+"
  "Runs of CJK ideographs and CJK punctuation in EPUB text.")

(defun reading/apply-han-font ()
  "Give the CJK runs of the rendered EPUB section the Han font family.
Runs after each render.  Graphical frames only, since a terminal picks its
own fonts."
  (when (display-graphic-p)
    (let ((inhibit-read-only t))
      (save-excursion
        (goto-char (point-min))
        (while (re-search-forward reading--han-regexp nil t)
          (add-face-text-property (match-beginning 0) (match-end 0)
                                  (list :family reading/han-family) t))))))

(defvar nov-file-name)
(declare-function nov-goto-document "nov" (index))

(defvar reading--section-text-cache (make-hash-table :test 'equal)
  "Plain text of EPUB sections, keyed by file, valued (STAMP . TEXT).")

(defun reading--section-text (file)
  "Return the plain text of the XHTML section FILE, cached per file version."
  (let* ((stamp (file-attribute-modification-time (file-attributes file)))
         (cached (gethash file reading--section-text-cache)))
    (if (and cached (equal (car cached) stamp))
        (cdr cached)
      (let ((text (with-temp-buffer
                    (insert-file-contents file)
                    (dom-inner-text (libxml-parse-html-region (point-min)
                                                              (point-max))))))
        (puthash file (cons stamp text) reading--section-text-cache)
        text))))

(defun reading--snippet (text begin end)
  "Return a one-line excerpt of TEXT around the match from BEGIN to END."
  (string-trim
   (replace-regexp-in-string
    "[[:space:]\n]+" " "
    (substring text (max 0 (- begin 30)) (min (length text) (+ end 30))))))

(defun reading--book-matches (query)
  "Return (INDEX . SNIPPET) for each match of QUERY in the EPUB's sections."
  (let ((case-fold-search (let ((case-fold-search nil))
                            (not (string-match-p "[[:upper:]]" query))))
        matches)
    (dotimes (index (length nov-documents))
      (let ((text (reading--section-text (cdr (aref nov-documents index))))
            (pos 0))
        (while (string-match (regexp-quote query) text pos)
          (let ((begin (match-beginning 0))
                (end (match-end 0)))
            (push (cons index (reading--snippet text begin end)) matches)
            (setq pos end)))))
    (nreverse matches)))

(defun reading--goto-match (index query)
  "Show section INDEX and move point to the first occurrence of QUERY in it."
  (nov-goto-document index)
  (goto-char (point-min))
  (when (search-forward query nil t)
    (goto-char (match-beginning 0))))

(defun reading/search-book (query)
  "Search every section of this EPUB for QUERY and show the chosen match."
  (interactive (list (read-string "Search book: ")))
  (unless (derived-mode-p 'nov-mode)
    (user-error "Not an EPUB buffer"))
  (when (string-empty-p query)
    (user-error "Empty search"))
  (let ((matches (reading--book-matches query)))
    (unless matches
      (user-error "No match for \"%s\"" query))
    (let* ((candidates
            (mapcar (lambda (match)
                      (cons (format "%3d  %s" (1+ (car match)) (cdr match))
                            (car match)))
                    matches))
           (choice (completing-read "Match: " candidates nil t)))
      (reading--goto-match (cdr (assoc choice candidates)) query))))

(defface reading-highlight
  '((t :inherit secondary-selection))
  "Face for EPUB text highlighted with `reading/highlight-region'."
  :group 'reading)

(defun reading--highlights-file ()
  "Return the file that keeps the EPUB highlights."
  (cache/file "reading/highlights.eld"))

(defun reading--highlights-read ()
  "Return the saved highlights as an alist of (BOOK . ((INDEX TEXT) ...))."
  (let ((file (reading--highlights-file)))
    (when (file-readable-p file)
      (with-temp-buffer
        (insert-file-contents file)
        (ignore-errors (read (current-buffer)))))))

(defun reading--book-highlights ()
  "Return the highlights of the current EPUB as a list of (INDEX TEXT)."
  (cdr (assoc (file-truename nov-file-name) (reading--highlights-read))))

(defun reading--book-highlights-set (highlights)
  "Save HIGHLIGHTS as the highlights of the current EPUB."
  (let* ((key (file-truename nov-file-name))
         (alist (assoc-delete-all key (reading--highlights-read))))
    (with-temp-file (reading--highlights-file)
      (prin1 (if highlights (cons (cons key highlights) alist) alist)
             (current-buffer)))))

(defun reading--highlight-overlay (beg end text)
  "Mark BEG to END as a highlight of TEXT."
  (let ((overlay (make-overlay beg end nil t nil)))
    (overlay-put overlay 'face 'reading-highlight)
    (overlay-put overlay 'reading-text text)
    overlay))

(defun reading--apply-highlights ()
  "Recreate the saved highlights of the section that was just rendered."
  (when (and (boundp 'nov-file-name) nov-file-name)
    (save-excursion
      (dolist (entry (reading--book-highlights))
        (when (= (car entry) nov-documents-index)
          (goto-char (point-min))
          (when (search-forward (cadr entry) nil t)
            (reading--highlight-overlay (match-beginning 0) (match-end 0)
                                        (cadr entry))))))))

(defun reading/highlight-region (beg end)
  "Highlight the region of this EPUB and remember it with the book."
  (interactive "r")
  (unless (derived-mode-p 'nov-mode)
    (user-error "Not an EPUB buffer"))
  (let ((text (buffer-substring-no-properties beg end)))
    (when (string-blank-p text)
      (user-error "Select some text to highlight"))
    (reading--highlight-overlay beg end text)
    (reading--book-highlights-set
     (delete-dups (cons (list nov-documents-index text)
                        (reading--book-highlights))))
    (deactivate-mark)))

(defun reading/unhighlight ()
  "Remove the highlight at point and forget it."
  (interactive)
  (let* ((overlay (seq-find (lambda (ov) (overlay-get ov 'reading-text))
                            (overlays-at (point))))
         (text (and overlay (overlay-get overlay 'reading-text))))
    (unless overlay
      (user-error "No highlight at point"))
    (delete-overlay overlay)
    (reading--book-highlights-set
     (cl-remove-if (lambda (entry)
                     (and (= (car entry) nov-documents-index)
                          (equal (cadr entry) text)))
                   (reading--book-highlights)))))

(defun reading/highlights ()
  "Show this EPUB's highlights and jump to the chosen one."
  (interactive)
  (let ((entries (reading--book-highlights)))
    (unless entries
      (user-error "No highlights in this book"))
    (let* ((candidates
            (mapcar (lambda (entry)
                      (cons (format "%3d  %s" (1+ (car entry)) (cadr entry))
                            entry))
                    entries))
           (choice (cdr (assoc (completing-read "Highlight: " candidates nil t)
                               candidates))))
      (reading--goto-match (car choice) (cadr choice)))))

(add-hook 'nov-post-html-render-hook #'reading/apply-han-font)
(add-hook 'nov-post-html-render-hook #'reading--apply-highlights)

(packages/declare 'nov 'visual-fill-column)

(use-package nov
  :ensure nil
  :mode ("\\.epub\\'" . nov-mode)
  :custom
  (nov-variable-pitch t)
  (nov-text-width t)
  (nov-render-html-function #'reading/render-html)
  (nov-save-place-file (cache/file "nov-places"))
  :hook (nov-mode . reading/setup-nov)
  :config
  ;; Nov copies its major-mode map into its link map at load time.  Update
  ;; both so navigation and width keys work on linked text as well as prose.
  (dolist (map (list nov-mode-map nov-button-map))
    (dolist (binding '(("j" . next-line)
                       ("k" . previous-line)
                       ("<next>" . nov-scroll-up)
                       ("<prior>" . nov-scroll-down)
                       ("C-v" . nov-scroll-up)
                       ("M-v" . nov-scroll-down)
                       ("i" . consult-imenu)
                       ("w" . reading/set-width)
                       ("+" . reading/widen)
                       ("-" . reading/narrow)
                       ("=" . reading/reset-width)
                       ("?" . describe-mode)
                       ("/" . reading/search-book)
                       ("h" . reading/highlight-region)
                       ("H" . reading/unhighlight)
                       ("L" . reading/highlights)))
      (define-key map (kbd (car binding)) (cdr binding)))))

(use-package visual-fill-column
  :ensure nil
  :commands (visual-fill-column-mode))

;;; reading.el ends here
