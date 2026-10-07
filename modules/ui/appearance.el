;;; modules/core/basic.el  -*- lexical-binding: t; -*-

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
  "Enable line numbers for local programming and text buffers."
  (when (and (not (file-remote-p default-directory))
             (not (derived-mode-p 'special-mode)))
    (display-line-numbers-mode 1)))

(add-hook 'prog-mode-hook #'appearance/line-numbers-maybe)
(add-hook 'text-mode-hook #'appearance/line-numbers-maybe)
(add-hook 'conf-mode-hook #'appearance/line-numbers-maybe)

;; Show paren
(show-paren-mode t)

;; Highlight the current line.
(require 'hl-line)
(set-face-background 'hl-line "#282828")

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
;; eng(default)
(set-face-attribute 'default nil :family "Cascadia Mono NF" :height 160)
;; unicode
(set-fontset-font t 'unicode (font-spec :family "Noto Sans"))
;; zh_cn.  No `:size' here: a fixed pixel size does not follow the frame's
;; point size on a scaled display, so let the fontset inherit the face height.
(dolist (CnFamily '(han cjk-misc bopomofo))
  (set-fontset-font t CnFamily (font-spec :family "LXGW WenKai") nil 'prepend))
;; symbol
(set-fontset-font t 'symbol (font-spec :family "Noto Sans Symbols 2") nil 'prepend)
;; emoji
(set-fontset-font t 'emoji (font-spec :family "Noto Color Emoji") nil 'prepend)
;; greek
(set-fontset-font t '(#x0370 . #x03FF) "Cascadia Mono NF")
(setq-default line-spacing 0.11)


;;; basic.el ends here
