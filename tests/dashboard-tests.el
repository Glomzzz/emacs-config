;;; dashboard-tests.el --- Daily dashboard regressions -*- lexical-binding: t; -*-

(require 'ert)
(require 'cl-lib)
(require 'button)
(require 'dashboard)

(defmacro config-test/with-dashboard (&rest body)
  "Run BODY in an isolated dashboard buffer, then remove it."
  (declare (indent 0) (debug t))
  `(let ((dashboard--buffer-name (generate-new-buffer-name " *test dashboard*")))
     (unwind-protect
         (with-current-buffer (dashboard/buffer) ,@body)
       (when-let* ((buffer (get-buffer dashboard--buffer-name)))
         (kill-buffer buffer)))))

(defun config-test/dashboard-button (command)
  "Return the dashboard button for COMMAND in the current buffer."
  (let ((button (next-button (point-min) t)))
    (while (and button (not (eq (button-get button 'dashboard-command) command)))
      (setq button (next-button (button-end button))))
    button))

(ert-deftest config-test/dashboard-renders-actions-with-real-global-keys ()
  (config-test/with-dashboard
    (should (derived-mode-p 'dashboard-mode))
    (should buffer-read-only)
    (should-not (buffer-modified-p))
    (dolist (section dashboard--actions)
      (pcase-dolist (`(,label ,command ,preferred) (cdr section))
        (let ((button (config-test/dashboard-button command)))
          (should button)
          (should (string-match-p (regexp-quote label) (button-label button)))
          (should (string-prefix-p preferred (button-label button)))
          (should (commandp command))
          (should (eq (lookup-key (current-global-map) (kbd preferred)) command)))))
    (should-not (config-test/dashboard-button 'funcs/format-buffer))))

(ert-deftest config-test/dashboard-refresh-reflects-rebound-keys ()
  (let ((map (copy-keymap (current-global-map))))
    ;; C-c is a named prefix whose map copy-keymap alone does not isolate.
    (define-key map (kbd "C-c") (copy-keymap mode-specific-map))
    (define-key map (kbd "C-c r") nil)
    (define-key map (kbd "C-c R") #'consult-recent-file)
    (cl-letf (((symbol-function 'current-global-map) (lambda () map)))
      (config-test/with-dashboard
        (should (string-prefix-p
                 "C-c R" (button-label (config-test/dashboard-button 'consult-recent-file))))
        (define-key map (kbd "C-c R") nil)
        (dashboard/refresh)
        (should (string-prefix-p
                 "M-x consult-recent-file"
                 (button-label (config-test/dashboard-button 'consult-recent-file))))))))

(ert-deftest config-test/dashboard-buttons-dispatch-interactively ()
  (let (called)
    (cl-letf (((symbol-function 'find-file)
               (lambda () (interactive) (setq called t))))
      (config-test/with-dashboard
        (button-activate (config-test/dashboard-button 'find-file))
        (should called)))))

(ert-deftest config-test/dashboard-tab-and-return-activate-buttons ()
  (save-window-excursion
    (let (called)
      (cl-letf (((symbol-function 'find-file)
                 (lambda () (interactive) (setq called t))))
        (config-test/with-dashboard
          (switch-to-buffer (current-buffer))
          (goto-char (point-min))
          (execute-kbd-macro (kbd "TAB RET"))
          (should called))))))

(ert-deftest config-test/dashboard-render-does-not-load-lazy-tools ()
  (let* ((commands '(magit-status vterm-other-window task-dashboard))
         (definitions (mapcar #'symbol-function commands)))
    (config-test/with-dashboard
      (should (equal definitions (mapcar #'symbol-function commands))))))

(ert-deftest config-test/dashboard-unavailable-button-reports-bootstrap ()
  (config-test/with-dashboard
    (cl-letf (((symbol-function 'magit-status) nil))
      (should-error (button-activate (config-test/dashboard-button 'magit-status))
                    :type 'user-error))))

(ert-deftest config-test/dashboard-inherits-caller-directory ()
  (config-test/with-directory
    (config-test/with-dashboard
      (should (equal default-directory root)))))

(ert-deftest config-test/dashboard-global-open-and-recent-file-bindings ()
  (should (eq (key-binding (kbd "C-c D")) #'dashboard/open))
  (should (eq (key-binding (kbd "C-c r")) #'consult-recent-file)))

(ert-deftest config-test/dashboard-startup-opens-only-idle-scratch ()
  (save-window-excursion
    (let ((noninteractive nil)
          (initial-buffer-choice nil)
          (dashboard/show-on-startup t)
          opened)
      (cl-letf (((symbol-function 'daemonp) (lambda () nil))
                ((symbol-function 'dashboard/open) (lambda () (setq opened t))))
        (delete-other-windows)
        (switch-to-buffer (get-buffer-create "*scratch*"))
        (set-buffer-modified-p nil)
        (dashboard/startup)
        (should opened)
        (should (eq initial-buffer-choice #'dashboard/buffer))))))

(ert-deftest config-test/dashboard-startup-preserves-explicit-files ()
  (save-window-excursion
    (let ((noninteractive nil)
          (initial-buffer-choice nil)
          (dashboard/show-on-startup t))
      (with-temp-buffer
        (setq buffer-file-name "/tmp/explicit-file.txt")
        (switch-to-buffer (current-buffer))
        (cl-letf (((symbol-function 'dashboard/open)
                   (lambda () (ert-fail "Displaced an explicit file"))))
          (dashboard/startup)
          ;; Empty future client frames still use the dashboard.
          (should (eq initial-buffer-choice #'dashboard/buffer)))))))

(ert-deftest config-test/dashboard-startup-preserves-modified-scratch ()
  (save-window-excursion
    (let ((noninteractive nil)
          (initial-buffer-choice nil)
          (dashboard/show-on-startup t))
      (switch-to-buffer (get-buffer-create "*scratch*"))
      (unwind-protect
          (progn
            (set-buffer-modified-p t)
            (cl-letf (((symbol-function 'dashboard/open)
                       (lambda () (ert-fail "Displaced modified scratch"))))
              (dashboard/startup)))
        (set-buffer-modified-p nil)))))

(ert-deftest config-test/dashboard-startup-respects-opt-outs-and-batch ()
  (dolist (settings '((t nil t) (nil nil nil) (nil t t)))
    (pcase-let ((`(,noninteractive ,initial-buffer-choice ,dashboard/show-on-startup)
                 settings))
      (let ((original initial-buffer-choice))
        (cl-letf (((symbol-function 'dashboard/open)
                   (lambda () (ert-fail "Unexpected startup dashboard"))))
          (dashboard/startup)
          (should (eq initial-buffer-choice original)))))))

(ert-deftest config-test/dashboard-daemon-installs-client-choice-without-display ()
  (let ((noninteractive nil)
        (initial-buffer-choice nil)
        (dashboard/show-on-startup t))
    (cl-letf (((symbol-function 'daemonp) (lambda () t))
              ((symbol-function 'dashboard/open)
               (lambda () (ert-fail "Displayed a dashboard on the daemon frame"))))
      (dashboard/startup)
      (should (eq initial-buffer-choice #'dashboard/buffer)))))

(ert-deftest config-test/dashboard-server-empty-request-selects-dashboard ()
  (require 'server)
  (save-window-excursion
    (let ((dashboard--buffer-name (generate-new-buffer-name " *client dashboard*"))
          (initial-buffer-choice #'dashboard/buffer)
          (server-raise-frame nil)
          (server-after-make-frame-hook nil)
          (process (make-pipe-process :name "dashboard-client-test" :noquery t)))
      (unwind-protect
          (cl-letf (((symbol-function 'server-visit-files) (lambda (&rest _) nil))
                    ((symbol-function 'server-delete-client) #'ignore)
                    ((symbol-function 'server-return-error)
                     (lambda (_process error) (ert-fail error))))
            ;; Exercise Emacs' actual empty-client selection, not our own hook.
            (server-execute process nil t nil nil t nil nil)
            (should (derived-mode-p 'dashboard-mode)))
        (delete-process process)
        (when-let* ((buffer (get-buffer dashboard--buffer-name)))
          (kill-buffer buffer))))))

(ert-deftest config-test/dashboard-server-file-request-preserves-file ()
  (require 'server)
  (save-window-excursion
    (with-temp-buffer
      (let ((file-buffer (current-buffer))
            (initial-buffer-choice (lambda () (ert-fail "Dashboard for explicit file")))
            (server-window nil)
            (server-raise-frame nil)
            (server-after-make-frame-hook nil)
            (server-switch-hook nil)
            (server-client-instructions nil)
            (process (make-pipe-process :name "dashboard-file-test" :noquery t)))
        (unwind-protect
            (cl-letf (((symbol-function 'server-visit-files)
                       (lambda (&rest _) (list file-buffer)))
                      ((symbol-function 'server-delete-client) #'ignore)
                      ((symbol-function 'server-return-error)
                       (lambda (_process error) (ert-fail error))))
              (server-execute process '(("/tmp/explicit.txt" . nil)) t nil nil t nil nil)
              (should (eq (window-buffer) file-buffer)))
          (delete-process process))))))

(provide 'dashboard-tests)
;;; dashboard-tests.el ends here
