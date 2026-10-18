;;; pi.el --- Inline Pi insertion integration -*- lexical-binding: t; -*-

(require 'packages)

;; Local package: no archive declaration or network installation is needed.
(use-package pi-inline
  :ensure nil
  :load-path "pkgs"
  :commands (pi-inline/start pi-inline/session)
  :bind (("C-c C-a" . pi-inline/start)))

;; A global binding alone loses to Org attachment and Markdown prefixes.
;; Give the requested key precedence only in ordinary editing buffers, leaving
;; Dired's existing mount command and other special-buffer controls alone.
(defvar pi/inline-key-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "C-c C-a") #'pi-inline/start)
    map))

(define-minor-mode pi/inline-key-mode
  "Reserve C-c C-a for inline Pi insertion in an editing buffer."
  :lighter nil :keymap pi/inline-key-mode-map)

(defun pi/enable-inline-key ()
  "Enable the inline Pi shortcut outside minibuffers and special buffers."
  (unless (or (minibufferp) (derived-mode-p 'special-mode))
    (pi/inline-key-mode 1)))

(define-globalized-minor-mode pi/global-inline-key-mode
  pi/inline-key-mode pi/enable-inline-key)

(pi/global-inline-key-mode 1)

;;; pi.el ends here
