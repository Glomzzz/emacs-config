;;; dirvish.el --- Dirvish file manager and desktop integration -*- lexical-binding: t; -*-

(require 'seq)
(require 'subr-x)
(require 'packages)

(declare-function dired-get-marked-files "dired" (&optional localp arg filter
                                                   distinguish-one-marked error))
(declare-function task-dashboard "task-dashboard" ())
(declare-function task-dashboard-track-process "task-dashboard"
                  (process &rest arguments))
(declare-function task-dashboard-task-process "task-dashboard" (task))
(declare-function dirvish-yank--start-proc "dirvish-yank" (cmd details))
(declare-function mounts/cancel-background-operation "mounts" ())
(declare-function mounts/mount-android "mounts" ())
(declare-function mounts/rsync-to-mac-mini "mounts" (&optional destination))
(declare-function mounts/unmount-android "mounts" ())
(declare-function mounts/visit-place "mounts" (path))

(defvar mounts/android-mount-directory)
(defvar mounts/mac-mini-mount-directory)
(defvar dirvish--props)

(packages/declare 'dirvish)

(when-let* ((dirvish-library (locate-library "dirvish"))
            (extensions-directory
             (expand-file-name "extensions/"
                               (file-name-directory dirvish-library)))
            ((file-directory-p extensions-directory)))
  (add-to-list 'load-path extensions-directory))

(defun dirvish--local-files ()
  "Return marked local Dired files, or signal for remote files."
  (let ((files (dired-get-marked-files)))
    (when (seq-some #'file-remote-p files)
      (user-error "This action only supports local files"))
    (mapcar #'file-local-name files)))

(defun dirvish/drag-files ()
  "Open marked files in ripdrag as a cross-application drag source."
  (interactive)
  (let ((program (executable-find "ripdrag")))
    (unless program
      (user-error "ripdrag is not installed; rebuild the NixOS configuration"))
    (apply #'start-process "ripdrag" nil program "-x"
           (dirvish--local-files))))

(defun dirvish/open-in-thunar ()
  "Reveal marked files, or the file at point, in Thunar."
  (interactive)
  (let ((program (executable-find "thunar")))
    (unless program
      (user-error "Thunar is not installed; rebuild the NixOS configuration"))
    (apply #'start-process "thunar" nil program
           (dirvish--local-files))))

(defun dirvish/command-line (_switch)
  "Handle the `--dirvish' command-line switch."
  (let ((path (when (and command-line-args-left
                         (not (string-prefix-p "-"
                                               (car command-line-args-left))))
                (pop command-line-args-left))))
    (dirvish (or path (expand-file-name "~/")))))

(add-to-list 'command-switch-alist '("--dirvish" . dirvish/command-line))

(defun dirvish--process-label (process)
  "Return a readable task label for a Dirvish PROCESS."
  (let* ((details (process-get process 'details))
         (sources (and (listp details) (nth 1 details)))
         (method (and (listp details) (nth 3 details))))
    (if (and (listp sources) (symbolp method))
        (format "Dirvish %s %d file%s"
                (capitalize (replace-regexp-in-string
                            "-" " " (symbol-name method)))
                (length sources)
                (if (= (length sources) 1) "" "s"))
      "Dirvish file operation")))

(defun dirvish--yank-progress (task)
  "Return the percentage reported by a Dirvish yank TASK."
  (when-let* ((process (task-dashboard-task-process task))
              (buffer (process-buffer process))
              ((buffer-live-p buffer)))
    (with-current-buffer buffer
      (let ((progress (alist-get :yank-percent dirvish--props)))
        (when progress
          (if (numberp progress)
              progress
            (string-to-number (format "%s" progress))))))))

(defun dirvish/track-yank-start (orig &rest arguments)
  "Register Dirvish's newly-created processes in the task dashboard."
  (let ((before (process-list)))
    (prog1 (apply orig arguments)
      (require 'task-dashboard)
      (dolist (process (seq-remove (lambda (candidate)
                                     (memq candidate before))
                                   (process-list)))
        (when (process-get process 'details)
          (condition-case error
              (task-dashboard-track-process
               process
               :label (dirvish--process-label process)
               :directory default-directory
               :progress-function #'dirvish--yank-progress)
            (error
             (message "Could not track Dirvish task: %s"
                      (error-message-string error)))))))))

(defun dirvish/list-tasks ()
  "Show the task dashboard in a bottom pane beside the Dirvish session."
  (interactive)
  (require 'task-dashboard)
  (let ((display-buffer-alist
         '(("\\*Task Dashboard\\*"
            (display-buffer-in-side-window)
            (side . bottom)
            (slot . 0)
            (window-height . 0.30)))))
    (task-dashboard)))

(defun dirvish--pre-redisplay-selected-window (orig window)
  "Run Dirvish's redisplay handler only for the selected WINDOW."
  (when (eq (frame-selected-window) window)
    (funcall orig window)))

(use-package dirvish
  :demand t
  :custom
  (dirvish-attributes '(file-time))
  (dirvish-cache-dir (cache/folder "dirvish"))
  (dirvish-default-layout '(0 0.0 0.55))
  (dirvish-large-directory-threshold 20000)
  (dirvish-input-debounce 0.03)
  (dirvish-input-throttle 0.15)
  (dirvish-preview-large-file-threshold (* 512 1024))
  (dirvish-preview-buffers-max-count 3)
  (dirvish-mode-line-format
   '(:left (sort symlink) :right (omit yank index)))
  :config
  (dirvish-override-dired-mode)
  (advice-add #'dirvish-pre-redisplay-h
              :around #'dirvish--pre-redisplay-selected-window)
  :bind
  (("C-x d" . dirvish-dwim)
   :map dirvish-mode-map
   ("C-c j" . dirvish/list-tasks)
   ("C-c C-r" . mounts/rsync-to-mac-mini)
   ("C-c C-a" . mounts/mount-android)
   ("C-c C-k" . mounts/cancel-background-operation)
   ("C-c C-u" . mounts/unmount-android)
   ("C-c C-d" . dirvish/drag-files)
   ("C-c C-t" . dirvish/open-in-thunar)))

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
  :bind (:map dirvish-mode-map ("?" . dirvish-dispatch)))

(use-package dirvish-fd
  :ensure nil
  :commands dirvish-fd
  :bind (:map dirvish-mode-map ("/" . dirvish-fd)))

(use-package dirvish-ls
  :ensure nil
  :commands (dirvish-ls-switches-menu dirvish-quicksort)
  :bind (:map dirvish-mode-map ("s" . dirvish-quicksort)))

(use-package dirvish-narrow
  :ensure nil
  :commands dirvish-narrow
  :bind (:map dirvish-mode-map ("N" . dirvish-narrow)))

(use-package dirvish-quick-access
  :ensure nil
  :demand t
  :custom
  (dirvish-quick-access-function #'mounts/visit-place)
  (dirvish-quick-access-entries
   `(("h" "~/" "Home")
     ("d" "~/Desktop/" "Desktop")
     ("e" ,user-emacs-directory "Emacs config")
     ("g" "~/git/" "Git repositories")
     ("m" ,mounts/mac-mini-mount-directory "mac-mini (SMB)")
     ("a" ,mounts/android-mount-directory "Android phone")))
  :bind (:map dirvish-mode-map ("o" . dirvish-quick-access)))

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
  :bind (:map dirvish-mode-map ("TAB" . dirvish-subtree-toggle)))

(use-package dirvish-vc
  :ensure nil
  :commands dirvish-vc-menu)

(use-package dirvish-yank
  :ensure nil
  :commands dirvish-yank-menu
  :bind (:map dirvish-mode-map ("y" . dirvish-yank-menu)))

(with-eval-after-load 'dirvish-yank
  (advice-add #'dirvish-yank--start-proc
              :around #'dirvish/track-yank-start))

;; Keep PostScript documents useful after routing them through Emacs.
(use-package doc-view
  :ensure nil
  :mode (("\\.e?ps\\'" . doc-view-mode-maybe)))

;;; dirvish.el ends here
