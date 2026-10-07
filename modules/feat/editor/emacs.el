;;; emacs.el --- Emacs defaults -*- lexical-binding: t; -*-

(require 'seq)

;; FUSE-backed removable/network mounts can remain mounted after their
;; connection has failed.  A synchronous stat on one of these paths can then
;; block Emacs for the duration of the FUSE/network timeout (including while
;; the daemon is shutting down).  Keep this check purely lexical: resolving a
;; path with `file-truename' would perform the very I/O we are avoiding.
(defconst emacs/unreliable-path-prefixes
  (mapcar #'file-name-as-directory
          (list (expand-file-name "~/mnt/mac-mini/")
                (expand-file-name "~/mnt/android/")))
  "Path prefixes backed by FUSE mounts that may become unresponsive.")

(defun emacs/unreliable-path-p (path)
  "Return non-nil when PATH is below a known unreliable mount.

The comparison intentionally uses expanded strings rather than filesystem
queries so this predicate is safe to call from timer and shutdown hooks."
  (when path
    (let ((expanded (expand-file-name path)))
      (seq-some (lambda (prefix)
                  (string-prefix-p prefix expanded))
                emacs/unreliable-path-prefixes))))

(defun emacs/disable-auto-revert-on-unreliable-path ()
  "Disable auto-revert for buffers below an unreliable FUSE mount."
  (when (and auto-revert-mode
             (emacs/unreliable-path-p (or buffer-file-name default-directory)))
    (auto-revert-mode -1)))

(add-hook 'auto-revert-mode-hook
          #'emacs/disable-auto-revert-on-unreliable-path)
(setq read-process-output-max (* 1024 1024)
      process-adaptive-read-buffering nil
      redisplay-skip-fontification-on-input t
      ;; Avoid repeatedly compacting the font cache during interactive use.
      ;; The cache is bounded by Emacs and this trades a small amount of memory
      ;; for smoother redisplay when many fonts are configured.
      inhibit-compacting-font-caches t)

;; Trusted content may execute code automatically, not just show diagnostics.
;; Limit the defaults to development trees; downloads and shared temporary
;; files must be trusted explicitly.  Preserve an explicit Customize choice.
(unless (get 'trusted-content 'saved-value)
  (setq trusted-content
        (list "~/git/"
              (abbreviate-file-name
               (file-name-as-directory
                (expand-file-name user-emacs-directory))))))
;; Summarize the most severe diagnostic at the end of its line, in addition
;; to the fringe indicators and `M-g f' (`consult-flymake').
(setq flymake-show-diagnostics-at-end-of-line 'short)

(setq create-lockfiles nil)
(setq make-backup-files t
      backup-by-copying t
      version-control t
      kept-new-versions 5
      kept-old-versions 2
      delete-old-versions t
      backup-directory-alist `(("." . ,(cache/folder "backups")))
      auto-save-default t
      tramp-auto-save-directory (cache/folder "tramp-auto-save")
      auto-save-list-file-prefix (cache/file "auto-save-list/.saves-"))
(unless (file-exists-p (file-name-directory auto-save-list-file-prefix))
  (make-directory (file-name-directory auto-save-list-file-prefix) t))
;; The non-nil third element keeps each source file's auto-save distinct.
(setq auto-save-file-name-transforms
      `((".*" ,(cache/folder "auto-save-files") t)))
(unless (file-exists-p (file-name-directory (car (cdr (car auto-save-file-name-transforms)))))
  (make-directory (file-name-directory (car (cdr (car auto-save-file-name-transforms)))) t))



;; Make searches case-insensitive by default.
(setq-default case-fold-search t)
;; Allow abbreviated y/n responses to prompts.
(setq use-short-answers t)
;; Prefer minibuffer prompts over dialog boxes.
(setq use-dialog-box nil)
;; Use the minibuffer instead of file-selection dialogs.
(setq use-file-dialog nil)
;; Disable the visual bell.
(setq visible-bell nil)
;; Silence the audible bell.
(setq ring-bell-function #'ignore)


;; Cursor move
(setq sentence-end-double-space nil
      sentence-end "\\([ \t]+\\|  \\|[.?!][]\"')}]*\\($\\|[ \t]\\)\\)[ \t\n]*"
      adaptive-fill-regexp "[ \t]+|[ \t]*([0-9]+.|*+)[ \t]*"
      adaptive-fill-first-line-regexp "^* *$"
      bidi-inhibit-bpa t ;; im LTR user and never use RTL
      bidi-display-reordering 'left-to-right
      bidi-paragraph-direction 'left-to-right
      long-line-threshold 1000
      large-hscroll-threshold 1000
      truncate-partial-width-windows nil)

;; i18n
(setq locale-coding-system 'utf-8-unix
      buffer-line-coding-system 'utf8-unix
      default-process-coding-system '(utf-8-unix . utf-8-unix))
(prefer-coding-system 'utf-8-unix)
(set-language-environment "UTF-8")
(set-default-coding-systems 'utf-8-unix)
(set-keyboard-coding-system 'utf-8-unix)
(set-terminal-coding-system 'utf-8-unix)
(set-file-name-coding-system 'utf-8-unix)
(set-selection-coding-system 'utf-8-unix)

;; Edit
(setq-default indent-tabs-mode nil
              tab-always-indent 'complete
              tab-width 2
              standard-indent 2
              c-basic-offset 2
              fill-column 80
              word-wrap t
              word-wrap-by-category t
              kill-do-not-save-duplicates t
              kill-whole-line t
              track-eol t
              disable-input-method nil)

;; Del selection(replace things when write on selection)
(delete-selection-mode t)

(defgroup editor nil
  "Shared editing policies."
  :group 'editing)

(defcustom editor/trim-trailing-whitespace 'code
  "Save-time trailing whitespace cleanup policy.
`code' cleans programming/config buffers but preserves prose and markup.
T opts any buffer in; nil disables cleanup.  Set this directory-locally
when a project's format has meaningful trailing spaces."
  :type '(choice (const :tag "Code/config only" code)
                 (const :tag "Always" t) (const :tag "Never" nil))
  :group 'editor)
(make-variable-buffer-local 'editor/trim-trailing-whitespace)
(put 'editor/trim-trailing-whitespace 'safe-local-variable
     (lambda (value) (memq value '(code t nil))))

(defun emacs/delete-trailing-whitespace-maybe ()
  "Clean trailing whitespace according to the current project's policy."
  (when (and editor/trim-trailing-whitespace
             (or (eq editor/trim-trailing-whitespace t)
                 (derived-mode-p 'prog-mode 'conf-mode))
             (not (file-remote-p default-directory))
             (buffers/small-p))
    (delete-trailing-whitespace)))

(add-hook 'before-save-hook #'emacs/delete-trailing-whitespace-maybe)

;; Auto revert.  File notifications handle local files without polling, and
;; TRAMP buffers opt out because their checks can involve network I/O.
(setq auto-revert-remote-files nil
      auto-revert-use-notify t
      auto-revert-interval 5
      auto-revert-verbose nil)
(global-auto-revert-mode t)

;; uniquify buffer
(setq uniquify-buffer-name-style 'forward)
(setq uniquify-strip-common-suffix t)
(setq uniquify-after-kill-buffer-flag t)

;; compile-mode
(require 'compile)
(setq compile-command "")
(setq compilation-always-kill t)
(setq compilation-ask-about-save nil)
(setq compilation-max-output-line-length nil)
(setq compilation-scroll-output 'first-error)
(add-to-list 'compilation-error-regexp-alist
             '("\\([a-zA-Z0-9\\.]+\\)(\\([0-9]+\\)\\(,\\([0-9]+\\)\\)?) \\(Warning:\\)?"
               1 2 (4) (5)))

;; Search/Replace
(setq query-replace-highlight t)
(setq isearch-lazy-highlight t)
(setq lazy-highlight-cleanup t)
(setq isearch-wrap-pause t)
(setq isearch-allow-motion t)
(setq isearch-motion-changes-direction t)
(setq isearch-lazy-count t)
(setq lazy-count-prefix-format "%s/%s ")

;; ibuffer(instead of bufferlist)
(setq ibuffer-use-other-window nil)
(setq ibuffer-default-sorting-mode 'filename/process)
(setq ibuffer-title-face 'font-lock-doc-face)
(setq ibuffer-use-header-line t)
(setq ibuffer-default-shrink-to-minimum-size nil)



;;; emacs.el ends here
