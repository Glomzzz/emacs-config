;;; modeline.el --- Smart Mode Line with useful minor-mode indicators -*- lexical-binding: t; -*-

(require 'cl-lib)
(require 'packages)

(defgroup modeline nil
  "Mode-line appearance and minor-mode visibility."
  :group 'mode-line)

(defcustom modeline/visible-minor-modes
  '(flymake-mode envrc-mode
    overwrite-mode defining-kbd-macro isearch-mode
    multiple-cursors-mode rectangular-region-mode rectangle-mark-mode
    mc-hide-unmatched-lines-mode
    dired-async--modeline-mode typst-ts-watch-mode)
  "Minor-mode indicators allowed in Smart Mode Line.
Only labels are filtered: the underlying modes and keymaps are unchanged.
Eglot, Dape, narrowing, read-only, modified, and version-control status live
outside the minor-mode list and remain visible independently."
  :type '(repeat symbol)
  :group 'modeline)

(defvar rm-base-text-properties)
(defvar rm-text-properties)

(defvar modeline--configured nil
  "Whether Smart Mode Line's one-time setup has completed.")

(defun modeline/filter-minor-modes (original &rest arguments)
  "Call ORIGINAL with only important minor-mode entries, passing ARGUMENTS.
Filter by mode symbol, not rendered text, so changing diagnostics, cursor
counts, environment states, faces, and mouse bindings remain intact.
Dynamically bind the list rather than deleting other packages' entries."
  (let ((minor-mode-alist
         (cl-remove-if-not
          (lambda (entry) (memq (car entry) modeline/visible-minor-modes))
          minor-mode-alist))
        ;; Rich Minority's generic properties would overwrite Flymake/envrc
        ;; faces and mode-specific hover text or mouse actions.
        (rm-base-text-properties nil)
        (rm-text-properties nil))
    (apply original arguments)))

(defun modeline/setup ()
  "Set up Smart Mode Line once, including Emacs 31's minor-mode slot."
  (unless (advice-member-p #'modeline/filter-minor-modes 'sml/generate-minor-modes)
    (advice-add 'sml/generate-minor-modes :around #'modeline/filter-minor-modes))
  (unless modeline--configured
    (sml/setup)
    (setq modeline--configured t))
  ;; SML recognizes the old inline `minor-mode-alist' construct.  Emacs 31
  ;; renders the list through a separate public mode-line variable instead.
  (when (boundp 'mode-line-minor-modes)
    (setq-default mode-line-minor-modes '(:eval (sml/generate-minor-modes)))))

(packages/declare 'rich-minority)
(use-package rich-minority
  :ensure nil
  :demand t
  :custom
  ;; SML calls Rich Minority itself; do not enable rich-minority-mode too.
  ;; Symbol-based filtering above preserves dynamic lighters without regexes.
  (rm-blacklist nil)
  (rm-whitelist nil))

(packages/declare 'smart-mode-line)
(use-package smart-mode-line
  :ensure nil
  :demand t
  :custom
  (sml/no-confirm-load-theme t)
  (sml/theme 'respectful)
  ;; Avoid project discovery on mode-line redisplay, especially over TRAMP.
  (sml/use-projectile-p nil)
  :config
  (modeline/setup))

;;; modeline.el ends here
