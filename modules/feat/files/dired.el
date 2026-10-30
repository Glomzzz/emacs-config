;;; dired.el --- Dired defaults -*- lexical-binding: t; -*-

(require 'autorevert)

(use-package dired
  :ensure nil
  :defer t
  :after hydra
  :bind (("C-x C-h D" . hydra-dired/body))
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
  ;; Dired menu adapted from the hydra wiki's Dired example.  Heads that need
  ;; dired-x, ediff, rsync, or dired+ are left out because this config does not
  ;; load those.
  :hydra (hydra-dired
          (:hint nil :color pink)
          "
 _+_ mkdir     _v_ view       _m_ mark       _(_ details     _i_ insert subdir
 _C_ copy      _O_ view other _U_ unmark all _)_ omit        _w_ kill subdir
 _D_ delete    _o_ open other _u_ unmark     _l_ redisplay   _g_ revert buffer
 _R_ rename    _M_ chmod      _t_ toggle     _s_ sort        _A_ find regexp
 _Y_ rel link  _G_ chgrp      _Z_ compress   _S_ symlink     _Q_ regexp replace
 _?_ summary   _._ quit"
          ("+" dired-create-directory)
          ("C" dired-do-copy)
          ("D" dired-do-delete)
          ("R" dired-do-rename)
          ("Y" dired-do-relsymlink)
          ("S" dired-do-symlink)
          ("v" dired-view-file)
          ("O" dired-display-file)
          ("o" dired-find-file-other-window)
          ("M" dired-do-chmod)
          ("G" dired-do-chgrp)
          ("m" dired-mark)
          ("U" dired-unmark-all-marks)
          ("u" dired-unmark)
          ("t" dired-toggle-marks)
          ("(" dired-hide-details-mode)
          (")" dired-omit-mode)
          ("i" dired-maybe-insert-subdir)
          ("w" dired-kill-subdir)
          ("l" dired-do-redisplay)
          ("g" revert-buffer)
          ("s" dired-sort-toggle-or-edit)
          ("A" dired-do-find-regexp)
          ("Q" dired-do-find-regexp-and-replace)
          ("Z" dired-do-compress)
          ("?" dired-summary)
          ("." nil :color blue))
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
