;;; reading.el --- EPUB reading support -*- lexical-binding: t; -*-

(require 'packages)

;; `nov-mode' renders book text through the `variable-pitch' face.  Choosing
;; a family that covers Latin and Han alike keeps both scripts at the frame
;; font size; relying on the fontset fallback would render the Han part at
;; whatever size that fontset entry specifies.  LXGW WenKai is the Han font
;; configured in `modules/ui/appearance.el' and installed by the Home
;; Manager Emacs module.
(defvar reading/nov-body-family "LXGW WenKai"
  "Proportional family used for EPUB body text.")

(defun reading/setup-nov ()
  "Tune the current EPUB buffer for comfortable bilingual reading."
  ;; More leading than the editing default keeps dense Han text readable.
  (setq-local line-spacing 0.25)
  (face-remap-add-relative 'variable-pitch :family reading/nov-body-family)
  ;; `nov-text-width' is t so nov leaves the text unfilled; visual line mode
  ;; wraps it and visual-fill-column centers a book-like measure that reflows
  ;; when the window changes size.
  (visual-line-mode 1)
  (visual-fill-column-mode 1))

(packages/declare 'nov 'visual-fill-column)

(use-package nov
  :ensure nil
  :mode ("\\.epub\\'" . nov-mode)
  :custom
  ;; Body text uses `variable-pitch'; fixed-width markup uses `fixed-pitch'.
  (nov-variable-pitch t)
  (nov-text-width t)
  ;; Keep reading positions under the cache root rather than in the repository.
  (nov-save-place-file (cache/file "nov-places"))
  :hook (nov-mode . reading/setup-nov))

(use-package visual-fill-column
  :ensure nil
  :commands (visual-fill-column-mode)
  :custom
  ;; 80 columns is a comfortable Latin line and about 40 Han characters, which
  ;; matches the measure of printed Chinese books.
  (visual-fill-column-width 80)
  (visual-fill-column-center-text t))

;;; reading.el ends here
