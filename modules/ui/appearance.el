;;; appearance.el --- Portable appearance defaults -*- lexical-binding: t; -*-

(require 'seq)

;; Disable Stupid UI
(setq inhibit-startup-message t)
(scroll-bar-mode -1)
(tool-bar-mode -1)
(menu-bar-mode -1)
(tooltip-mode -1)

;; Set the left and right fringe widths to 10 pixels.
(set-fringe-mode 10)

;; Show relative line numbers in ordinary editable buffers.  Global line
;; numbers make every special, remote, and generated buffer pay redisplay cost.
(setq display-line-numbers-type 'relative)

(defun appearance/line-numbers-maybe ()
  "Enable line numbers for local, reasonably-sized editable buffers."
  (when (and (not (file-remote-p default-directory))
             (not (derived-mode-p 'special-mode))
             (buffers/small-p))
    (display-line-numbers-mode 1)))

(add-hook 'prog-mode-hook #'appearance/line-numbers-maybe)
(add-hook 'text-mode-hook #'appearance/line-numbers-maybe)
(add-hook 'conf-mode-hook #'appearance/line-numbers-maybe)

;; Show paren
(show-paren-mode t)

;; Highlight the current line.
(require 'hl-line)
;; A fallback spec follows theme changes; theme/Customize overrides win.
;; Gruber Darker's highlight background is the existing #282828 default.
(face-spec-set 'hl-line '((t (:inherit highlight :extend t)))
               'face-defface-spec)

(defun appearance/hl-line-maybe ()
  "Highlight the current line in local, reasonably-sized buffers."
  (when (and (not (file-remote-p default-directory))
             (not (derived-mode-p 'special-mode))
             (buffers/small-p))
    (hl-line-mode 1)))

(add-hook 'prog-mode-hook #'appearance/hl-line-maybe)
(add-hook 'text-mode-hook #'appearance/hl-line-maybe)
(add-hook 'conf-mode-hook #'appearance/hl-line-maybe)

;; Cursor
(setq cursor-type 'box) ;; box/bar/hbar/nil


;; Enable smooth pixel scrolling with conservative, stable, and fast scrolling behavior.
(pixel-scroll-mode 1)
(pixel-scroll-precision-mode 1)
(setq scroll-conservatively 101)
(setq scroll-margin 0)
(setq scroll-step 0)
(setq scroll-preserve-screen-position t)
(setq fast-but-imprecise-scrolling t)

;; Display the current line and column numbers in the mode line.
(line-number-mode t)
(column-number-mode t)


;; Show recursion depth in nested minibuffer prompts.
(setq minibuffer-depth-indicate-mode t)
;; Allow opening a minibuffer while another is active.
(setq enable-recursive-minibuffers t)
;; Ignore case when completing buffer names.
(setq read-buffer-completion-ignore-case t)
;; Use Up/Down to navigate candidates in *Completions*.
(setq minibuffer-visible-completions 'up-down)
;; Show defaults only while they remain applicable.
(setq minibuffer-electric-default-mode t)

;; Title
(setq frame-title-format
      '(:eval (concat
               (if (and buffer-file-name (buffer-modified-p)) "● " "")
               (buffer-name))))
(setq icon-title-format frame-title-format)



;;; Fonts
(defgroup appearance nil
  "Portable font preferences."
  :group 'faces)

(defcustom appearance/font-families
  '("Cascadia Mono NF" "Cascadia Mono" "DejaVu Sans Mono" "Monospace")
  "Preferred default fonts, first installed family wins.
Nil leaves the frame's default font unchanged.  Run `appearance/apply-fonts'
after changing preferences; new graphical frames pick them up automatically."
  :type '(repeat string) :group 'appearance)

(defcustom appearance/font-height 160
  "Default font height in tenths of a point.  Nil keeps the frame default."
  :type '(choice (const nil) integer) :group 'appearance)

(defcustom appearance/script-font-families
  '((unicode "Noto Sans")
    (han "LXGW WenKai" "Noto Sans CJK SC")
    (cjk-misc "LXGW WenKai" "Noto Sans CJK SC")
    (bopomofo "LXGW WenKai" "Noto Sans CJK TC")
    (symbol "Noto Sans Symbols 2")
    (emoji "Noto Color Emoji")
    ((#x0370 . #x03FF) "Cascadia Mono NF" "Cascadia Mono"))
  "Preferred fonts per script or character range.
Missing families leave Emacs' own font fallback intact."
  :type '(alist :key-type sexp :value-type (repeat string))
  :group 'appearance)

(defun appearance--available-font (families frame)
  "Return the first installed family in FAMILIES on FRAME."
  (seq-find (lambda (family)
              (find-font (font-spec :family family) frame))
            families))

(defun appearance/apply-fonts (&optional frame)
  "Apply font preferences to graphical FRAME, or the selected frame.
Do not query or change fonts on a terminal or display-less daemon frame."
  (interactive)
  (let ((frame (or frame (selected-frame))))
    (when (display-graphic-p frame)
      (when-let* ((family (appearance--available-font
                          appearance/font-families frame)))
        (set-face-attribute 'default frame :family family))
      (when appearance/font-height
        (set-face-attribute 'default frame :height appearance/font-height))
      (dolist (entry appearance/script-font-families)
        (when-let* ((family (appearance--available-font (cdr entry) frame)))
          ;; No fixed pixel size: inherit the frame's face height on HiDPI.
          (set-fontset-font nil (car entry) (font-spec :family family)
                            frame 'prepend))))))

(appearance/apply-fonts)
(add-hook 'after-make-frame-functions #'appearance/apply-fonts)
(setq-default line-spacing 0.11)

;;; appearance.el ends here
