;;; dired.el --- Dired defaults -*- lexical-binding: t; -*-

(require 'autorevert)

(use-package dired
  :ensure nil
  :defer t
  :custom
  ;; Move deleted files to the desktop trash when supported.
  (delete-by-moving-to-trash t)
  ;; Keep only the active Dired buffer for a directory.
  (dired-kill-when-opening-new-dired-buffer t)
  ;; Show useful metadata, hidden files, and directories before files.
  (dired-listing-switches
   "-l --almost-all --human-readable --group-directories-first --no-group --sort=version")
  ;; Use the other Dired window as the default target.
  (dired-dwim-target t)
  ;; Ask only once before recursively deleting.
  (dired-recursive-deletes 'top)
  ;; Always copy directories recursively.
  (dired-recursive-copies 'always)
  ;; Automatically create destination directories.
  (dired-create-destination-dirs 'always)
  ;; Keep confirmation for destructive deletes.
  (dired-no-confirm '(move copy))
  ;; Enable mouse drag-and-drop for files.
  (dired-mouse-drag-files t)
  ;; Allow dragging files from Dired to another application.
  (mouse-drag-and-drop-region-cross-program t)
  :hook (dired-mode . auto-revert-mode)
  :config
  ;; Local file notifications keep Dired current without remote polling.
  (setq auto-revert-verbose nil
        auto-revert-remote-files nil
        auto-revert-avoid-polling t)
  ;; `dired-find-alternate-file' is useful for keeping one Dired buffer tidy.
  (put 'dired-find-alternate-file 'disabled nil))

(use-package wdired
  :ensure nil
  :commands (wdired-change-to-wdired-mode)
  :custom
  (wdired-allow-to-change-permissions t)
  (wdired-create-parent-directories t))

;;; dired.el ends here
