;;; git.el --- Git integration -*- lexical-binding: t; -*-

(require 'packages)
(declare-function magit-toplevel "magit-git" (&optional directory))

(packages/declare 'diff-hl)
(defun git/diff-hl-maybe ()
  "Enable diff markers for local file buffers that are not huge."
  (when (and buffer-file-name
             (not (file-remote-p buffer-file-name))
             (buffers/small-p)
             (fboundp 'diff-hl-mode))
    (diff-hl-mode 1)))

(use-package diff-hl
  :ensure nil
  :custom
  ;; Git diff calculation is filesystem/process work.  Let the buffer finish
  ;; opening while diff-hl computes markers in a worker thread.
  (diff-hl-update-async t)
  :config
  ;; `diff-hl-flydiff-mode' remains available on demand; enabling its global
  ;; watcher would make every visited file participate in VCS updates.
  (add-hook 'prog-mode-hook #'git/diff-hl-maybe)
  (add-hook 'text-mode-hook #'git/diff-hl-maybe)
  (add-hook 'conf-mode-hook #'git/diff-hl-maybe))

(packages/declare 'magit)
(use-package magit
  :ensure nil
  :commands (magit-dispatch magit-file-dispatch magit-status)
  :bind (("C-x g" . magit-status)
         ("C-x M-g" . magit-dispatch)
         ("C-c M-g" . magit-file-dispatch)))

(defun git/display-buffer-in-selected-frame (buffer)
  "Display BUFFER in the selected frame without reusing another frame."
  (let ((window (selected-window)))
    (set-window-buffer window buffer)
    (delete-other-windows window)
    window))

(defun git/status-window (directory)
  "Open Magit for DIRECTORY in the frame selected by emacsclient."
  (let ((frame (selected-frame)))
    (unless (memq frame (emc/gui-frames))
      (error "No graphical Emacs client frame is selected"))
    (select-frame frame)
    (require 'magit)
    (let ((repository (magit-toplevel directory)))
      (unless repository
        (user-error "Not a Git repository: %s" directory))
      (let ((magit-display-buffer-function
             #'git/display-buffer-in-selected-frame))
        ;; `magit-status' treats an explicit subdirectory as a request to
        ;; initialize a nested repository.  Resolve the worktree first so
        ;; this launcher is non-interactive and always opens the right repo.
        (magit-status-setup-buffer repository)))))

;;; git.el ends here
