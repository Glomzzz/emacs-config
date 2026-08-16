;;; mounts.el --- Android and mac-mini mount helpers with rsync -*- lexical-binding: t; -*-

(require 'cl-lib)

(declare-function dired-dwim-target-directory "dired" ())
(declare-function dired-get-marked-files "dired"
                  (&optional localp arg filter distinguish-one-marked error))
(declare-function dirvish-dwim "dirvish" (path))
(declare-function my/async-task-cancelled "apps/async-tasks" (task &optional detail))
(declare-function my/async-task-complete "apps/async-tasks" (task &optional detail))
(declare-function my/async-task-fail "apps/async-tasks" (task &optional detail))
(declare-function my/async-task-for-process "apps/async-tasks" (process))
(declare-function my/async-task-register "apps/async-tasks" (name kind &rest properties))

(defconst my/android-mount-directory
  (expand-file-name "~/mnt/android/"))

(defconst my/mac-mini-mount-directory
  (expand-file-name "~/mnt/mac-mini/"))

(defconst my/mac-mini-remote-home-directory "/Users/glom/")

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

(defun my/mac-mini-relative-path (path)
  "Return PATH relative to the mac-mini mount, or nil when it is outside."
  (let ((relative
         (file-relative-name (expand-file-name path)
                             my/mac-mini-mount-directory)))
    (unless (or (equal relative "..")
                (string-prefix-p "../" relative))
      (if (equal relative "./") "" relative))))

(defun my/mac-mini-rsync-destination (path)
  "Convert local mac-mini mount PATH to its SSH TRAMP directory."
  (when-let* ((relative (my/mac-mini-relative-path path)))
    (concat "/ssh:mac-mini:"
            (file-name-as-directory
             (expand-file-name relative my/mac-mini-remote-home-directory)))))

(defun my/dirvish-rsync-to-mac-mini (&optional destination)
  "Rsync marked files to a mac-mini DESTINATION with live progress."
  (interactive)
  (let* ((sources (dired-get-marked-files))
         (suggested (or destination (dired-dwim-target-directory)))
         (local-destination
          (if (my/mac-mini-relative-path suggested)
              suggested
            (read-directory-name "mac-mini destination: "
                                 my/mac-mini-mount-directory nil t)))
         (remote-destination
          (my/mac-mini-rsync-destination local-destination)))
    (unless remote-destination
      (user-error "Destination is outside the mac-mini mount"))
    (require 'dirvish-rsync)
    (let ((dirvish-yank-sources (lambda () sources)))
      (dirvish-rsync remote-destination))))

;;; mounts.el ends here
