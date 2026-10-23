;;; tty.el --- Terminal display and clipboard integration -*- lexical-binding: t; -*-

(require 'packages)

(packages/declare 'xclip)
(use-package xclip
  :ensure nil
  :commands xclip-mode)

(defun tty/enable-clipboard ()
  "Use a local desktop clipboard backend when one is available.
Prefer native Wayland over XWayland on a Wayland desktop.  Headless/SSH
installations without clipboard tools retain Emacs' terminal backend.
Xclip's selection methods are TTY-specific, leaving GUI frames alone."
  (let ((wayland (and (getenv "WAYLAND_DISPLAY")
                      (executable-find "wl-copy")
                      (executable-find "wl-paste"))))
    (when (or wayland
              (and (getenv "DISPLAY")
                   (or (executable-find "xclip") (executable-find "xsel")))
              (and (eq system-type 'darwin)
                   (executable-find "pbcopy") (executable-find "pbpaste")))
      (require 'xclip)
      (when (and wayland (not (get 'xclip-method 'saved-value)))
        (setq xclip-method 'wl-copy
              xclip-program (executable-find "wl-copy")))
      (xclip-mode 1))))

(defun tty/setup ()
  "Enable mouse, tooltips, Unicode borders, and clipboard for a TTY.
Keyboard protocol negotiation is owned by the existing KKP declaration.
Corfu uses Emacs 31's native TTY child frames without corfu-terminal."
  (unless (display-graphic-p)
    (xterm-mouse-mode 1)
    (when (featurep 'tty-child-frames)
      (standard-display-unicode-special-glyphs)
      (tty-tip-mode 1))
    (tty/enable-clipboard)))

(add-hook 'tty-setup-hook #'tty/setup)

;; Handle an ordinary -nw startup too, not just future daemon clients.
(unless (or noninteractive (daemonp) (display-graphic-p))
  (tty/setup))

;; Graphics are intentionally opt-in: the package installs redisplay hooks and
;; advice on several image/document modes. Pin the tested release, never load
;; it during ordinary startup, and do not automatically enable it for clients.
(packages/declare-vc
 'kitty-graphics
 '(:url "https://github.com/cashmeredev/kitty-graphics.el"
   :branch "v1.4.0"
   :vc-backend Git))
(use-package kitty-graphics
  :ensure nil
  :commands (kitty-graphics-mode kitty-graphics-doctor
             kitty-graphics-org-heading-sizes kitty-graphics-typst-preview)
  :custom
  (kitty-graphics-shr-scale 'fit)
  (kitty-graphics-heading-sizes-auto nil)
  (kitty-graphics-enable-video nil)
  (kitty-graphics-enable-browser nil))

(defun tty/describe ()
  "Describe terminal Emacs capabilities without probing or enabling graphics."
  (interactive)
  (let ((frame (selected-frame)))
    (with-help-window "*Terminal Emacs*"
      (princ (format "Terminal: %s\nTERM: %s\nColors: %s\n"
                     (terminal-name frame) (getenv "TERM" frame)
                     (display-color-cells frame)))
      (princ (format "Native TTY child frames: %s\nMouse mode: %s\n"
                     (featurep 'tty-child-frames)
                     (bound-and-true-p xterm-mouse-mode)))
      (princ (format "Clipboard backend: %s\nOptional graphics enabled: %s\n\n"
                     (if (bound-and-true-p xclip-mode) xclip-method 'terminal)
                     (bound-and-true-p kitty-graphics-mode)))
      (princ "Fonts and font size are controlled by the terminal, not Emacs.\n")
      (princ "Use M-x kkp-status to check keyboard protocol negotiation.\n")
      (princ "Use M-x eldoc-doc-buffer for full documentation in a window.\n")
      (princ "Use M-x kitty-graphics-mode to toggle optional image/PDF support,\n")
      (princ "then M-x kitty-graphics-doctor to inspect its terminal support.\n"))))

(provide 'tty)
;;; tty.el ends here
