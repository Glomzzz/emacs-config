;;; task-dashboard.el --- Asynchronous process task dashboard -*- lexical-binding: t; -*-

;; This package deliberately uses Emacs' process primitives instead of a
;; package-specific worker abstraction.  External processes can be paused,
;; resumed, and cancelled with OS signals, while their output remains useful
;; in an ordinary Emacs buffer.

(require 'cl-lib)
(require 'subr-x)
(require 'tabulated-list)

(declare-function async-start "async" (start-func &optional finish-func))
(defvar async-process-noquery-on-exit)

(defgroup task-dashboard nil
  "Run and monitor asynchronous external tasks."
  :group 'processes
  :prefix "task-dashboard-")

(defcustom task-dashboard-refresh-interval 0.5
  "Seconds between dashboard refreshes."
  :type 'number
  :group 'task-dashboard)

(defcustom task-dashboard-cancel-grace-period 2.0
  "Seconds to wait after SIGTERM before sending SIGKILL."
  :type 'number
  :group 'task-dashboard)

(defcustom task-dashboard-progress-bar-width 10
  "Number of cells used by the progress bar in the dashboard."
  :type 'integer
  :group 'task-dashboard)

(defconst task-dashboard--terminal-statuses
  '(completed failed cancelled)
  "Task statuses that cannot transition back to an active state.")

(cl-defstruct (task-dashboard-task
               (:constructor task-dashboard--make-task))
  "A task managed by `task-dashboard'."
  id label command process output-buffer status progress progress-function
  start-time end-time exit-code error directory scan-tail cancel-requested
  cancel-timer kind result completion-function)

(defvar task-dashboard--tasks nil
  "Tasks known to the current Emacs session, newest tasks at the end.")

(defvar task-dashboard--next-id 0
  "Next numeric task identifier.")

(defvar task-dashboard--dashboard-buffer "*Task Dashboard*"
  "Name of the task dashboard buffer.")

(defvar task-dashboard--refresh-timer nil
  "Timer used to refresh live task dashboard buffers.")

(defun task-dashboard--task-live-p (task)
  "Return non-nil when TASK has a live process."
  (and (task-dashboard-task-p task)
       (process-live-p (task-dashboard-task-process task))))

(defun task-dashboard--task-command-label (command)
  "Return a readable label for COMMAND, a list of process arguments."
  (mapconcat #'identity command " "))

(defun task-dashboard--normalise-label (label command)
  "Return a single-line display label for LABEL and COMMAND."
  (replace-regexp-in-string
   "[\r\n]" " "
   (format "%s" (or label (task-dashboard--task-command-label command)))))

(defun task-dashboard--normalise-command (command)
  "Validate and copy COMMAND for `make-process'."
  (unless (and (listp command)
               command
               (cl-every #'stringp command))
    (user-error "COMMAND must be a non-empty list of strings"))
  (copy-sequence command))

(defun task-dashboard--normalise-directory (directory &optional allow-remote)
  "Return an absolute DIRECTORY, or signal a user error.

When ALLOW-REMOTE is non-nil, a TRAMP directory is accepted without probing
the remote host.  This keeps observing an already-running remote process from
triggering authentication or network I/O in the parent Emacs."
  (let* ((directory (file-name-as-directory
                     (expand-file-name (or directory default-directory))))
         (remote (file-remote-p directory)))
    (unless (or (and allow-remote remote)
                (file-directory-p directory))
      (user-error "Task directory does not exist: %s" directory))
    directory))

(defun task-dashboard--default-directory ()
  "Return the current project root when available, else `default-directory'."
  (or (ignore-errors
        (when (fboundp 'project-current)
          (let ((project (project-current nil)))
            (when (and project (fboundp 'project-root))
              (project-root project)))))
      default-directory))

(defun task-dashboard--output-buffer-name (task)
  "Return a useful output buffer name for TASK."
  (format "*Task %d: %s*"
          (task-dashboard-task-id task)
          (task-dashboard-task-label task)))

(defun task-dashboard--make-output-buffer (task)
  "Create and configure TASK's output buffer."
  (let ((buffer (generate-new-buffer
                 (task-dashboard--output-buffer-name task))))
    (with-current-buffer buffer
      (special-mode)
      (setq-local buffer-read-only t)
      (setq-local truncate-lines nil)
      (setq buffer-file-coding-system 'utf-8-unix)
      (set-buffer-modified-p nil))
    buffer))

(defun task-dashboard--notify (title body &optional severity)
  "Notify the user with TITLE and BODY, using available notification APIs."
  (require 'notifications nil t)
  (require 'alert nil t)
  (let ((notified nil))
    (when (fboundp 'notifications-notify)
      (setq notified
            (condition-case nil
                (progn
                  (notifications-notify :title title
                                        :body body
                                        :urgency (or severity 'normal))
                  t)
              (error nil))))
    (when (and (not notified) (fboundp 'alert))
      (setq notified
            (condition-case nil
                (progn
                  (alert body
                        :title title
                        :severity (if (eq severity 'critical)
                                      'urgent
                                    (or severity 'normal)))
                  t)
              (error nil))))
    (unless notified
      (message "%s: %s" title body))))

(defun task-dashboard--refresh-all ()
  "Refresh every live task dashboard buffer."
  (dolist (buffer (buffer-list))
    (when (buffer-live-p buffer)
      (with-current-buffer buffer
        (when (derived-mode-p 'task-dashboard-mode)
          (task-dashboard-refresh))))))

(defun task-dashboard--append-output (task output)
  "Append OUTPUT to TASK's output buffer, preserving a user's point."
  (let ((buffer (task-dashboard-task-output-buffer task)))
    (when (and (buffer-live-p buffer) (stringp output))
      (with-current-buffer buffer
        (let ((at-end (= (point) (point-max)))
              (inhibit-read-only t))
          (goto-char (point-max))
          (insert output)
          (set-buffer-modified-p nil)
          (when at-end
            (goto-char (point-max))))))))

(defun task-dashboard--progress-value (text)
  "Return the last progress value found in TEXT, or nil.

Recognised forms include `42%', `progress: 42', and `12/100'.  The
returned value is a percentage in the range 0..100."
  (let ((patterns
         `(("\\b\\([0-9]+\\(?:\\.[0-9]+\\)?\\)[ \t]*%"
            . percent)
           ("\\bprogress\\(?:[ \t_-]*\\(?:percent\\|pct\\)\\)?[ \t]*[:=][ \t]*\\([0-9]+\\(?:\\.[0-9]+\\)?\\)"
            . percent)
           ("\\b\\([0-9]+\\)[ \t]*/[ \t]*\\([0-9]+\\)\\b"
            . ratio)))
        (best-position -1)
        (best-value nil))
    (dolist (pattern patterns)
      (let ((start 0)
            (regexp (car pattern))
            (kind (cdr pattern)))
        (while (string-match regexp text start)
          (let ((position (match-beginning 0))
                (value
                 (if (eq kind 'ratio)
                     (let ((done (string-to-number (match-string 1 text)))
                           (total (string-to-number (match-string 2 text))))
                       (and (> total 0) (/ (* 100.0 done) total)))
                   (string-to-number (match-string 1 text)))))
            (when (and value (> position best-position))
              (setq best-position position
                    best-value (max 0.0 (min 100.0 value))))
            (setq start (match-end 0))))))
    best-value))

(defun task-dashboard--parse-progress (task output)
  "Update TASK's progress from OUTPUT, retaining a short split-line tail."
  (let* ((tail (or (task-dashboard-task-scan-tail task) ""))
         (text (concat tail (if (stringp output) output "")))
         (progress (task-dashboard--progress-value text)))
    (when progress
      (setf (task-dashboard-task-progress task) progress))
    (setf (task-dashboard-task-scan-tail task)
          (if (> (length text) 256)
              (substring text (- (length text) 256))
            text))))

(defun task-dashboard--process-filter (process output)
  "Store PROCESS OUTPUT and update its task progress."
  (let ((task (process-get process 'task-dashboard-task)))
    (when (task-dashboard-task-p task)
      (when (stringp output)
        (task-dashboard--append-output task output)
        (task-dashboard--parse-progress task output))
      (task-dashboard--refresh-all))))

(defun task-dashboard--cancel-timer (task)
  "Cancel TASK's pending force-kill timer, if any."
  (when (timerp (task-dashboard-task-cancel-timer task))
    (cancel-timer (task-dashboard-task-cancel-timer task)))
  (setf (task-dashboard-task-cancel-timer task) nil))

(defun task-dashboard--run-completion-function (task result)
  "Run TASK's optional completion callback with RESULT.

Completion callbacks are deliberately isolated from task state changes: an
error in a callback is reported but does not turn an already completed task
into a failed one."
  (let ((function (task-dashboard-task-completion-function task)))
    (when function
      (setf (task-dashboard-task-completion-function task) nil)
      (condition-case error
          (funcall function task result)
        (error
         (message "Task %d completion callback failed: %s"
                  (task-dashboard-task-id task)
                  (error-message-string error)))))))

(defun task-dashboard--async-handle-message (task message)
  "Handle an `async.el' MESSAGE belonging to TASK."
  (let ((progress (plist-get message :progress))
        (text (or (plist-get message :message)
                  (plist-get message :text)
                  (and (plist-get message :status)
                       (format "%s" (plist-get message :status))))))
    (when (numberp progress)
      (setf (task-dashboard-task-progress task)
            (max 0.0 (min 100.0 progress))))
    (when (stringp text)
      (task-dashboard--append-output task (concat text "\n")))
    (task-dashboard--refresh-all)))

(defun task-dashboard--finish-async-task (task result)
  "Finish TASK from an `async.el' RESULT packet."
  (unless (memq (task-dashboard-task-status task)
                task-dashboard--terminal-statuses)
    (let* ((wrapped (and (listp result)
                         (plist-get result :task-dashboard-result)))
           (failed (and (listp result)
                        (plist-get result :task-dashboard-error)))
           (error-text (and failed
                            (or (plist-get result :error)
                                "Async task failed")))
           (cancelled (task-dashboard-task-cancel-requested task)))
      (setf (task-dashboard-task-end-time task) (current-time)
            (task-dashboard-task-result task) result
            (task-dashboard-task-exit-code task) (if (or failed cancelled) 1 0))
      (cond
       (cancelled
        (setf (task-dashboard-task-status task) 'cancelled
              (task-dashboard-task-error task) nil)
        (task-dashboard--notify
         (format "Task %d cancelled" (task-dashboard-task-id task))
         (task-dashboard-task-label task)
         'low))
       (failed
        (setf (task-dashboard-task-status task) 'failed
              (task-dashboard-task-error task) (format "%s" error-text))
        (task-dashboard--append-output
         task
         (format "Async task failed: %s\n" error-text))
        (task-dashboard--notify
         (format "Task %d failed" (task-dashboard-task-id task))
         (format "%s (%s)"
                 (task-dashboard-task-label task)
                 error-text)
         'critical))
       (t
        (setf (task-dashboard-task-status task) 'completed
              (task-dashboard-task-error task) nil
              (task-dashboard-task-progress task) 100.0)
        (task-dashboard--notify
         (format "Task %d complete" (task-dashboard-task-id task))
         (task-dashboard-task-label task))))
      ;; Keep the wrapper marker available to completion callbacks.  For a
      ;; plain async result, RESULT itself is still useful to callers.
      (unless wrapped
        (setf (task-dashboard-task-result task) result))
      (task-dashboard--run-completion-function task result)
      (task-dashboard--refresh-all))))

(defun task-dashboard--async-process-sentinel (process event)
  "Finalize an async TASK when its child process is interrupted."
  (let ((task (process-get process 'task-dashboard-task)))
    (when (and (task-dashboard-task-p task)
               (memq (process-status process) '(exit signal failed closed))
               (not (memq (task-dashboard-task-status task)
                          task-dashboard--terminal-statuses)))
      (if (task-dashboard-task-cancel-requested task)
          (task-dashboard--finish-async-task
           task
           (list :task-dashboard-error t
                 :error "Async task cancelled"))
        (task-dashboard--finish-async-task
         task
         (list :task-dashboard-error t
               :error (format "Async process ended: %s"
                              (string-trim (or event "")))))))))

(defun task-dashboard--install-async-sentinel (process)
  "Preserve PROCESS's async sentinel and add task lifecycle tracking."
  (let ((sentinel (process-sentinel process)))
    (set-process-sentinel
     process
     (lambda (proc event)
       (condition-case error
           (when sentinel
             (funcall sentinel proc event))
         (error
          (message "Async process sentinel failed: %s"
                   (error-message-string error))))
       (task-dashboard--async-process-sentinel proc event)))))

;;;###autoload
(cl-defun task-dashboard-run-async (start-fn
                                    &key label directory on-complete)
  "Run START-FN in an `async.el' child and track it in the dashboard.

START-FN must be a function that can be serialized by `async-start'.  The
function may call `async-send' with `:progress' (0..100) and `:message' keys;
those updates are shown in the dashboard and task output buffer.  ON-COMPLETE
is called with the task record and the raw result packet after completion or
failure."
  (unless (functionp start-fn)
    (signal 'wrong-type-argument (list 'functionp start-fn)))
  (require 'async)
  (let* ((directory (task-dashboard--normalise-directory
                     (or directory default-directory)))
         (task (task-dashboard--make-task
                :id (cl-incf task-dashboard--next-id)
                :label (task-dashboard--normalise-label
                        (or label "Async task") nil)
                :status 'queued
                :directory directory
                :start-time (current-time)
                :kind 'async
                :completion-function on-complete
                :scan-tail ""))
         process)
    (setf (task-dashboard-task-output-buffer task)
          (task-dashboard--make-output-buffer task))
    (setq task-dashboard--tasks (append task-dashboard--tasks (list task)))
    (condition-case error
        (let ((default-directory directory)
              (async-process-noquery-on-exit t))
          (setq process
                 (async-start
                 (lambda ()
                   (condition-case child-error
                       (let ((value (funcall start-fn)))
                         ;; A worker can return a reserved error packet while
                         ;; still providing a useful value for its callback.
                         ;; Flatten that packet at the process boundary so the
                         ;; dashboard sees the failure and callers see the
                         ;; worker's detailed value in `:value'.
                         (if (and (listp value)
                                  (plist-get value :task-dashboard-error))
                             (list :task-dashboard-result t
                                   :task-dashboard-error t
                                   :error (or (plist-get value :error)
                                              "Async task failed")
                                   :value (if (plist-member value :value)
                                               (plist-get value :value)
                                             value))
                           (list :task-dashboard-result t
                                 :value value)))
                     (error
                      (list :task-dashboard-error t
                            :error (error-message-string child-error)))))
                 (lambda (result)
                   (if (and (fboundp 'async-message-p)
                            (async-message-p result))
                       (task-dashboard--async-handle-message task result)
                     (task-dashboard--finish-async-task task result))))))
      (error
       (setf (task-dashboard-task-status task) 'failed
             (task-dashboard-task-end-time task) (current-time)
             (task-dashboard-task-exit-code task) 1
             (task-dashboard-task-error task) (error-message-string error))
       (task-dashboard--append-output
        task
        (format "Could not start async task: %s\n"
                (error-message-string error)))
       (task-dashboard--notify
        (format "Task %d failed to start" (task-dashboard-task-id task))
        (format "%s (%s)"
                (task-dashboard-task-label task)
                (error-message-string error))
        'critical)
       (task-dashboard--run-completion-function
        task
        (list :task-dashboard-error t
              :error (error-message-string error)))))
    (when process
      (setf (task-dashboard-task-process task) process
            (task-dashboard-task-status task) 'running)
      (process-put process 'task-dashboard-task task)
      (task-dashboard--install-async-sentinel process)
      (task-dashboard--notify
       (format "Task %d started" (task-dashboard-task-id task))
       (task-dashboard-task-label task)))
    (task-dashboard--refresh-all)
    task))

(defun task-dashboard--task-finish (task process event)
  "Finalize TASK after PROCESS exits, using EVENT for failure details."
  (unless (memq (task-dashboard-task-status task)
                task-dashboard--terminal-statuses)
    (let* ((status (process-status process))
           (exit-code (process-exit-status process))
           (cancelled (task-dashboard-task-cancel-requested task))
           (event (string-trim (or event ""))))
      (setf (task-dashboard-task-end-time task) (current-time)
            (task-dashboard-task-exit-code task) exit-code)
      (cond
       (cancelled
        (setf (task-dashboard-task-status task) 'cancelled
              (task-dashboard-task-error task) nil)
        (task-dashboard--cancel-timer task)
        (task-dashboard--notify
         (format "Task %d cancelled" (task-dashboard-task-id task))
         (task-dashboard-task-label task)
         'low))
       ((and (eq status 'exit) (numberp exit-code) (zerop exit-code))
        (setf (task-dashboard-task-status task) 'completed
              (task-dashboard-task-error task) nil
              (task-dashboard-task-progress task) 100.0)
        (task-dashboard--cancel-timer task)
        (task-dashboard--notify
         (format "Task %d complete" (task-dashboard-task-id task))
         (task-dashboard-task-label task)))
       (t
        (setf (task-dashboard-task-status task) 'failed
              (task-dashboard-task-error task)
              (if (string-empty-p event)
                  (format "Process exited with status %s" exit-code)
                event))
        (task-dashboard--cancel-timer task)
        (task-dashboard--notify
         (format "Task %d failed" (task-dashboard-task-id task))
         (format "%s (%s)"
                 (task-dashboard-task-label task)
                 (task-dashboard-task-error task))
         'critical)))
      (task-dashboard--refresh-all))))

(defun task-dashboard--process-sentinel (process event)
  "Update the task associated with PROCESS when its state changes."
  (let ((task (process-get process 'task-dashboard-task)))
    (when (task-dashboard-task-p task)
      (pcase (process-status process)
        ('stop
         (unless (task-dashboard-task-cancel-requested task)
           (setf (task-dashboard-task-status task) 'paused))
         (task-dashboard--refresh-all))
        ((or 'run 'open)
         (when (eq (task-dashboard-task-status task) 'paused)
           (setf (task-dashboard-task-status task) 'running))
         (task-dashboard--refresh-all))
        ((or 'exit 'signal 'failed 'closed)
         (task-dashboard--task-finish task process event))))))

(defun task-dashboard--install-process-sentinel (process)
  "Preserve PROCESS's sentinel and add dashboard lifecycle tracking.

This is used for processes created by another asynchronous package, such as
`dired-async'.  The existing sentinel runs first so that the owning package
can perform its normal cleanup and buffer refresh."
  (unless (process-get process 'task-dashboard-sentinel-installed)
    (let ((sentinel (process-sentinel process)))
      (set-process-sentinel
       process
       (lambda (proc event)
         (condition-case error
             (when sentinel
               (funcall sentinel proc event))
           (error
            (message "Tracked process sentinel failed: %s"
                     (error-message-string error))))
         (task-dashboard--process-sentinel proc event)))
      (process-put process 'task-dashboard-sentinel-installed t))))

;;;###autoload
(cl-defun task-dashboard-track-process (process
                                        &key label directory progress-function)
  "Track an already-running asynchronous PROCESS in the dashboard.

PROCESS keeps its existing filter and sentinel; the dashboard wraps them so
the package that owns PROCESS retains its normal output and cleanup behavior.
This is intended for integrations such as `dired-async' whose work is already
asynchronous but would otherwise be absent from the dashboard.  When supplied,
PROGRESS-FUNCTION receives the task and may return a numeric percentage."
  (unless (processp process)
    (signal 'wrong-type-argument (list 'processp process)))
  (or (process-get process 'task-dashboard-task)
      (let* ((directory (task-dashboard--normalise-directory
                         (or directory default-directory)
                         t))
             (task (task-dashboard--make-task
                    :id (cl-incf task-dashboard--next-id)
                    :label (task-dashboard--normalise-label
                            (or label (process-name process)) nil)
                    :process process
                    :status (if (process-live-p process) 'running 'queued)
                    :directory directory
                    :start-time (current-time)
                    :progress-function progress-function
                    :kind 'adopted
                    :scan-tail "")))
        (setf (task-dashboard-task-output-buffer task)
              (task-dashboard--make-output-buffer task))
        (setq task-dashboard--tasks (append task-dashboard--tasks (list task)))
        (process-put process 'task-dashboard-task task)
        (if (process-live-p process)
            (task-dashboard--install-process-sentinel process)
          ;; A very short-lived process may finish before an observer gets a
          ;; chance to attach.  Finalise it immediately instead of leaving a
          ;; permanently queued row in the dashboard.
          (task-dashboard--task-finish task process ""))
        (task-dashboard--append-output
         task
         (format "Tracking existing process: %s\n"
                 (task-dashboard-task-label task)))
        (when (process-live-p process)
          (task-dashboard--notify
           (format "Task %d started" (task-dashboard-task-id task))
           (task-dashboard-task-label task)))
        (task-dashboard--refresh-all)
        task)))

(defun task-dashboard-cancel-process (process)
  "Mark the task associated with PROCESS as cancelled.

This is intended for integrations that own a process and need to terminate it
outside the dashboard's point-based interactive command.  The process owner
still decides how to signal or delete PROCESS; the dashboard sentinel will
then record the cancellation instead of reporting a failure."
  (when-let* ((task (process-get process 'task-dashboard-task)))
    (setf (task-dashboard-task-cancel-requested task) t)
    task))

(defun task-dashboard--force-cancel (task)
  "Escalate cancellation of TASK to SIGKILL when it is still running."
  (setf (task-dashboard-task-cancel-timer task) nil)
  (when (and (eq (task-dashboard-task-status task) 'cancelling)
             (task-dashboard--task-live-p task))
    (let ((process (task-dashboard-task-process task)))
      (condition-case error
          (signal-process process 'SIGKILL)
        (error
         (ignore-errors (delete-process process))
         (setf (task-dashboard-task-error task)
               (error-message-string error))))))
  (when (and (eq (task-dashboard-task-status task) 'cancelling)
             (not (task-dashboard--task-live-p task)))
    (task-dashboard--task-finish
     task
     (task-dashboard-task-process task)
     "cancelled")))

(defun task-dashboard--start-process (task)
  "Start TASK's process and install its filter and sentinel."
  (let ((default-directory (task-dashboard-task-directory task))
        (output-buffer (task-dashboard-task-output-buffer task)))
    (condition-case error
        (let ((process
               (make-process
                :name (format "task-dashboard-%d"
                              (task-dashboard-task-id task))
                :command (task-dashboard-task-command task)
                :buffer output-buffer
                :filter #'task-dashboard--process-filter
                :sentinel #'task-dashboard--process-sentinel
                :noquery t
                :coding 'utf-8-unix
                :connection-type 'pipe)))
          (setf (task-dashboard-task-process task) process
                (task-dashboard-task-status task) 'running
                (task-dashboard-task-start-time task) (current-time))
          (process-put process 'task-dashboard-task task)
          (task-dashboard--notify
           (format "Task %d started" (task-dashboard-task-id task))
           (task-dashboard-task-label task))
          (task-dashboard--refresh-all)
          task)
      (error
       (setf (task-dashboard-task-status task) 'failed
             (task-dashboard-task-start-time task) (current-time)
             (task-dashboard-task-end-time task) (current-time)
             (task-dashboard-task-error task) (error-message-string error))
       (task-dashboard--append-output
        task
        (format "Could not start task: %s\n"
                (error-message-string error)))
       (task-dashboard--notify
        (format "Task %d failed to start" (task-dashboard-task-id task))
        (format "%s (%s)"
                (task-dashboard-task-label task)
                (error-message-string error))
        'critical)
       (task-dashboard--refresh-all)
       task))))

;;;###autoload
(cl-defun task-dashboard-run (command &key label directory)
  "Run COMMAND asynchronously and return its task record.

COMMAND is a non-empty list of program and argument strings.  LABEL and
DIRECTORY are optional keyword arguments; DIRECTORY defaults to the current
project root when available.  The task's output is collected in a dedicated
buffer and can be inspected from the dashboard."
  (let* ((command (task-dashboard--normalise-command command))
         (directory (task-dashboard--normalise-directory
                     (or directory (task-dashboard--default-directory))))
         (id (cl-incf task-dashboard--next-id))
         (task (task-dashboard--make-task
                :id id
                :label (task-dashboard--normalise-label label command)
                :command command
                :status 'queued
                :directory directory
                :scan-tail "")))
    (setf (task-dashboard-task-output-buffer task)
          (task-dashboard--make-output-buffer task))
    (setq task-dashboard--tasks (append task-dashboard--tasks (list task)))
    (task-dashboard--start-process task)))

;;;###autoload
(defun task-dashboard-run-shell-command (command &optional directory)
  "Run shell COMMAND asynchronously and return its task record.

When called interactively, COMMAND is read from the minibuffer and DIRECTORY
defaults to the current project root.  The shell is `shell-file-name' (or the
user's SHELL environment variable) and receives `shell-command-switch'."
  (interactive
   (list (read-shell-command "Async shell command: "
                             (and (boundp 'compile-command)
                                  compile-command))
         (task-dashboard--default-directory)))
  (let ((shell (or shell-file-name (getenv "SHELL") "/bin/sh"))
        (switch (or (and (boundp 'shell-command-switch)
                         shell-command-switch)
                    "-c"))
        (task nil))
    (setq task
          (task-dashboard-run (list shell switch command)
                              :label command
                              :directory directory))
    (when (called-interactively-p 'interactive)
      (task-dashboard))
    task))

(defun task-dashboard-tasks ()
  "Return a snapshot of all task records in the current session."
  (copy-sequence task-dashboard--tasks))

(defun task-dashboard-update-progress (task progress)
  "Set TASK's numeric PROGRESS percentage and refresh dashboards.

This is useful for callers that start a task through `task-dashboard-run' but
have progress information that is not printed by the child process."
  (unless (task-dashboard-task-p task)
    (signal 'wrong-type-argument (list 'task-dashboard-task-p task)))
  (unless (numberp progress)
    (signal 'wrong-type-argument (list 'numberp progress)))
  (setf (task-dashboard-task-progress task)
        (max 0.0 (min 100.0 progress)))
  (task-dashboard--refresh-all)
  (task-dashboard-task-progress task))

(defun task-dashboard--refresh-progress (task)
  "Refresh TASK's progress from its optional progress callback."
  (when (and (eq (task-dashboard-task-status task) 'running)
             (task-dashboard-task-progress-function task))
    (condition-case error-data
        (let ((progress
               (funcall (task-dashboard-task-progress-function task) task)))
          (when (numberp progress)
            (setf (task-dashboard-task-progress task)
                  (max 0.0 (min 100.0 progress)))))
      (error
       (when-let* ((process (task-dashboard-task-process task)))
         (unless (process-get process 'task-dashboard-progress-error-reported)
           (process-put process 'task-dashboard-progress-error-reported t)
           (message "Task %d progress callback failed: %s"
                    (task-dashboard-task-id task)
                    (error-message-string error-data))))))))

(defun task-dashboard--status-label (status)
  "Return a dashboard label for STATUS."
  (capitalize (symbol-name (or status 'unknown))))

(defun task-dashboard--progress-string (progress)
  "Return a fixed-width dashboard progress string for PROGRESS."
  (if (numberp progress)
      (let* ((width (max 1 task-dashboard-progress-bar-width))
             (filled (round (* width (/ progress 100.0))))
             (bar (concat (make-string filled ?#)
                          (make-string (max 0 (- width filled)) ?-))))
        (format "[%s] %3.0f%%" bar progress))
    (format "[%s]   -" (make-string (max 1 task-dashboard-progress-bar-width)
                                     ?-))))

(defun task-dashboard--elapsed-string (task)
  "Return TASK's elapsed runtime as HH:MM:SS."
  (let* ((start (task-dashboard-task-start-time task))
         (end (or (task-dashboard-task-end-time task) (current-time)))
         (seconds (if start
                      (max 0 (truncate (float-time (time-subtract end start))))
                    0))
         (hours (/ seconds 3600))
         (minutes (% (/ seconds 60) 60))
         (seconds (% seconds 60)))
    (format "%02d:%02d:%02d" hours minutes seconds)))

(defun task-dashboard--exit-string (task)
  "Return TASK's exit result for the dashboard."
  (cond
   ((eq (task-dashboard-task-status task) 'cancelled) "cancel")
   ((numberp (task-dashboard-task-exit-code task))
    (number-to-string (task-dashboard-task-exit-code task)))
   ((task-dashboard-task-error task) "error")
   (t "-")))

(defun task-dashboard--entries ()
  "Return `tabulated-list-entries' for the task dashboard."
  (mapcar
   (lambda (task)
     (task-dashboard--refresh-progress task)
     (list (task-dashboard-task-id task)
           (vector (number-to-string (task-dashboard-task-id task))
                   (task-dashboard--status-label
                    (task-dashboard-task-status task))
                   (task-dashboard--progress-string
                    (task-dashboard-task-progress task))
                   (task-dashboard-task-label task)
                   (task-dashboard--elapsed-string task)
                   (task-dashboard--exit-string task))))
   task-dashboard--tasks))

(defun task-dashboard--task-at-point ()
  "Return the task represented by the current dashboard row."
  (let ((id (or (tabulated-list-get-id)
                (tabulated-list-get-id (line-beginning-position)))))
    (or (cl-find id task-dashboard--tasks
                 :key #'task-dashboard-task-id
                 :test #'equal)
        (user-error "No task is selected"))))

(defun task-dashboard-view-task ()
  "Visit the output buffer of the task at point."
  (interactive)
  (let ((buffer (task-dashboard-task-output-buffer
                 (task-dashboard--task-at-point))))
    (if (buffer-live-p buffer)
        (pop-to-buffer buffer)
      (user-error "Task output buffer no longer exists"))))

(defun task-dashboard--send-signal (task signal)
  "Send SIGNAL to TASK's process, returning non-nil on success."
  (condition-case error
      (progn
        ;; `stop-process' and `continue-process' use the process-aware signal
        ;; path and work on platforms where direct POSIX names are unavailable.
        (cond
         ((eq signal 'SIGSTOP) (stop-process (task-dashboard-task-process task)))
         ((eq signal 'SIGCONT)
          (continue-process (task-dashboard-task-process task)))
         (t (signal-process (task-dashboard-task-process task) signal)))
        t)
    (error
     (message "Task %d: cannot send %s: %s"
              (task-dashboard-task-id task)
              signal
              (error-message-string error))
     nil)))

(defun task-dashboard-toggle-pause ()
  "Pause or resume the task at point using SIGSTOP/SIGCONT."
  (interactive)
  (let* ((task (task-dashboard--task-at-point))
         (status (task-dashboard-task-status task)))
    (cond
     ((eq status 'running)
      (unless (task-dashboard--send-signal task 'SIGSTOP)
        (user-error "This platform cannot pause the task"))
      (setf (task-dashboard-task-status task) 'paused)
      (message "Task %d paused" (task-dashboard-task-id task)))
     ((eq status 'paused)
      (unless (task-dashboard--send-signal task 'SIGCONT)
        (user-error "This platform cannot resume the task"))
      (setf (task-dashboard-task-status task) 'running)
      (message "Task %d resumed" (task-dashboard-task-id task)))
     ((eq status 'cancelling)
      (user-error "Task %d is being cancelled" (task-dashboard-task-id task)))
     (t
      (user-error "Task is not running (status: %s)"
                  (task-dashboard--status-label status))))
    (task-dashboard--refresh-all)))

(defun task-dashboard-cancel ()
  "Cancel the task at point, escalating from SIGTERM to SIGKILL if needed."
  (interactive)
  (let ((task (task-dashboard--task-at-point)))
    (unless (memq (task-dashboard-task-status task)
                  task-dashboard--terminal-statuses)
      (setf (task-dashboard-task-cancel-requested task) t
            (task-dashboard-task-status task) 'cancelling)
      (if (task-dashboard--task-live-p task)
          (progn
            (unless (task-dashboard--send-signal task 'SIGTERM)
              (ignore-errors
                (delete-process (task-dashboard-task-process task))))
            (setf (task-dashboard-task-cancel-timer task)
                  (run-at-time task-dashboard-cancel-grace-period nil
                               #'task-dashboard--force-cancel task)))
        (setf (task-dashboard-task-status task) 'cancelled
              (task-dashboard-task-end-time task) (current-time))
        (task-dashboard--notify
         (format "Task %d cancelled" (task-dashboard-task-id task))
         (task-dashboard-task-label task)
         'low))
      (task-dashboard--refresh-all))))

(defun task-dashboard-clear-finished ()
  "Remove completed, failed, and cancelled tasks from the dashboard.

Output buffers are kept so their logs remain available through `C-x b'."
  (interactive)
  (let ((cleared 0))
    (setq task-dashboard--tasks
          (cl-delete-if
           (lambda (task)
             (if (memq (task-dashboard-task-status task)
                       task-dashboard--terminal-statuses)
                 (progn (setq cleared (1+ cleared)) t)
               nil))
           task-dashboard--tasks))
    (task-dashboard--refresh-all)
    (message "Cleared %d finished task%s"
             cleared
             (if (= cleared 1) "" "s"))))

(defun task-dashboard-refresh ()
  "Refresh the current task dashboard, or all dashboard buffers."
  (interactive)
  (if (derived-mode-p 'task-dashboard-mode)
      (tabulated-list-print t)
    (task-dashboard--refresh-all)))

(defun task-dashboard--refresh-timer-function ()
  "Refresh dashboards from `task-dashboard--refresh-timer'."
  (let ((buffers
         (cl-remove-if-not
          (lambda (buffer)
            (and (buffer-live-p buffer)
                 (with-current-buffer buffer
                   (derived-mode-p 'task-dashboard-mode))))
          (buffer-list))))
    (if buffers
        (dolist (buffer buffers)
          (with-current-buffer buffer
            (task-dashboard-refresh)))
      (when (timerp task-dashboard--refresh-timer)
        (cancel-timer task-dashboard--refresh-timer))
      (setq task-dashboard--refresh-timer nil))))

(defun task-dashboard--ensure-refresh-timer ()
  "Start the dashboard refresh timer if it is not already running."
  (unless (timerp task-dashboard--refresh-timer)
    (setq task-dashboard--refresh-timer
          (run-at-time task-dashboard-refresh-interval
                       task-dashboard-refresh-interval
                       #'task-dashboard--refresh-timer-function))))

(defun task-dashboard--dashboard-killed ()
  "Stop the refresh timer when the last dashboard buffer is killed."
  (unless (cl-some
           (lambda (buffer)
             (and (buffer-live-p buffer)
                  (with-current-buffer buffer
                    (derived-mode-p 'task-dashboard-mode))))
           (buffer-list))
    (when (timerp task-dashboard--refresh-timer)
      (cancel-timer task-dashboard--refresh-timer))
    (setq task-dashboard--refresh-timer nil)))

(defvar task-dashboard-mode-map
  (let ((map (make-sparse-keymap)))
    (set-keymap-parent map tabulated-list-mode-map)
    (define-key map (kbd "g") #'task-dashboard-refresh)
    (define-key map (kbd "RET") #'task-dashboard-view-task)
    (define-key map (kbd "p") #'task-dashboard-toggle-pause)
    (define-key map (kbd "c") #'task-dashboard-cancel)
    (define-key map (kbd "k") #'task-dashboard-cancel)
    (define-key map (kbd "x") #'task-dashboard-clear-finished)
    (define-key map (kbd "q") #'quit-window)
    map)
  "Keymap for `task-dashboard-mode'.")

(define-derived-mode task-dashboard-mode tabulated-list-mode "Task Dashboard"
  "Major mode for viewing and controlling asynchronous tasks."
  (setq-local tabulated-list-format
              [("ID" 5 t)
               ("Status" 12 t)
               ("Progress" 19 nil)
               ("Task" 42 t)
               ("Elapsed" 10 nil)
               ("Exit" 8 nil)])
  (setq-local tabulated-list-padding 2)
  (setq-local tabulated-list-sort-key nil)
  (setq-local tabulated-list-entries #'task-dashboard--entries)
  (tabulated-list-init-header)
  (add-hook 'kill-buffer-hook #'task-dashboard--dashboard-killed nil t)
  (task-dashboard--ensure-refresh-timer)
  (task-dashboard-refresh))

;;;###autoload
(defun task-dashboard ()
  "Display the asynchronous task dashboard."
  (interactive)
  (let ((buffer (get-buffer-create task-dashboard--dashboard-buffer)))
    (with-current-buffer buffer
      (unless (derived-mode-p 'task-dashboard-mode)
        (task-dashboard-mode)))
    (pop-to-buffer buffer)))

(provide 'task-dashboard)

;;; task-dashboard.el ends here
