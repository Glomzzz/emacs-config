;;; mounts.el --- Android and Mac-mini mount helpers -*- lexical-binding: t; -*-

(require 'subr-x)
(require 'locations)

(declare-function dired-dwim-target-directory "dired" ())
(declare-function dired-get-marked-files "dired"
                  (&optional localp arg filter distinguish-one-marked error))
(declare-function dirvish-dwim "dirvish" (&optional path))
(declare-function dirvish-rsync "dirvish-rsync" (dest))
(declare-function task-dashboard-track-process "task-dashboard"
                  (process &rest arguments))
(declare-function task-dashboard-cancel-process "task-dashboard" (process))
(defvar dirvish-yank-sources)

(defgroup mounts nil
  "External commands for removable/network mounts."
  :group 'locations)

(defcustom mounts/android-command '("android-phone")
  "Command and initial arguments for Android mount/unmount actions."
  :type '(repeat string) :group 'mounts)
(defcustom mounts/mac-mini-connect-command '("mac-mini-connect")
  "Command and arguments for connecting the Mac-mini share."
  :type '(repeat string) :group 'mounts)

(defun mounts/resolve-command (command)
  "Resolve COMMAND's executable, preserving its arguments."
  (unless (and (consp command) (seq-every-p #'stringp command))
    (user-error "Mount command must be a non-empty list of strings"))
  (cons (or (executable-find (car command))
            (user-error "Mount executable is not installed: %s" (car command)))
        (cdr command)))

(defvar mounts/android-phone-process nil)
(defvar mounts/mac-mini-connect-process nil)

(defun mounts--process-output (process)
  "Return trimmed output captured by PROCESS, when available."
  (let ((buffer (process-buffer process)))
    (if (buffer-live-p buffer)
        (with-current-buffer buffer
          (string-trim (buffer-string)))
      "")))

(defun mounts--finish-message (action status details)
  "Return a useful completion message for mount ACTION and STATUS."
  (cond
   ((zerop status)
    (format "%s complete" (capitalize action)))
   ((string-empty-p details)
    (format "%s failed" (capitalize action)))
   (t
    (format "%s failed: %s" (capitalize action) details))))

(defun mounts--open-after-mount (process path action)
  "Open PATH after successful mount ACTION started by PROCESS."
  (let ((target-window (process-get process 'mounts-target-window))
        (source-buffer (process-get process 'mounts-source-buffer)))
    (if (and (window-live-p target-window)
             (eq (window-buffer target-window) source-buffer))
        (with-selected-window target-window
          (dirvish-dwim path))
      (message "%s is ready; use Dirvish quick access again"
               (capitalize action)))))

(defun mounts--android-sentinel (process _event)
  "Handle completion of the Android helper PROCESS."
  (when (and (memq (process-status process) '(exit signal))
             (not (process-get process 'mounts-handled)))
    (process-put process 'mounts-handled t)
    (let* ((status (process-exit-status process))
           (action (process-get process 'mounts-action))
           (details (mounts--process-output process))
           (cancelled (process-get process 'mounts-cancelled)))
      (when (eq process mounts/android-phone-process)
        (setq mounts/android-phone-process nil))
      (unwind-protect
          (cond
           (cancelled
            (message "Stopped Android phone operation"))
           ((zerop status)
            (if (string-equal action "mount")
                (progn
                  (mounts--open-after-mount
                   process mounts/android-mount-directory "Android phone")
                  (message "Android phone mounted"))
              (message "Android phone unmounted")))
           (t
            (message "%s"
                     (mounts--finish-message
                      (format "Android phone %s" action) status details))))
        (let ((buffer (process-buffer process)))
          (when (buffer-live-p buffer)
            (kill-buffer buffer)))))))

(defun mounts--run-android-phone (action)
  "Run the Android helper with ACTION without blocking Emacs."
  (if (process-live-p mounts/android-phone-process)
      (message "An Android phone operation is already running")
    (let ((command (mounts/resolve-command mounts/android-command))
          (output-buffer (generate-new-buffer " *android-phone*")))
      (let ((process
             (condition-case error-data
                 (make-process
                  :name "android-phone"
                  :buffer output-buffer
                  :command (append command (list action))
                  :connection-type 'pipe
                  :noquery t
                  :sentinel #'mounts--android-sentinel)
               (error
                (kill-buffer output-buffer)
                (signal (car error-data) (cdr error-data))))))
        (setq mounts/android-phone-process process)
        (process-put process 'mounts-action action)
        (process-put process 'mounts-target-window (selected-window))
        (process-put process 'mounts-source-buffer (current-buffer))
        (require 'task-dashboard)
        (task-dashboard-track-process
         process
         :label (format "%s Android phone"
                        (if (string-equal action "mount") "Mount" "Unmount"))
         :directory (expand-file-name "~/"))
        (unless (process-live-p process)
          (mounts--android-sentinel process "finished\n"))
        (message "%s Android phone... use C-c C-k to cancel"
                 (if (string-equal action "mount") "Mounting" "Unmounting"))
        process))))

(defun mounts--mac-mini-sentinel (process _event)
  "Handle completion of the Mac-mini connector PROCESS."
  (when (and (memq (process-status process) '(exit signal))
             (not (process-get process 'mounts-handled)))
    (process-put process 'mounts-handled t)
    (let* ((status (process-exit-status process))
           (details (mounts--process-output process))
           (cancelled (process-get process 'mounts-cancelled)))
      (when (eq process mounts/mac-mini-connect-process)
        (setq mounts/mac-mini-connect-process nil))
      (unwind-protect
          (cond
           (cancelled
            (message "Stopped connecting to mac-mini"))
           ((zerop status)
            (mounts--open-after-mount
             process mounts/mac-mini-mount-directory "mac-mini")
            (message "mac-mini connected"))
           (t
            (message "%s"
                     (mounts--finish-message
                      "mac-mini connection" status details))))
        (let ((buffer (process-buffer process)))
          (when (buffer-live-p buffer)
            (kill-buffer buffer)))))))

(defun mounts--connect-mac-mini ()
  "Connect to Mac-mini asynchronously, then open it in Dirvish."
  (if (process-live-p mounts/mac-mini-connect-process)
      (message "Already connecting to mac-mini")
    (let ((command (mounts/resolve-command mounts/mac-mini-connect-command))
          (output-buffer (generate-new-buffer " *mac-mini connector*")))
      (let ((process
             (condition-case error-data
                 (let ((default-directory (expand-file-name "~/")))
                   (make-process
                    :name "mac-mini connector"
                    :buffer output-buffer
                    :command command
                    :connection-type 'pipe
                    :noquery t
                    :sentinel #'mounts--mac-mini-sentinel))
               (error
                (kill-buffer output-buffer)
                (signal (car error-data) (cdr error-data))))))
        (setq mounts/mac-mini-connect-process process)
        (process-put process 'mounts-target-window (selected-window))
        (process-put process 'mounts-source-buffer (current-buffer))
        (require 'task-dashboard)
        (task-dashboard-track-process
         process
         :label "Connect to mac-mini"
         :directory (expand-file-name "~/"))
        (unless (process-live-p process)
          (mounts--mac-mini-sentinel process "finished\n"))
        (message "Connecting to mac-mini... use C-c C-k to cancel")
        process))))

(defun mounts--cancel-process (process)
  "Cancel PROCESS while preserving its dashboard cancellation state."
  (when (process-live-p process)
    (process-put process 'mounts-cancelled t)
    (when (fboundp 'task-dashboard-cancel-process)
      (task-dashboard-cancel-process process))
    (delete-process process)))

(defun mounts/cancel-background-operation ()
  "Cancel the current Android mount or Mac-mini connection."
  (interactive)
  (cond
   ((process-live-p mounts/android-phone-process)
    (let ((process mounts/android-phone-process))
      (setq mounts/android-phone-process nil)
      (mounts--cancel-process process)))
   ((process-live-p mounts/mac-mini-connect-process)
    (let ((process mounts/mac-mini-connect-process))
      (setq mounts/mac-mini-connect-process nil)
      (mounts--cancel-process process)))
   (t
    (message "No background mount or connection is running"))))

(defun mounts/visit-place (path)
  "Open PATH in Dirvish, preparing removable or network storage first."
  (let ((normalized-path (directory-file-name (expand-file-name path))))
    (cond
     ((equal normalized-path
             (directory-file-name (expand-file-name mounts/mac-mini-mount-directory)))
      (mounts--connect-mac-mini))
     ((equal normalized-path
             (directory-file-name (expand-file-name mounts/android-mount-directory)))
      (mounts--run-android-phone "mount"))
     (t
      (dirvish-dwim path)))))

(defun mounts/mount-android ()
  "Mount the connected Android phone and open it in Dirvish."
  (interactive)
  (mounts/visit-place mounts/android-mount-directory))

(defun mounts/unmount-android ()
  "Leave Dirvish and unmount the Android phone filesystem."
  (interactive)
  (dirvish-dwim (expand-file-name "~/"))
  (mounts--run-android-phone "unmount"))

(defun mounts/mac-mini-relative-path (path)
  "Return PATH relative to Mac-mini, or nil when outside its mount.

Local canonicalisation prevents a symlink outside the mount from being
classified as a Mac-mini destination, while avoiding TRAMP network I/O."
  (when (and path (not (file-remote-p path)))
    (condition-case nil
        (let ((relative
               (file-relative-name
                (file-truename (expand-file-name path))
                (file-name-as-directory
                 (file-truename mounts/mac-mini-mount-directory)))))
          (unless (or (equal relative "..")
                      (string-prefix-p "../" relative))
            (if (equal relative "./") "" relative)))
      (file-error nil))))

(defun mounts/mac-mini-mounted-p ()
  "Return non-nil when Mac-mini is an actual mounted filesystem."
  (when-let* ((program (executable-find "mountpoint")))
    (condition-case nil
        (zerop (call-process program nil nil nil "-q"
                             (expand-file-name mounts/mac-mini-mount-directory)))
      (file-error nil))))

(defun mounts/mac-mini-rsync-destination (path)
  "Convert local Mac-mini PATH to its SSH TRAMP directory."
  (when-let* ((relative (mounts/mac-mini-relative-path path)))
    (concat "/ssh:" mounts/mac-mini-host ":"
            (file-name-as-directory mounts/mac-mini-remote-home-directory)
            (if (string-empty-p relative) "" (file-name-as-directory relative)))))

(defun mounts/rsync-to-mac-mini (&optional destination)
  "Rsync marked files to Mac-mini DESTINATION."
  (interactive)
  (unless (mounts/mac-mini-mounted-p)
    (user-error "Mac-mini is not mounted: %s"
                mounts/mac-mini-mount-directory))
  (let* ((sources (dired-get-marked-files))
         (suggested (or destination (dired-dwim-target-directory)))
         (local-destination
          (if (mounts/mac-mini-relative-path suggested)
              suggested
            (read-directory-name "mac-mini destination: "
                                 mounts/mac-mini-mount-directory nil t)))
         (remote-destination
          (mounts/mac-mini-rsync-destination local-destination)))
    (unless remote-destination
      (user-error "Destination is outside the mac-mini mount"))
    (unless (require 'dirvish-rsync nil t)
      (user-error "Dirvish rsync extension is unavailable"))
    (let ((dirvish-yank-sources (lambda () sources)))
      (dirvish-rsync remote-destination))))

;;; mounts.el ends here
