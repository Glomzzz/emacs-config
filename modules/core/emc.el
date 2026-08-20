;;; modules/core/emc.el --- Lisp entry points for the `emc' launcher -*- lexical-binding: t; -*-
(require 'seq)

(defun emc/gui-frames ()
  "Return live frames connected to a graphical or terminal display.
A foreground daemon keeps a display-less initial frame alive, so test
the `display' frame parameter instead of treating every live frame as a
client frame."
  (seq-filter (lambda (frame)
                (frame-parameter frame 'display))
              (frame-list)))

(defun emc/config-newest-mtime ()
  "Return the newest modification time in the hand-written config.
Ignore `custom-file' because Emacs can rewrite it while the daemon is
running, which would otherwise make the config permanently stale."
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

(defun emc/config-stale-p ()
  "Return non-nil when the config changed after this Emacs started."
  (let ((newest (emc/config-newest-mtime)))
    (and newest
         (time-less-p before-init-time newest))))

(provide 'emc)

;;; emc.el ends here
