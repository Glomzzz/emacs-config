;;; reading.el --- EPUB reading support -*- lexical-binding: t; -*-

(require 'packages)

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
                       ("?" . describe-mode)))
      (define-key map (kbd (car binding)) (cdr binding)))))

(use-package visual-fill-column
  :ensure nil
  :commands (visual-fill-column-mode))

;;; reading.el ends here
