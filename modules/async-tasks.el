;;; async-tasks.el --- Background task dashboard -*- lexical-binding: t; -*-

(require 'cl-lib)
(require 'project)
(require 'seq)
(require 'tabulated-list)

(cl-defstruct (my/async-task (:constructor my/async-task-create))
  id name kind state started finished detail project process buffer cancel-function)

(defgroup my/async-tasks nil
  "Track background work started by Emacs."
  :group 'processes)

(defcustom my/async-task-history-limit 100
  "Maximum number of completed tasks retained by the dashboard."
  :type 'integer)

(defcustom my/async-task-refresh-interval 1
  "Seconds between dashboard refreshes while it is visible."
  :type 'number)

(defconst my/async-task-buffer-name "*Async Tasks*")

(defvar my/async-tasks nil)
(defvar my/async-task-next-id 0)
(defvar my/async-task-refresh-timer nil)
(defvar my/async-task-show-history t)
(defvar my/async-task-refreshing nil)
(defvar eglot--servers-by-project)
(defvar jsonrpc--events-buffer-scrollback-size)

(declare-function eglot--server-name "eglot" (server))
(declare-function eglot-project-nickname "eglot" (server))
(declare-function eglot-shutdown "eglot" (server &optional interactive timeout preserve-buffers))
(declare-function jsonrpc--process "jsonrpc" (connection))
(declare-function jsonrpc-events-buffer "jsonrpc" (connection))

(defun my/async-task-current-project ()
  "Return the current project root or abbreviated working directory."
  (if-let* ((project (project-current nil default-directory)))
      (abbreviate-file-name (project-root project))
    (abbreviate-file-name default-directory)))

(defun my/async-task-register (name kind &rest properties)
  "Register a background task named NAME of KIND with PROPERTIES."
  (unless (plist-member properties :project)
    (setq properties
          (plist-put properties :project (my/async-task-current-project))))
  (let ((task (apply #'my/async-task-create
                     :id (cl-incf my/async-task-next-id)
                     :name name
                     :kind kind
                     :state 'running
                     :started (current-time)
                     properties)))
    (push task my/async-tasks)
    (when-let* ((process (my/async-task-process task)))
      (process-put process 'my/async-task task))
    (my/async-task-refresh)
    task))

(defun my/async-task-for-process (process)
  "Return the dashboard task associated with PROCESS."
  (or (process-get process 'my/async-task)
      (seq-find (lambda (task)
                  (eq process (my/async-task-process task)))
                my/async-tasks)))

(defun my/async-task-set-state (task state &optional detail)
  "Set TASK to STATE and optionally replace its DETAIL."
  (when task
    (setf (my/async-task-state task) state)
    (when detail
      (setf (my/async-task-detail task) detail))
    (unless (eq state 'running)
      (setf (my/async-task-finished task) (current-time)))
    (my/async-task-trim-history)
    (my/async-task-refresh))
  task)

(defun my/async-task-complete (task &optional detail)
  "Mark TASK completed with optional DETAIL."
  (my/async-task-set-state task 'done detail))

(defun my/async-task-fail (task &optional detail)
  "Mark TASK failed with optional DETAIL."
  (my/async-task-set-state task 'failed detail))

(defun my/async-task-cancelled (task &optional detail)
  "Mark TASK cancelled with optional DETAIL."
  (my/async-task-set-state task 'cancelled detail))

(defun my/async-task-trim-history ()
  "Keep only the configured number of completed tasks."
  (let ((completed 0))
    (setq my/async-tasks
          (seq-filter
           (lambda (task)
             (or (eq (my/async-task-state task) 'running)
                 (<= (cl-incf completed) my/async-task-history-limit)))
           my/async-tasks))))

(defun my/async-task-known-process-p (process)
  "Return non-nil when PROCESS is already represented by a task or service."
  (or (process-get process 'my/async-task)
      (process-get process 'my/async-task-hidden)
      (process-get process 'dired-async-process)
      (member (process-name process) '("server" "emacs-server"))
      (and (featurep 'eglot)
           (boundp 'eglot--servers-by-project)
           (cl-loop for servers being the hash-values of eglot--servers-by-project
                    thereis
                    (cl-loop for server in servers
                             thereis (eq process (jsonrpc--process server)))))))

(defun my/async-task-interesting-process-p (process)
  "Return non-nil when PROCESS should be discovered by the dashboard."
  (and (process-live-p process)
       (not (my/async-task-known-process-p process))
       (or (process-command process)
           (memq (process-type process) '(network serial)))))

(defun my/async-task-process-detail (process)
  "Return a concise command description for PROCESS."
  (let ((command (process-command process)))
    (cond
     ((consp command) (mapconcat #'identity command " "))
     ((stringp command) command)
     (t (symbol-name (process-type process))))))

(defun my/async-task-process-project (process)
  "Return the project or working directory associated with PROCESS."
  (when-let* ((buffer (process-buffer process))
              ((buffer-live-p buffer)))
    (with-current-buffer buffer
      (my/async-task-current-project))))

(defun my/async-task-discover-processes ()
  "Register active Emacs subprocesses not already known to the dashboard."
  (dolist (process (process-list))
    (when (my/async-task-interesting-process-p process)
      (let ((project (my/async-task-process-project process)))
        (my/async-task-register
         (process-name process) 'process
         :detail (my/async-task-process-detail process)
         :project project
         :process process
         :buffer (process-buffer process))))))

(defun my/async-task-reconcile-processes ()
  "Update running task states from their subprocesses."
  (dolist (task my/async-tasks)
    (when (and (eq (my/async-task-state task) 'running)
               (processp (my/async-task-process task))
               (not (process-live-p (my/async-task-process task))))
      (let ((process (my/async-task-process task)))
        (cond
         ((process-get process 'cancelled)
          (my/async-task-cancelled task))
         ((zerop (process-exit-status process))
          (my/async-task-complete task))
         (t
          (my/async-task-fail
           task (format "exit %d" (process-exit-status process)))))))))

(defun my/async-task-eglot-servers ()
  "Return all currently registered Eglot servers."
  (require 'eglot nil t)
  (when (and (featurep 'eglot)
             (boundp 'eglot--servers-by-project))
    (cl-loop for servers being the hash-values of eglot--servers-by-project
             append servers)))

(defun my/async-task-elapsed (started &optional finished)
  "Format elapsed time between STARTED and FINISHED or now."
  (let ((seconds (max 0 (floor (float-time
                                (time-subtract (or finished (current-time))
                                               started))))))
    (format-seconds "%h:%.2m:%.2s" seconds)))

(defun my/async-task-state-string (state)
  "Return a display string for task STATE."
  (pcase state
    ('running (propertize "running" 'face 'success))
    ('done (propertize "done" 'face 'font-lock-doc-face))
    ('cancelled (propertize "cancelled" 'face 'warning))
    ('failed (propertize "failed" 'face 'error))
    (_ (symbol-name state))))

(defun my/async-task-entry (task)
  "Build one tabulated list entry for TASK."
  (list task
        (vector
         (my/async-task-state-string (my/async-task-state task))
         (symbol-name (my/async-task-kind task))
         (my/async-task-name task)
         (my/async-task-elapsed (my/async-task-started task)
                                (my/async-task-finished task))
         (or (my/async-task-project task) "")
         (or (my/async-task-detail task) ""))))

(defun my/async-task-eglot-entry (server)
  "Build one service entry for Eglot SERVER."
  (let* ((process (jsonrpc--process server))
         (started (or (process-get process 'my/async-task-started)
                      (let ((time (current-time)))
                        (process-put process 'my/async-task-started time)
                        time)))
         (command (process-command process)))
    (list (cons 'eglot server)
          (vector
           (propertize "service" 'face 'font-lock-keyword-face)
           "lsp"
           (eglot--server-name server)
           (my/async-task-elapsed started)
           (eglot-project-nickname server)
           (if (consp command) (mapconcat #'identity command " ") "network")))))

(defun my/async-task-entries ()
  "Return task and service entries for the dashboard."
  (let ((my/async-task-refreshing t))
    (my/async-task-discover-processes)
    (my/async-task-reconcile-processes)
    (let ((running (seq-filter
                    (lambda (task)
                      (eq (my/async-task-state task) 'running))
                    my/async-tasks))
          (finished (seq-remove
                     (lambda (task)
                       (eq (my/async-task-state task) 'running))
                     my/async-tasks)))
      (append
       (mapcar #'my/async-task-entry running)
       (mapcar #'my/async-task-eglot-entry (my/async-task-eglot-servers))
       (when my/async-task-show-history
         (mapcar #'my/async-task-entry finished))))))

(defun my/async-task-at-point ()
  "Return the task or service represented by the current row."
  (or (tabulated-list-get-id)
      (user-error "No task on this line")))

(defun my/async-task-cancel ()
  "Cancel the task or service at point."
  (interactive)
  (pcase (my/async-task-at-point)
    (`(eglot . ,server)
     (when (yes-or-no-p (format "Stop %s? " (eglot--server-name server)))
       (eglot-shutdown server)))
    ((and task (pred my/async-task-p))
     (unless (eq (my/async-task-state task) 'running)
       (user-error "This task is no longer running"))
     (when (yes-or-no-p (format "Cancel %s? " (my/async-task-name task)))
       (cond
        ((my/async-task-cancel-function task)
         (funcall (my/async-task-cancel-function task) task))
        ((process-live-p (my/async-task-process task))
         (process-put (my/async-task-process task) 'cancelled t)
         (delete-process (my/async-task-process task)))
        (t (user-error "Task has no cancellable process")))
       (my/async-task-cancelled task)))
    (_ (user-error "Unknown dashboard row"))))

(defun my/async-task-open-log ()
  "Open the task log, process buffer, or Eglot events at point."
  (interactive)
  (pcase (my/async-task-at-point)
    (`(eglot . ,server)
     (let ((jsonrpc--events-buffer-scrollback-size nil))
       (pop-to-buffer (jsonrpc-events-buffer server))))
    ((and task (pred my/async-task-p))
     (let ((buffer (or (and (buffer-live-p (my/async-task-buffer task))
                            (my/async-task-buffer task))
                       (when-let* ((process (my/async-task-process task))
                                   (process-buffer (process-buffer process))
                                   ((buffer-live-p process-buffer)))
                         process-buffer))))
       (if buffer
           (pop-to-buffer buffer)
         (user-error "No log buffer is available for this task"))))))

(defun my/async-task-toggle-history ()
  "Toggle completed task history in the dashboard."
  (interactive)
  (setq my/async-task-show-history (not my/async-task-show-history))
  (setq header-line-format
        (format " %s task history; g refresh, h toggle history, k cancel, RET log"
                (if my/async-task-show-history "Showing" "Hiding")))
  (tabulated-list-print t))

(defun my/async-task-clear-history ()
  "Remove completed tasks from the dashboard history."
  (interactive)
  (setq my/async-tasks
        (seq-filter (lambda (task)
                      (eq (my/async-task-state task) 'running))
                    my/async-tasks))
  (tabulated-list-print t))

(defvar-keymap my/async-task-list-mode-map
  :parent tabulated-list-mode-map
  "k" #'my/async-task-cancel
  "RET" #'my/async-task-open-log
  "h" #'my/async-task-toggle-history
  "x" #'my/async-task-clear-history)

(define-derived-mode my/async-task-list-mode tabulated-list-mode "Async-Tasks"
  "List background tasks and persistent Eglot services."
  (setq tabulated-list-format
        [("State" 10 t)
         ("Kind" 10 t)
         ("Task" 28 t)
         ("Elapsed" 10 nil)
         ("Project" 28 t)
         ("Detail" 48 nil)]
        tabulated-list-padding 2
        tabulated-list-sort-key nil
        tabulated-list-entries #'my/async-task-entries
        header-line-format
        " Showing task history; g refresh, h toggle history, k cancel, RET log")
  (tabulated-list-init-header))

(defun my/async-task-refresh ()
  "Refresh the task dashboard when it is visible."
  (unless my/async-task-refreshing
    (if-let* ((buffer (get-buffer my/async-task-buffer-name))
              ((get-buffer-window buffer t)))
        (with-current-buffer buffer
          (when (derived-mode-p 'my/async-task-list-mode)
            (let ((my/async-task-refreshing t))
              (tabulated-list-print t))))
      (when (timerp my/async-task-refresh-timer)
        (cancel-timer my/async-task-refresh-timer)
        (setq my/async-task-refresh-timer nil)))))

(defun my/async-task-start-refresh-timer ()
  "Start automatic dashboard refreshes."
  (unless (timerp my/async-task-refresh-timer)
    (setq my/async-task-refresh-timer
          (run-with-timer 0 my/async-task-refresh-interval
                          #'my/async-task-refresh))))

(defun my/async-task-list ()
  "Show all active tasks, recent history, and Eglot services."
  (interactive)
  (let ((buffer (get-buffer-create my/async-task-buffer-name)))
    (with-current-buffer buffer
      (my/async-task-list-mode)
      (tabulated-list-print))
    (pop-to-buffer buffer)
    (my/async-task-start-refresh-timer)))

(global-set-key (kbd "C-c j") #'my/async-task-list)

;;; async-tasks.el ends here
