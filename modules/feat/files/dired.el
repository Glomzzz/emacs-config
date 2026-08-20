;;; dired.el  -*- lexical-binding: t; -*-


(use-package dired
  :ensure nil
  :defer t
  :custom
  ;; Show human-readable file sizes and directories first.
  (dired-listing-switches "-alh --group-directories-first")
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
  (dired-mouse-drag-files t))

(use-package wdired
  :ensure nil
  :commands (wdired-change-to-wdired-mode)
  :custom
  (wdired-allow-to-change-permissions t)
  (wdired-create-parent-directories t))

;;; dired.el ends here
