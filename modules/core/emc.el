;;; modules/core/emc.el --- Lisp entry points for the `emc' launcher -*- lexical-binding: t; -*-
(require 'seq)

(defun emc/client-frames ()
  "Return GUI and TTY client frames, excluding the daemon's initial frame.
TTY frames have a `tty' parameter even when `display' is nil."
  (seq-filter (lambda (frame)
                (or (frame-parameter frame 'display)
                    (frame-parameter frame 'tty)))
              (frame-list)))

(defalias 'emc/gui-frames #'emc/client-frames
  "Compatibility name for `emc/client-frames'.")

(defun emc/config-newest-mtime ()
  "Return the newest modification time in the hand-written config.
Include modules and local packages, but not test fixtures.
Ignore `custom-file' because Emacs can rewrite it while the daemon is
running, which would otherwise make the config permanently stale."
  (let ((newest nil))
    (dolist (file (append
                   (directory-files user-emacs-directory t "\\.el\\'")
                   (seq-mapcat
                    (lambda (path)
                      (let ((directory (expand-file-name
                                        path user-emacs-directory)))
                        (when (file-directory-p directory)
                          (directory-files-recursively directory "\\.el\\'"))))
                    '("modules/" "pkgs/"))))
      (unless (and custom-file
                   (string-equal (file-truename file)
                                 (file-truename custom-file)))
        (let ((mtime (file-attribute-modification-time
                      (file-attributes file))))
          (when (and mtime
                     (or (null newest) (time-less-p newest mtime)))
            (setq newest mtime)))))
    newest))

(defun emc/config-stale-p ()
  "Return non-nil when the config changed after this Emacs started."
  (let ((newest (emc/config-newest-mtime)))
    (and newest
         (time-less-p before-init-time newest))))

(defun emc/launcher-state ()
  "Return `stale' only when the managed launcher may safely restart.
Keep open TTY/GUI clients, modified files, and background mail sends alive.
An unresponsive daemon must be handled by the launcher without assuming
that it is safe to restart."
  (if (or (emc/client-frames)
          (seq-some (lambda (buffer)
                      (with-current-buffer buffer
                        (and buffer-file-name (buffer-modified-p))))
                    (buffer-list))
          (bound-and-true-p mail-async--jobs)
          (not (emc/config-stale-p)))
      'ok
    'stale))

(provide 'emc)

;;; emc.el ends here
