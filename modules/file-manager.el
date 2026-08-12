;;; file-manager.el --- Dirvish file management and desktop integration -*- lexical-binding: t; -*-

(require 'dired)
(require 'seq)
(require 'subr-x)

(defconst my/android-mount-directory
  (expand-file-name "~/mnt/android/"))

(defun my/run-android-phone (action)
  "Run the android-phone helper with ACTION and report a useful error."
  (let ((program (executable-find "android-phone")))
    (unless program
      (user-error "android-phone is not installed; rebuild the NixOS configuration"))
    (with-temp-buffer
      ;; Never run the unmount helper with its process cwd inside the mount.
      (let ((default-directory (expand-file-name "~/"))
            (status (call-process program nil t nil action)))
        (unless (eq status 0)
          (user-error "%s" (string-trim (buffer-string))))))))

(defun my/dirvish-visit-place (path)
  "Open PATH in Dirvish, mounting Android storage when necessary."
  (when (equal (directory-file-name (expand-file-name path))
               (directory-file-name my/android-mount-directory))
    (my/run-android-phone "mount"))
  (dirvish-dwim path))

(defun my/dirvish-mount-android ()
  "Mount the connected Android phone and open it in Dirvish."
  (interactive)
  (my/dirvish-visit-place my/android-mount-directory))

(defun my/dirvish-unmount-android ()
  "Leave and unmount the Android phone filesystem."
  (interactive)
  (dirvish-dwim (expand-file-name "~/"))
  (my/run-android-phone "unmount"))

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

(use-package dired
  :ensure nil
  :custom
  (delete-by-moving-to-trash t)
  (dired-dwim-target t)
  (dired-kill-when-opening-new-dired-buffer t)
  (dired-listing-switches
   "-l --almost-all --human-readable --group-directories-first --no-group --sort=version")
  (dired-mouse-drag-files t)
  (dired-recursive-copies 'always)
  (dired-recursive-deletes 'top)
  (mouse-drag-and-drop-region-cross-program t)
  :hook (dired-mode . auto-revert-mode)
  :config
  (setq auto-revert-verbose nil)
  (put 'dired-find-alternate-file 'disabled nil))

(use-package dirvish
  :init
  (dirvish-override-dired-mode)
  :custom
  (dirvish-attributes
   '(vc-state subtree-state nerd-icons collapse git-msg file-time file-size))
  (dirvish-cache-dir
   (expand-file-name "dirvish/" my/emacs-cache-dir))
  (dirvish-default-layout '(1 0.15 0.55))
  (dirvish-large-directory-threshold 20000)
  (dirvish-mode-line-format
   '(:left (sort symlink) :right (omit yank index)))
  :bind
  (("C-x d" . dirvish-dwim)
   ("C-c d" . dirvish)
   :map dirvish-mode-map
   ("?" . dirvish-dispatch)
   ("/" . dirvish-fd)
   ("N" . dirvish-narrow)
   ("o" . dirvish-quick-access)
   ("s" . dirvish-quicksort)
   ("y" . dirvish-yank-menu)
   ("TAB" . dirvish-subtree-toggle)
   ("M-f" . dirvish-history-go-forward)
   ("M-b" . dirvish-history-go-backward)
   ("C-c C-a" . my/dirvish-mount-android)
   ("C-c C-u" . my/dirvish-unmount-android)
   ("C-c C-d" . my/dirvish-drag-files)
   ("C-c C-t" . my/dirvish-open-in-thunar)))

(use-package dirvish-history
  :ensure nil
  :commands (dirvish-history-go-backward
             dirvish-history-go-forward
             dirvish-history-menu))

(use-package dirvish-emerge
  :ensure nil
  :commands dirvish-emerge-menu)

(use-package dirvish-ls
  :ensure nil
  :commands (dirvish-ls-switches-menu dirvish-quicksort))

(use-package dirvish-narrow
  :ensure nil
  :commands dirvish-narrow)

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
     ("m" "/mnt/mac-mini/" "mac-mini (SMB)")
     ("a" ,my/android-mount-directory "Android phone"))))

(use-package dirvish-rsync
  :ensure nil
  :commands (dirvish-rsync dirvish-rsync-switches-menu))

(use-package dirvish-subtree
  :ensure nil
  :commands (dirvish-subtree-menu dirvish-subtree-toggle))

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
  :commands dirvish-yank-menu)

;;; file-manager.el ends here
