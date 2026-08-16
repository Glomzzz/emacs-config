;;; core.el --- Core editor defaults and shared environment helpers -*- lexical-binding: t; -*-

(setq inhibit-startup-screen t
      inhibit-startup-message t
      initial-scratch-message nil
      ring-bell-function #'ignore
      make-backup-files nil
      create-lockfiles nil
      auto-save-default nil
      tab-width 4
      compilation-scroll-output t
      read-process-output-max (* 1024 1024)
      process-adaptive-read-buffering nil
      fast-but-imprecise-scrolling t
      redisplay-skip-fontification-on-input t
      auto-window-vscroll nil
      bidi-paragraph-direction 'left-to-right
      bidi-inhibit-bpa t
      ffap-machine-p-known 'reject
      vc-handled-backends '(Git)
      eldoc-echo-area-use-multiline-p nil)

(let ((my/posix-shell (or (executable-find "bash")
                          (executable-find "sh")))
      (my/fish-shell (executable-find "fish")))
  (when my/posix-shell
    (setq shell-file-name my/posix-shell))
  (when my/fish-shell
    (setq explicit-shell-file-name my/fish-shell)
    (setenv "SHELL" my/fish-shell)))

(setq-default indent-tabs-mode nil
              display-line-numbers-type 'relative)

;; Free the bare right-shift key (only used as an unshifted modifier):
;; translation and binding together make a lone right-shift press a no-op
;; instead of self-inserting, so it can be rebound without dead keys.
;; Shift-combinations (S-*, C-S-*) are unaffected.
(define-key key-translation-map [right-shift] [ignore])
(global-set-key [right-shift] #'ignore)
(global-set-key (kbd "C-c f") #'find-file-at-point)

(defun my/prepend-to-path (dir)
  "Prepend DIR to PATH and `exec-path' when present."
  (when (file-directory-p dir)
    (unless (member dir exec-path)
      (push dir exec-path))
    (unless (string-match-p (regexp-quote dir) (or (getenv "PATH") ""))
      (setenv "PATH" (concat dir path-separator (getenv "PATH"))))))

(my/prepend-to-path (expand-file-name "~/.cargo/bin"))
(my/prepend-to-path (expand-file-name "~/.local/bin"))

;; envrc 20260518.1537 predates Emacs 31's define-globalized-minor-mode
;; machinery: the macro now generates --set-explicitly bookkeeping for every
;; globalized minor mode.  Native-compiled artifacts built by Emacs 31
;; reference these variables while older bytecode does not declare them,
;; which surfaces as "Symbol's value as variable is void:
;; envrc-mode--set-explicitly" when the two mix.  Predeclare them so any
;; loaded variant of envrc finds the bindings.
(defvar envrc-mode--set-explicitly nil
  "Preedeclared for Emacs 31 `define-globalized-minor-mode' compatibility.")
(make-variable-buffer-local 'envrc-mode--set-explicitly)
(defvar envrc-mode--suppress-set-explicitly nil
  "Preedeclared for Emacs 31 `define-globalized-minor-mode' compatibility.")

(use-package envrc
  :hook (after-init . envrc-global-mode))

;;; --- daemon self-management helpers (used by the `emc' launcher) ---

(defun my/gui-frames ()
  "Return live frames shown on a real display (graphical or tty).
A `--fg-daemon' keeps one display-less initial frame around even
when no client has opened a frame, and `frames-on-display-list'
returns that phantom whenever it is the selected frame.  The
`window-system' frame parameter is nil even on real PGTK frames,
so discriminate on `display' instead: a real frame names its
wayland/tty display, the phantom has none."
  (seq-filter (lambda (frame)
                (frame-parameter frame 'display))
              (frame-list)))

(defun my/config-newest-mtime ()
  "Return the newest modification time of the hand-written config.
Covers the top-level .el files and everything under modules/, but
not the package/cache state under .cache/ nor the custom-file:
the daemon itself rewrites custom-file (Customize saves,
package-selected-packages), so its mtime is always newer than the
daemon and would make the config look permanently stale."
  (let ((modules-dir (expand-file-name "modules/" user-emacs-directory))
        (newest nil))
    (dolist (file (append
                   (directory-files user-emacs-directory t "\\.el\\'")
                   (when (file-directory-p modules-dir)
                     (directory-files-recursively modules-dir "\\.el\\'"))))
      (unless (string-equal (file-truename file)
                            (file-truename custom-file))
        (let ((mtime (file-attribute-modification-time
                      (file-attributes file))))
          (when (and mtime
                     (or (null newest) (time-less-p newest mtime)))
            (setq newest mtime)))))
    newest))

(defun my/config-stale-p ()
  "Return non-nil if the hand-written config changed after daemon start.
The `emc' launcher wrapper checks this together with an empty
frame list: when the launching client is the daemon's only client,
the wrapper restarts the daemon before connecting so the edited
config is loaded."
  (let ((newest (my/config-newest-mtime)))
    (and newest
         (time-less-p before-init-time newest))))
