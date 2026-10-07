;;; task-dashboard-tests.el --- Task output regressions -*- lexical-binding: t; -*-

(require 'ert)
(require 'task-dashboard)

(ert-deftest config-test/task-output-preserves-reader-point ()
  (with-temp-buffer
    (special-mode)
    (let ((task (task-dashboard--make-task :output-buffer (current-buffer))))
      (task-dashboard--append-output task "first\nsecond\n")
      (goto-char 3)
      (task-dashboard--append-output task "third\n")
      (should (= (point) 3))
      (should (equal (buffer-string) "first\nsecond\nthird\n"))
      (should buffer-read-only)
      (should-not (buffer-modified-p)))))

(ert-deftest config-test/task-output-follows-tail-only-at-end ()
  (with-temp-buffer
    (special-mode)
    (let ((task (task-dashboard--make-task :output-buffer (current-buffer))))
      (task-dashboard--append-output task "first\n")
      (should (= (point) (point-max)))
      (task-dashboard--append-output task "second\n")
      (should (= (point) (point-max))))))

(provide 'task-dashboard-tests)
;;; task-dashboard-tests.el ends here
