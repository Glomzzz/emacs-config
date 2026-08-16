;;; dired.el --- Dired defaults, async copies, and byte progress -*- lexical-binding: t; -*-

(require 'cl-lib)
(require 'dired)
(require 'seq)
(require 'subr-x)

(declare-function my/async-task-buffer "apps/async-tasks" (cl-x))
(declare-function my/async-task-complete "apps/async-tasks" (task &optional detail))
(declare-function my/async-task-fail "apps/async-tasks" (task &optional detail))
(declare-function my/async-task-for-process "apps/async-tasks" (process))
(declare-function my/async-task-process "apps/async-tasks" (cl-x))
(declare-function my/async-task-progress-files "apps/async-tasks" (cl-x))
(declare-function my/async-task-register "apps/async-tasks" (name kind &rest properties))
(declare-function my/dirvish-rsync-to-mac-mini "apps/mounts"
                  (&optional destination))
(declare-function my/mac-mini-relative-path "apps/mounts" (path))

(defvar async-current-process)

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

(defun my/dired-async-file-size (file)
  "Return FILE's regular-file size, or nil for other file types and errors."
  (condition-case nil
      (when-let* ((attributes (and file (file-attributes file))))
        (when (null (file-attribute-type attributes))
          (file-attribute-size attributes)))
    (file-error nil)))

(cl-defstruct (my/dired-async-file-progress
               (:constructor my/dired-async-file-progress-create))
  source destination source-size destination-existed destination-size
  destination-changed copied-bytes)

(defun my/dired-async-make-file-progress (source destination)
  "Capture progress metadata for copying SOURCE to DESTINATION."
  (let ((destination-existed
         (condition-case nil
             (and destination (file-exists-p destination))
           (file-error nil))))
    (my/dired-async-file-progress-create
     :source source
     :destination destination
     :source-size (my/dired-async-file-size source)
     :destination-existed destination-existed
     :destination-size (and destination-existed
                            (my/dired-async-file-size destination))
     :destination-changed nil
     :copied-bytes 0)))

(defun my/dired-async-progress (task)
  "Return observable byte progress for a Dired copy TASK."
  (let ((total-bytes 0)
        (copied-bytes 0)
        (observable t)
        (progress-files (my/async-task-progress-files task)))
    (if (null progress-files)
        "running"
      (dolist (file progress-files)
        (let ((source-size (my/dired-async-file-progress-source-size file))
              (destination
               (my/dired-async-file-progress-destination file)))
          (if (and (numberp source-size) destination)
              (let ((destination-size
                     (my/dired-async-file-size destination)))
                (cl-incf total-bytes source-size)
                (when (and
                       (my/dired-async-file-progress-destination-existed file)
                       (not (my/dired-async-file-progress-destination-changed
                             file)))
                  (if (equal destination-size
                             (my/dired-async-file-progress-destination-size
                              file))
                      (setq observable nil)
                    (setf
                     (my/dired-async-file-progress-destination-changed file)
                     t)))
                (when (or
                       (not
                        (my/dired-async-file-progress-destination-existed file))
                       (my/dired-async-file-progress-destination-changed file))
                  (when (numberp destination-size)
                    (setf (my/dired-async-file-progress-copied-bytes file)
                          (max
                           (my/dired-async-file-progress-copied-bytes file)
                           (min source-size destination-size))))
                  (cl-incf copied-bytes
                           (my/dired-async-file-progress-copied-bytes file))))
            (setq observable nil))))
      (if (and observable (> total-bytes 0))
          (format "%d%% (%s/%s)"
                  (min 100 (floor (* 100.0 copied-bytes) total-bytes))
                  (file-size-human-readable copied-bytes)
                  (file-size-human-readable total-bytes))
        "running"))))

(defun my/dired-async-track-process (process operation total progress-files)
  "Track PROCESS performing OPERATION on TOTAL files with PROGRESS-FILES."
  (my/async-task-register
   (format "%s %d file%s"
           operation total (if (= total 1) "" "s"))
   'dired
   :detail (abbreviate-file-name default-directory)
   :process process
   :buffer (process-buffer process)
   :progress-function (and progress-files #'my/dired-async-progress)
   :progress-files progress-files
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
  (let* ((before (process-list))
         (progress-files
          (when (string-equal operation "Copy")
            (mapcar
             (lambda (file)
               (my/dired-async-make-file-progress
                file
                (condition-case nil
                    (funcall name-constructor file)
                  (error nil))))
             files))))
    (prog1
        (apply orig file-creator operation files name-constructor arguments)
      (when-let* ((process
                   (seq-find
                    (lambda (candidate)
                      (and (not (memq candidate before))
                           (process-get candidate 'dired-async-process)))
                    (process-list))))
        (my/dired-async-track-process
         process operation (length files) progress-files)))))

(defun my/dired-copy-dispatch (&optional argument)
  "Copy with rsync when the Dired target is mac-mini, asynchronously otherwise."
  (interactive "P")
  (let ((destination (dired-dwim-target-directory)))
    (if (my/mac-mini-relative-path destination)
        (my/dirvish-rsync-to-mac-mini destination)
      (dired-async-do-copy argument))))

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

(with-eval-after-load 'dired
  (define-key dired-mode-map [remap dired-do-copy] #'my/dired-copy-dispatch)
  (define-key dired-mode-map [remap dired-do-hardlink] #'dired-async-do-hardlink)
  (define-key dired-mode-map [remap dired-do-rename] #'dired-async-do-rename)
  (define-key dired-mode-map [remap dired-do-symlink] #'dired-async-do-symlink))

;;; dired.el ends here
