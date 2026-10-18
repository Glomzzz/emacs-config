;;; pairs.el --- Tree-sitter pairing and structural editing -*- lexical-binding: t; -*-

(require 'packages)
(require 'treesit)

;; Fingertip is the sole pairing engine.  Parser-free buffers keep ordinary
;; Emacs insertion; Fingertip's node-based commands cannot safely run there.
(use-package elec-pair
  :ensure nil
  :init
  (electric-pair-mode -1))

;; Patch the source before byte/native compilation, including on VC upgrades.
;; Declarations in this module alone would not reach native compiler workers.
(let ((source
       `(:url "https://github.com/manateelazycat/fingertip"
         :vc-backend Git
         :shell-command
         ,(mapconcat #'shell-quote-argument
                     (list (expand-file-name invocation-name invocation-directory)
                           "--batch" "-Q" "--load"
                           (expand-file-name "scripts/patch-fingertip.el"
                                             user-emacs-directory)
                           "--funcall" "pairs/patch-fingertip")
                     " "))))
  (with-eval-after-load 'package-vc
    ;; Authorize only this package's build command, not arbitrary VC builds.
    (unless (eq package-vc-allow-build-commands t)
      (add-to-list 'package-vc-allow-build-commands 'fingertip))
    ;; Already installed checkouts also need the build step on their next upgrade.
    (setf (alist-get 'fingertip package-vc-selected-packages) source))
  (packages/declare-vc 'fingertip source))

(declare-function fingertip-mode "fingertip" (&optional arg))

(defgroup pairs nil
  "Automatic activation of Fingertip in structured editing buffers."
  :group 'editing)

(defcustom pairs/enabled-modes
  '(prog-mode conf-mode markdown-mode org-mode typst-ts-mode)
  "Parent/major modes eligible for automatic Fingertip activation.
An active Tree-sitter parser is also required, regardless of this list."
  :type '(repeat symbol) :group 'pairs)

(defun pairs/enable ()
  "Enable Fingertip in small, writable buffers with an active parser.
Leave minibuffers, prose, process buffers, and special buffers alone.
Run this again after manually creating a parser in an existing buffer."
  (when (and (apply #'derived-mode-p pairs/enabled-modes)
             (not (minibufferp))
             (not buffer-read-only)
             (not (derived-mode-p 'special-mode 'comint-mode))
             (buffers/small-p)
             (treesit-parser-list))
    (fingertip-mode 1)))

(defun pairs/help ()
  "Describe the active Fingertip bindings."
  (interactive)
  (describe-minor-mode 'fingertip-mode))

(use-package fingertip
  :ensure nil
  :commands (fingertip-mode)
  :hook (after-change-major-mode . pairs/enable)
  ;; Keep ordinary Emacs Backspace instead of protecting/skipping delimiters.
  ;; Other editing commands retain upstream behavior.  Navigation lives under
  ;; C-c p instead of stealing Tempel's M-{ / M-} or Eldoc's M-n / M-p.
  ;; Percent and equals remain literal, and M-' still stores registers.
  :bind (:map fingertip-mode-map
              ("(" . fingertip-open-round)
              ("[" . fingertip-open-bracket)
              ("{" . fingertip-open-curly)
              (")" . fingertip-close-round)
              ("]" . fingertip-close-bracket)
              ("}" . fingertip-close-curly)
              ("（" . fingertip-open-chinese-round)
              ("「" . fingertip-open-chinese-bracket)
              ("【" . fingertip-open-chinese-curly)
              ("）" . fingertip-close-chinese-round)
              ("」" . fingertip-close-chinese-bracket)
              ("】" . fingertip-close-chinese-curly)
              ("\"" . fingertip-double-quote)
              ("'" . fingertip-single-quote)
              ("SPC" . fingertip-space)
              ("RET" . fingertip-newline)
              ("DEL" . backward-delete-char-untabify)
              ("<backspace>" . backward-delete-char-untabify)
              ("C-d" . fingertip-forward-delete)
              ("C-k" . fingertip-kill)
              ("C-c p (" . fingertip-wrap-round)
              ("C-c p [" . fingertip-wrap-bracket)
              ("C-c p {" . fingertip-wrap-curly)
              ("C-c p \"" . fingertip-wrap-double-quote)
              ("C-c p '" . fingertip-wrap-single-quote)
              ("C-c p u" . fingertip-unwrap)
              ("C-c p n" . fingertip-jump-right)
              ("C-c p p" . fingertip-jump-left)
              ("C-c p m" . fingertip-match-paren)
              ("C-c p j" . fingertip-jump-out-pair-and-newline)
              ("C-c p a" . fingertip-jump-up)
              ("C-c p q" . quoted-insert)
              ("C-c p t" . fingertip-mode)
              ("C-c p ?" . pairs/help)))

;;; pairs.el ends here
