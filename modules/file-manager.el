;;; file-manager.el --- Dirvish file management and desktop integration -*- lexical-binding: t; -*-

(require 'dired)
(require 'seq)
(require 'subr-x)

(defconst my/android-mount-directory
  (expand-file-name "~/mnt/android/"))

(defconst my/mac-mini-mount-directory
  (expand-file-name "~/mnt/mac-mini/"))

(defvar my/mac-mini-connect-process nil)
(defvar my/android-phone-process nil)

(defun my/android-phone-process-sentinel (process _event)
  "Finish the asynchronous android-phone helper PROCESS."
  (when (and (memq (process-status process) '(exit signal))
             (not (process-get process 'handled)))
    (process-put process 'handled t)
    (let* ((status (process-exit-status process))
           (output-buffer (process-buffer process))
           (details (if (buffer-live-p output-buffer)
                        (with-current-buffer output-buffer
                          (string-trim (buffer-string)))
                      ""))
           (action (process-get process 'action))
           (task (my/async-task-for-process process))
           (target-window (process-get process 'target-window))
           (source-buffer (process-get process 'source-buffer)))
      (when (eq process my/android-phone-process)
        (setq my/android-phone-process nil))
      (unwind-protect
          (cond
           ((process-get process 'cancelled)
            (my/async-task-cancelled task)
            (message "Stopped Android phone operation"))
           ((zerop status)
            (my/async-task-complete task)
            (if (string-equal action "mount")
                (if (and (window-live-p target-window)
                         (eq (window-buffer target-window) source-buffer))
                    (with-selected-window target-window
                      (dirvish-dwim my/android-mount-directory))
                  (message "Android phone is mounted; use quick access again"))
              (message "Android phone unmounted")))
           (t
            (my/async-task-fail task details)
            (message "android-phone %s failed%s"
                     action
                     (if (string-empty-p details)
                         ""
                       (format ": %s" details)))))
        (when (buffer-live-p output-buffer)
          (kill-buffer output-buffer))))))

(defun my/run-android-phone-async (action)
  "Run the android-phone helper with ACTION without blocking Emacs."
  (if (process-live-p my/android-phone-process)
      (message "An Android phone operation is already running")
    (let ((program (executable-find "android-phone"))
          (output-buffer (generate-new-buffer " *android-phone*"))
          (default-directory (expand-file-name "~/")))
      (unless program
        (kill-buffer output-buffer)
        (user-error "android-phone is not installed; rebuild NixOS"))
      (let ((process
             (condition-case error-data
                 (make-process
                  :name "android-phone"
                  :buffer output-buffer
                  :command (list program action)
                  :connection-type 'pipe
                  :noquery t
                  :sentinel #'ignore)
               (error
                (kill-buffer output-buffer)
                (signal (car error-data) (cdr error-data))))))
        (setq my/android-phone-process process)
        (process-put process 'action action)
        (process-put process 'target-window (selected-window))
        (process-put process 'source-buffer (current-buffer))
        (my/async-task-register
         (format "%s Android phone"
                 (if (string-equal action "mount") "Mount" "Unmount"))
         'mount
         :detail my/android-mount-directory
         :process process
         :buffer output-buffer)
        (message "%s Android phone... use C-c C-k to cancel"
                 (if (string-equal action "mount") "Mounting" "Unmounting"))
        (set-process-sentinel process #'my/android-phone-process-sentinel)
        (unless (process-live-p process)
          (my/android-phone-process-sentinel process "finished\n"))))))

(defun my/dirvish-mac-mini-connect-sentinel (process _event)
  "Open mac-mini when its persistent connector PROCESS succeeds."
  (when (memq (process-status process) '(exit signal))
    (let* ((status (process-exit-status process))
           (output-buffer (process-buffer process))
           (details (if (buffer-live-p output-buffer)
                        (with-current-buffer output-buffer
                          (string-trim (buffer-string)))
                      ""))
           (task (my/async-task-for-process process))
           (target-window (process-get process 'target-window))
           (source-buffer (process-get process 'source-buffer)))
      (unwind-protect
          (when (eq process my/mac-mini-connect-process)
            (setq my/mac-mini-connect-process nil)
            (cond
             ((zerop status)
              (my/async-task-complete task)
              (if (and (window-live-p target-window)
                       (eq (window-buffer target-window) source-buffer))
                  (condition-case error-data
                      (with-selected-window target-window
                        (dirvish-dwim my/mac-mini-mount-directory))
                    (error
                     (message "Could not open mac-mini: %s"
                              (error-message-string error-data))))
                (message "mac-mini is ready; use quick access again")))
             ((process-get process 'cancelled)
              (my/async-task-cancelled task)
              (message "Stopped connecting to mac-mini"))
             (t
              (my/async-task-fail task details)
              (message "mac-mini connector stopped%s"
                       (if (string-empty-p details)
                           ""
                         (format ": %s" details))))))
        (when (buffer-live-p output-buffer)
          (kill-buffer output-buffer))))))

(defun my/dirvish-open-mac-mini ()
  "Keep connecting to mac-mini asynchronously, then open it in Dirvish."
  (interactive)
  (if (process-live-p my/mac-mini-connect-process)
      (message "Already connecting to mac-mini")
    (let ((program (executable-find "mac-mini-connect"))
          (output-buffer (generate-new-buffer " *mac-mini connector*"))
          (target-window (selected-window))
          (source-buffer (current-buffer))
          (default-directory (expand-file-name "~/")))
      (unless program
        (kill-buffer output-buffer)
        (user-error "mac-mini-connect is not installed; rebuild NixOS"))
      (let ((process
             (condition-case error-data
                 (make-process
                  :name "mac-mini connector"
                  :buffer output-buffer
                  :command (list program)
                  :connection-type 'pipe
                  :noquery t
                  :sentinel #'ignore)
               (error
                (kill-buffer output-buffer)
                (signal (car error-data) (cdr error-data))))))
        (setq my/mac-mini-connect-process process)
        (process-put process 'target-window target-window)
        (process-put process 'source-buffer source-buffer)
        (my/async-task-register
         "Connect to mac-mini" 'mount
         :detail my/mac-mini-mount-directory
         :process process
         :buffer output-buffer)
        (message "Connecting to mac-mini... use C-c C-k to cancel")
        (set-process-sentinel process #'my/dirvish-mac-mini-connect-sentinel)
        (unless (process-live-p process)
          (my/dirvish-mac-mini-connect-sentinel process "finished\n"))))))

(defun my/dirvish-cancel-mac-mini-connect ()
  "Cancel the current background mac-mini connection attempt."
  (interactive)
  (if (process-live-p my/mac-mini-connect-process)
      (let ((process my/mac-mini-connect-process))
        (setq my/mac-mini-connect-process nil)
        (process-put process 'cancelled t)
        (delete-process process)
        (when-let* ((output-buffer (process-buffer process))
                    ((buffer-live-p output-buffer)))
          (kill-buffer output-buffer))
        (message "Stopped connecting to mac-mini"))
    (message "No mac-mini connection attempt is running")))

(defun my/dirvish-visit-place (path)
  "Open PATH in Dirvish, preparing removable or network storage first."
  (let ((normalized-path (directory-file-name (expand-file-name path))))
    (cond
     ((equal normalized-path
             (directory-file-name my/mac-mini-mount-directory))
      (my/dirvish-open-mac-mini))
     ((equal normalized-path
             (directory-file-name my/android-mount-directory))
      (my/run-android-phone-async "mount"))
     (t
      (dirvish-dwim path)))))

(defun my/dirvish-mount-android ()
  "Mount the connected Android phone and open it in Dirvish."
  (interactive)
  (my/dirvish-visit-place my/android-mount-directory))

(defun my/dirvish-unmount-android ()
  "Leave and unmount the Android phone filesystem."
  (interactive)
  (dirvish-dwim (expand-file-name "~/"))
  (my/run-android-phone-async "unmount"))

(defun my/dirvish-cancel-background-operation ()
  "Cancel the current background mount or connection operation."
  (interactive)
  (cond
   ((process-live-p my/android-phone-process)
    (let ((process my/android-phone-process))
      (setq my/android-phone-process nil)
      (process-put process 'cancelled t)
      (delete-process process)))
   ((process-live-p my/mac-mini-connect-process)
    (my/dirvish-cancel-mac-mini-connect))
   (t
    (message "No background mount or connection is running"))))

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
  (setq auto-revert-verbose nil
        auto-revert-remote-files nil
        auto-revert-avoid-polling t)
  (put 'dired-find-alternate-file 'disabled nil))

(defun my/dired-async-message (format-string _face &rest arguments)
  "Report a Dired async message without pausing the Emacs event loop."
  (apply #'message format-string arguments))

(defun my/dired-async-track-process (process operation total)
  "Track Dired async PROCESS performing OPERATION on TOTAL files."
  (my/async-task-register
   (format "%s %d file%s"
           operation total (if (= total 1) "" "s"))
   'dired
   :detail (abbreviate-file-name default-directory)
   :process process
   :buffer (process-buffer process)
   :cancel-function #'my/dired-async-cancel-task))

(defun my/dired-async-cancel-task (task)
  "Cancel the Dired async process belonging to TASK."
  (when-let* ((process (my/async-task-process task))
              ((process-live-p process)))
    (process-put process 'cancelled t)
    (delete-process process)
    (unless (dired-async-processes)
      (dired-async--modeline-mode -1))))

(defun my/dired-async-track-finish (orig total operation failures skipped)
  "Update the dashboard after Dired async callback ORIG finishes."
  (prog1
      (funcall orig total operation failures skipped)
    (when-let* (((boundp 'async-current-process))
                (process async-current-process)
                (task (my/async-task-for-process process)))
      (when (and failures (boundp 'dired-log-buffer))
        (setf (my/async-task-buffer task) (get-buffer dired-log-buffer)))
      (cond
       (failures
        (my/async-task-fail
         task (format "%d of %d failed" (length failures) total)))
       (skipped
        (my/async-task-complete
         task (format "%d of %d skipped" (length skipped) total)))
       (operation
        (my/async-task-complete task))))))

(defun my/dired-async-track-start (orig file-creator operation files
                                        name-constructor &rest arguments)
  "Track the process created by Dired async function ORIG."
  (let ((before (process-list)))
    (prog1
        (apply orig file-creator operation files name-constructor arguments)
      (when-let* ((process
                   (seq-find
                    (lambda (candidate)
                      (and (not (memq candidate before))
                           (process-get candidate 'dired-async-process)))
                    (process-list))))
        (my/dired-async-track-process process operation (length files))))))

(use-package dired-async
  :demand t
  :custom
  (dired-async-log-file
   (expand-file-name "dired-async.log" my/emacs-cache-dir))
  (dired-async-message-function #'my/dired-async-message)
  (dired-async-mode-lighter nil)
  (dired-async-skip-fast nil)
  (dired-async-small-file-max (* 4 1024 1024))
  :config
  (advice-add #'dired-async-create-files
              :around #'my/dired-async-track-start)
  (advice-add #'dired-async-after-file-create
              :around #'my/dired-async-track-finish)
  (dired-async-mode 1))

(use-package dirvish
  :init
  (dirvish-override-dired-mode)
  :custom
  (dirvish-attributes
   '(vc-state subtree-state nerd-icons collapse file-time file-size))
  (dirvish-cache-dir
   (expand-file-name "dirvish/" my/emacs-cache-dir))
  (dirvish-default-layout '(1 0.15 0.55))
  (dirvish-large-directory-threshold 20000)
  (dirvish-input-debounce 0.03)
  (dirvish-input-throttle 0.15)
  (dirvish-preview-large-file-threshold (* 512 1024))
  (dirvish-preview-buffers-max-count 3)
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
   ("C-c C-k" . my/dirvish-cancel-background-operation)
   ("C-c C-u" . my/dirvish-unmount-android)
   ("C-c C-d" . my/dirvish-drag-files)
   ("C-c C-t" . my/dirvish-open-in-thunar)))

(with-eval-after-load 'dired
  (define-key dired-mode-map [remap dired-do-copy] #'dired-async-do-copy)
  (define-key dired-mode-map [remap dired-do-hardlink] #'dired-async-do-hardlink)
  (define-key dired-mode-map [remap dired-do-rename] #'dired-async-do-rename)
  (define-key dired-mode-map [remap dired-do-symlink] #'dired-async-do-symlink))

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
     ("m" ,my/mac-mini-mount-directory "mac-mini (SMB)")
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
