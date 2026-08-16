;;; version-control.el --- Git workflows with Magit -*- lexical-binding: t; -*-

(use-package magit
  :commands (magit-dispatch magit-file-dispatch magit-status)
  :bind
  (("C-x g" . magit-status)
   ("C-x M-g" . magit-dispatch)
   ("C-c M-g" . magit-file-dispatch)))

(defun my/magit-status-window (dir)
  "Open Magit for DIR, filling a whole GUI frame.
Called by the `magit' fish function (see the nixos-config emacs
module) through emacsclient.  Selects an existing GUI frame and
shows the status buffer as that frame's only window; this leaves
C-x g inside Emacs on its usual split display.  The fish function
falls back to --create-frame when no GUI frame exists: displaying
from a frame-less daemon targets its display-less initial frame
and wedges the PGTK daemon."
  (let ((frame (car (my/gui-frames))))
    (unless frame
      (error "No Emacs GUI frame open; re-run `magit' so emacsclient can create one"))
    (select-frame frame)
    (require 'magit)
    (let ((magit-display-buffer-function
           #'magit-display-buffer-fullframe-status-v1))
      (magit-status dir))))

;;; version-control.el ends here
