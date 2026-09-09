;;; dired-async.el --- Asynchronous Dired operations -*- lexical-binding: t; -*-

;; Filesystem work is safe to isolate in a child process.  Buffer edits such as
;; kill/yank and ordinary text deletion stay synchronous so point, undo state,
;; and the kill ring retain their normal Emacs semantics.

(require 'cl-lib)
(require 'cache)
(require 'packages)

(declare-function dired-do-delete "dired-aux" (&optional arg))
(declare-function dired-get-marked-files "dired" (&optional localp arg filter
                                                  distinguish-one-marked error))
(defvar dired-recursive-deletes)
(defvar dired-no-confirm)
(defvar dired-mode-map)
(defvar dired-async-skip-fast)
(defvar dired-async-message-function)
(defvar dired-async-log-file)

(declare-function dired-async-create-files "dired-async"
                  (file-creator operation fn-list name-constructor
                                 &optional marker-char))
(declare-function dired-async-processes "dired-async" (&optional propname))
(declare-function task-dashboard-track-process "task-dashboard"
                  (process &rest arguments))
(declare-function task-dashboard-run-async "task-dashboard"
                  (start-fn &rest arguments))
(declare-function task-dashboard-task-status "task-dashboard" (task))
(declare-function task-dashboard-task-error "task-dashboard" (task))

(packages/declare 'async)

(use-package async
  :ensure nil
  :commands (async-start async-start-process)
  :custom
  ;; Do not make exiting Emacs wait for a background worker.
  (async-process-noquery-on-exit t))

(defun dired-async/message (format-string _face &rest args)
  "Report a completed Dired async operation without blocking the UI."
  (apply #'message format-string args))

(defun dired-async/track-tasks
    (_file-creator operation files _name-constructor &optional _marker-char)
  "Expose newly-created Dired async processes in the task dashboard."
  (when (fboundp 'dired-async-processes)
    (dolist (process (dired-async-processes))
      (unless (process-get process 'task-dashboard-task)
        (condition-case error
            (task-dashboard-track-process
             process
             :label (format "Dired %s (%d file%s)"
                            operation
                            (length files)
                            (if (= (length files) 1) "" "s"))
             :directory default-directory)
          (error
           ;; A remote Dired operation may require a TRAMP prompt or a
           ;; directory that cannot be normalised in the parent process.  The
           ;; owning `dired-async' operation remains fully functional.
           (message "Could not track Dired async task: %s"
                    (error-message-string error))))))))

(defun dired-async--refresh (buffer deleted)
  "Refresh Dired BUFFER after DELETED files finish asynchronously."
  (when (buffer-live-p buffer)
    (with-current-buffer buffer
      (when (derived-mode-p 'dired-mode)
        (when (fboundp 'dired-clean-up-after-deletion)
          (dolist (file deleted)
            (ignore-errors
              (dired-clean-up-after-deletion file))))
        (when (buffer-live-p buffer)
          (revert-buffer nil t))))))

(defun dired-async/delete (&optional arg)
  "Delete marked Dired files asynchronously when they are local.

The standard Dired confirmation, trash setting, recursive-delete setting, and
remote-file behavior are preserved.  Remote files fall back to Emacs' native
implementation because an async child cannot reliably share every TRAMP
authentication prompt."
  (interactive "P")
  (require 'dired-aux)
  (require 'task-dashboard)
  (let* ((files (dired-get-marked-files nil arg))
         (buffer (current-buffer))
         (remote (cl-some #'file-remote-p files)))
    (unless files
      (user-error "No files selected"))
    (if (or remote
            (not (require 'async nil t)))
        (progn
          (when remote
            (message "Remote Dired deletion uses the native synchronous path"))
          (dired-do-delete arg))
      (let* ((directories
              (cl-remove-if-not
               (lambda (file)
                 (and (file-directory-p file)
                      (not (file-symlink-p file))))
               files))
             (recursive
              (cond
               ((null directories) nil)
               ((eq dired-recursive-deletes 'always) t)
               ((eq dired-recursive-deletes 'top)
                (y-or-n-p (format "Recursively delete %d director%s? "
                                  (length directories)
                                  (if (= (length directories) 1) "y" "ies"))))
               (t nil)))
             (trash (and (not arg)
                         (boundp 'delete-by-moving-to-trash)
                         delete-by-moving-to-trash)))
        (when (or (memq 'delete dired-no-confirm)
                  (yes-or-no-p
                   (format "Delete %d file%s asynchronously%s? "
                           (length files)
                           (if (= (length files) 1) "" "s")
                           (if trash " (move to trash)" ""))))
          (task-dashboard-run-async
           (lambda ()
             (let ((total (length files))
                   (index 0)
                   deleted
                   failures)
               (dolist (file files)
                 (setq index (1+ index))
                 (condition-case error
                     (progn
                       (if (and (file-directory-p file)
                                (not (file-symlink-p file)))
                           (delete-directory file recursive trash)
                         (delete-file file trash))
                       (push file deleted))
                   (error
                    (push (cons file (error-message-string error)) failures)))
                 (when (fboundp 'async-send)
                   (async-send
                    :progress (* 100.0 (/ index (float total)))
                    :message (format "Deleted %d/%d: %s" index total file))))
               (let ((value (list :deleted (nreverse deleted)
                                  :failures (nreverse failures))))
                 ;; Keep the detailed result available to the completion
                 ;; callback, while making partial filesystem operations visible
                 ;; as failed tasks in the dashboard.
                 (if failures
                     (list :task-dashboard-error t
                           :error (format "Failed to delete %d of %d file%s"
                                          (length failures)
                                          total
                                          (if (= total 1) "" "s"))
                           :value value)
                   value))))
           :label (format "Delete %d Dired file%s"
                          (length files)
                          (if (= (length files) 1) "" "s"))
           :directory default-directory
           :on-complete
           (lambda (task result)
             (let* ((value (and (listp result)
                                (plist-get result :value)))
                    (deleted (and (listp value)
                                  (plist-get value :deleted)))
                    (failures (and (listp value)
                                   (plist-get value :failures))))
               (cond
                ((eq (task-dashboard-task-status task) 'cancelled)
                 (message "Async delete cancelled"))
                ((eq (task-dashboard-task-status task) 'failed)
                 (dired-async--refresh buffer deleted)
                 (message "Async delete failed: %s"
                          (or (task-dashboard-task-error task)
                              "see *Task Dashboard*")))
                (failures
                 (dired-async--refresh buffer deleted)
                 (message "Async delete: %d deleted, %d failed; see *Task Dashboard*"
                          (length deleted) (length failures)))
                (t
                 (dired-async--refresh buffer deleted)
                 (message "Async delete complete: %d file%s"
                          (length deleted)
                          (if (= (length deleted) 1) "" "s"))))))))))))

(defun dired-async/enable ()
  "Enable asynchronous Dired file operations when the package is present."
  (when (require 'dired-async nil t)
    ;; Dired is lazy, so load the dashboard only when this integration is used.
    (require 'task-dashboard)
    (setq dired-async-skip-fast nil
          dired-async-message-function #'dired-async/message
          dired-async-log-file (cache/file "dired-async.log"))
    (dired-async-mode 1)
    (unless (advice-member-p #'dired-async/track-tasks
                             #'dired-async-create-files)
      (advice-add 'dired-async-create-files
                  :after #'dired-async/track-tasks))
    ;; These remaps make the asynchronous behavior explicit even if another
    ;; package later changes the `dired-create-files' advice chain.
    (define-key dired-mode-map [remap dired-do-copy] #'dired-async-do-copy)
    (define-key dired-mode-map [remap dired-do-rename] #'dired-async-do-rename)
    (define-key dired-mode-map [remap dired-do-delete] #'dired-async/delete)
    (when (fboundp 'dired-async-do-symlink)
      (define-key dired-mode-map
                  [remap dired-do-symlink]
                  #'dired-async-do-symlink))
    (when (fboundp 'dired-async-do-hardlink)
      (define-key dired-mode-map
                  [remap dired-do-hardlink]
                  #'dired-async-do-hardlink))))

(with-eval-after-load 'dired
  (dired-async/enable))

;;; dired-async.el ends here
