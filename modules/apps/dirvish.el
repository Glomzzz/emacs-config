;;; dirvish.el --- Dirvish file manager, preview, and desktop integration -*- lexical-binding: t; -*-

(require 'seq)
(require 'subr-x)

(defvar my/android-mount-directory)
(defvar my/mac-mini-mount-directory)

(declare-function my/async-task-discover-processes "apps/async-tasks" ())
(declare-function my/async-task-list-in-dirvish "apps/async-tasks" ())
(declare-function my/disable-line-numbers "core/ui" ())
(declare-function my/dirvish-cancel-background-operation "apps/mounts" ())
(declare-function my/dirvish-mount-android "apps/mounts" ())
(declare-function my/dirvish-rsync-to-mac-mini "apps/mounts" (&optional destination))
(declare-function my/dirvish-unmount-android "apps/mounts" ())
(declare-function my/dirvish-visit-place "apps/mounts" (path))

(defun my/dired-local-files ()
  "Return the marked local Dired files, or signal for remote files."
  (let ((files (dired-get-marked-files)))
    (when (seq-some #'file-remote-p files)
      (user-error "This action only supports local files"))
    (mapcar #'file-local-name files)))

(defun my/dirvish-drag-files ()
  "Open marked files in ripdrag as a cross-application drag source."
  (interactive)
  (let ((program (executable-find "ripdrag")))
    (unless program
      (user-error "ripdrag is not installed; rebuild the NixOS configuration"))
    (apply #'start-process "ripdrag" nil program "-x"
           (my/dired-local-files))))

(defun my/dirvish-open-in-thunar ()
  "Reveal the marked files, or the file at point, in Thunar."
  (interactive)
  (let ((program (executable-find "thunar")))
    (unless program
      (user-error "Thunar is not installed; rebuild the NixOS configuration"))
    (apply #'start-process "thunar" nil program
           (my/dired-local-files))))

(defun my/command-line-dirvish (_switch)
  "Handle the --dirvish command-line switch."
  (let ((path (when (and command-line-args-left
                         (not (string-prefix-p "-"
                                               (car command-line-args-left))))
                (pop command-line-args-left))))
    (dirvish (or path (expand-file-name "~/")))))

(add-to-list 'command-switch-alist
             '("--dirvish" . my/command-line-dirvish))

(when-let* ((dirvish-library (locate-library "dirvish"))
            (extensions-directory
             (expand-file-name "extensions/"
                               (file-name-directory dirvish-library)))
            ((file-directory-p extensions-directory)))
  (add-to-list 'load-path extensions-directory))

(defun my/dirvish-track-yank-start (orig &rest arguments)
  "Register the Dirvish process started by ORIG in the task dashboard."
  (prog1 (apply orig arguments)
    (my/async-task-discover-processes)))

(defun my/dirvish-pre-redisplay-selected-window (orig window)
  "Run Dirvish redisplay handler ORIG only for the selected WINDOW."
  (when (eq (frame-selected-window) window)
    (funcall orig window)))

(use-package dirvish
  :init
  (dirvish-override-dired-mode)
  :custom
  (dirvish-attributes '(file-time))
  (dirvish-cache-dir
   (expand-file-name "dirvish/" my/emacs-cache-dir))
  (dirvish-default-layout '(0 0.0 0.55))
  (dirvish-large-directory-threshold 20000)
  (dirvish-input-debounce 0.03)
  (dirvish-input-throttle 0.15)
  (dirvish-preview-large-file-threshold (* 512 1024))
  (dirvish-preview-buffers-max-count 3)
  (dirvish-mode-line-format
   '(:left (sort symlink) :right (omit yank index)))
  :config
  (advice-add #'dirvish-pre-redisplay-h
              :around #'my/dirvish-pre-redisplay-selected-window)
  :bind
  (("C-x d" . dirvish-dwim)
   ("C-c d" . dirvish)
   :map dirvish-mode-map
   ("C-c j" . my/async-task-list-in-dirvish)
   ("C-c C-r" . my/dirvish-rsync-to-mac-mini)
   ("C-c C-a" . my/dirvish-mount-android)
   ("C-c C-k" . my/dirvish-cancel-background-operation)
   ("C-c C-u" . my/dirvish-unmount-android)
   ("C-c C-d" . my/dirvish-drag-files)
   ("C-c C-t" . my/dirvish-open-in-thunar)))

(use-package dirvish-history
  :ensure nil
  :commands (dirvish-history-go-backward
             dirvish-history-go-forward
             dirvish-history-menu)
  :bind
  (:map dirvish-mode-map
   ("M-f" . dirvish-history-go-forward)
   ("M-b" . dirvish-history-go-backward)))

(use-package dirvish-emerge
  :ensure nil
  :commands dirvish-emerge-menu)

(use-package dirvish-extras
  :ensure nil
  :commands dirvish-dispatch
  :bind
  (:map dirvish-mode-map
   ("?" . dirvish-dispatch)))

(use-package dirvish-fd
  :ensure nil
  :commands dirvish-fd
  :bind
  (:map dirvish-mode-map
   ("/" . dirvish-fd)))

(use-package dirvish-ls
  :ensure nil
  :commands (dirvish-ls-switches-menu dirvish-quicksort)
  :bind
  (:map dirvish-mode-map
   ("s" . dirvish-quicksort)))

(use-package dirvish-narrow
  :ensure nil
  :commands dirvish-narrow
  :bind
  (:map dirvish-mode-map
   ("N" . dirvish-narrow)))

(use-package dirvish-quick-access
  :ensure nil
  :demand t
  :custom
  (dirvish-quick-access-function #'my/dirvish-visit-place)
  (dirvish-quick-access-entries
   `(("h" "~/" "Home")
     ("d" "~/Desktop/" "Desktop")
     ("e" ,user-emacs-directory "Emacs config")
     ("g" "~/git/" "Git repositories")
     ("m" ,my/mac-mini-mount-directory "mac-mini (SMB)")
     ("a" ,my/android-mount-directory "Android phone")))
  :bind
  (:map dirvish-mode-map
   ("o" . dirvish-quick-access)))

(use-package dirvish-rsync
  :ensure nil
  :commands (dirvish-rsync dirvish-rsync-switches-menu)
  :custom
  (dirvish-rsync-args
   '("--archive"
     "--human-readable"
     "--partial"
     "--partial-dir=.rsync-partial"
     "--info=progress2"
     "--timeout=600")))

(use-package dirvish-subtree
  :ensure nil
  :commands (dirvish-subtree-menu dirvish-subtree-toggle)
  :bind
  (:map dirvish-mode-map
   ("TAB" . dirvish-subtree-toggle)))

(use-package dirvish-vc
  :ensure nil
  :commands dirvish-vc-menu)

;; Keep the document types formerly owned by an external viewer useful after
;; routing the same MIME types to Emacs.
(use-package nov
  :mode ("\.epub\'" . nov-mode))

(use-package doc-view
  :ensure nil
  :mode ("\.e?ps\'" . doc-view-mode-maybe)
  :hook (doc-view-mode . my/disable-line-numbers))

(use-package dirvish-yank
  :ensure nil
  :commands dirvish-yank-menu
  :bind
  (:map dirvish-mode-map
   ("y" . dirvish-yank-menu)))

(with-eval-after-load 'dirvish-yank
  (advice-add #'dirvish-yank--start-proc
              :around #'my/dirvish-track-yank-start))

;;; dirvish.el ends here
