;;; dashboard-tests.el --- Dashboard package integration regressions -*- lexical-binding: t; -*-

(require 'ert)
(require 'cl-lib)
(require 'bookmark)
(require 'project)
(require 'dashboard)

(defmacro config-test/with-dashboard (&rest body)
  "Run BODY in an isolated upstream Dashboard buffer, then remove it."
  (declare (indent 0) (debug t))
  `(let ((dashboard-buffer-name (generate-new-buffer-name " *test dashboard*"))
         (recentf-list nil)
         (bookmark-alist nil)
         (bookmark-default-file-already-loaded t)
         (project--list nil))
     (unwind-protect
         (with-current-buffer (dashboard/buffer) ,@body)
       (when-let* ((buffer (get-buffer dashboard-buffer-name)))
         (kill-buffer buffer)))))

(ert-deftest config-test/dashboard-loads-package-without-local-feature-collision ()
  (should (memq 'dashboard packages/declared))
  (should (file-in-directory-p (symbol-file 'dashboard-mode 'defun) package-user-dir))
  (config-test/with-dashboard
    (should (derived-mode-p 'dashboard-mode))
    (should buffer-read-only)
    (should (string-match-p "The truth is the whole\\." (buffer-string)))))

(ert-deftest config-test/dashboard-renders-real-recent-bookmark-and-project-limits ()
  (config-test/with-directory
    (config-test/with-dashboard
      (let ((recentf-list
             (cl-loop for n from 1 to 7
                      collect (config-test/file root (format "recent-%d.txt" n))))
            (bookmark-alist
             (cl-loop for n from 1 to 7
                      collect `(,(format "bookmark-%d" n)
                                (filename . ,(expand-file-name "recent-1.txt" root))
                                (position . 1))))
            (project--list
             (cl-loop for n from 1 to 12
                      for directory = (expand-file-name (format "project-%d/" n) root)
                      do (make-directory directory)
                      collect (list directory))))
        (dashboard-insert-startupify-lists t)
        (dolist (label '("Recent Files:" "Bookmarks:" "Projects:"
                         "recent-5.txt" "bookmark-5" "project-10"))
          (should (string-match-p (regexp-quote label) (buffer-string))))
        (dolist (label '("recent-6.txt" "bookmark-6" "project-11"))
          (should-not (string-match-p (regexp-quote label) (buffer-string))))))))

(ert-deftest config-test/dashboard-tab-and-return-open-real-recent-file ()
  (config-test/with-directory
    (let ((file (config-test/file root "recent.txt")))
      (unwind-protect
          (save-window-excursion
            (config-test/with-dashboard
              (let ((dashboard-items '((recents . 5)))
                    (recentf-list (list file)))
                (dashboard-insert-startupify-lists t)
                (switch-to-buffer (current-buffer))
                (goto-char (point-min))
                (execute-kbd-macro (kbd "TAB RET"))
                (should (equal (buffer-file-name) file)))))
        (when-let* ((buffer (get-file-buffer file)))
          (kill-buffer buffer))))))

(ert-deftest config-test/dashboard-hydra-opens-navigates-and-launches ()
  (config-test/with-directory
    (save-window-excursion
      (config-test/with-dashboard
        (let ((recentf-list (list (config-test/file root "hydra-recent.txt")))
              called)
          (cl-letf (((symbol-function 'consult-recent-file)
                     (lambda () (interactive) (setq called t))))
            (unwind-protect
                (progn
                  (switch-to-buffer (current-buffer))
                  (execute-kbd-macro (kbd "C-x C-h s n p g q"))
                  (should (derived-mode-p 'dashboard-mode))
                  (should-not hydra-curr-map)
                  (execute-kbd-macro (kbd ". r"))
                  (should called)
                  (should-not hydra-curr-map))
              (hydra-keyboard-quit))))))))

(ert-deftest config-test/dashboard-inherits-caller-directory ()
  (config-test/with-directory
    (config-test/with-dashboard
      (should (equal default-directory root)))))

(ert-deftest config-test/dashboard-global-open-and-recent-file-bindings ()
  (should (eq (key-binding (kbd "C-c D")) #'dashboard/open))
  (should (eq (key-binding (kbd "C-c R")) #'consult-recent-file)))

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
    (let ((dashboard-buffer-name (generate-new-buffer-name " *client dashboard*"))
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
        (when-let* ((buffer (get-buffer dashboard-buffer-name)))
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
