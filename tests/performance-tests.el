;;; performance-tests.el --- Resource guards and benchmark regressions -*- lexical-binding: t; -*-

(require 'ert)
(require 'cl-lib)
(load (expand-file-name "benchmark-lib.el" (file-name-directory load-file-name))
      nil 'nomessage)

(ert-deftest config-test/line-numbers-respect-size-limit ()
  (with-temp-buffer
    (insert "12345")
    (let ((buffers/feature-size-limit 5))
      (appearance/line-numbers-maybe)
      (should-not display-line-numbers-mode))
    (let ((buffers/feature-size-limit 6))
      (appearance/line-numbers-maybe)
      (should display-line-numbers-mode)))
  (with-temp-buffer
    (let ((buffers/feature-size-limit nil))
      (appearance/line-numbers-maybe)
      (should display-line-numbers-mode))))

(ert-deftest config-test/line-numbers-remote-check-is-lexical ()
  (with-temp-buffer
    (let ((default-directory "/ssh:unused-host:/tmp/"))
      (cl-letf (((symbol-function 'file-attributes)
                 (lambda (&rest _) (ert-fail "Remote guard probed the filesystem"))))
        (appearance/line-numbers-maybe)
        (should-not display-line-numbers-mode)))))

(ert-deftest config-test/completion-auto-guard-keeps-manual-completion ()
  (require 'corfu)
  (dolist (kind '(small large remote opt-out))
    (with-temp-buffer
      (insert "ab")
      (let ((buffers/feature-size-limit (if (eq kind 'large) 2 3))
            (default-directory (if (eq kind 'remote)
                                   "/ssh:unused-host:/tmp/" default-directory)))
        (when (eq kind 'opt-out) (setq-local corfu-auto nil))
        (corfu-mode 1)
        (should corfu-mode)
        (if (eq kind 'small)
            (should corfu-auto)
          (should-not corfu-auto)
          (should (local-variable-p 'corfu-auto))
          ;; A nil option is insufficient if Corfu already installed its timer.
          (should-not (memq 'corfu-auto--post-command post-command-hook)))
        (should (functionp completion-in-region-function))
        ;; Exercise public manual CAPF dispatch without requiring a GUI popup.
        (let* ((completion-at-point-functions
                (list (lambda () '(1 3 ("abc") :exclusive t))))
               matches
               (completion-in-region-function
                (lambda (beg end table &optional predicate)
                  (setq matches (all-completions (buffer-substring beg end)
                                                table predicate))
                  t)))
          (should (completion-at-point))
          (should (equal matches '("abc"))))))))

(ert-deftest config-test/completion-so-long-keeps-manual-mode-only ()
  (with-temp-buffer
    (so-long-mode)
    (corfu-mode 1)
    (should corfu-mode)
    (should-not corfu-auto)
    (should-not (memq 'corfu-auto--post-command post-command-hook))
    (should (functionp completion-in-region-function))))

(ert-deftest config-test/completion-auto-guard-unlimited-and-local-scope ()
  (with-temp-buffer
    (insert "12345")
    (let ((buffers/feature-size-limit nil))
      (corfu-mode 1)
      (should corfu-auto)))
  (should (default-value 'corfu-auto)))

(ert-deftest config-test/so-long-disables-expensive-modes-and-reverts ()
  (require 'so-long)
  (dolist (mode '(font-lock-mode display-line-numbers-mode corfu-mode))
    (should (memq mode so-long-minor-modes)))
  (let ((buffer (generate-new-buffer "so-long-test")))
    (unwind-protect
        (with-current-buffer buffer
          (emacs-lisp-mode)
          ;; Font Lock skips batch sessions and space-prefixed buffers.
          (let ((noninteractive nil)) (font-lock-mode 1))
          (display-line-numbers-mode 1)
          (corfu-mode 1)
          (should font-lock-mode)
          (should corfu-mode)
          (so-long 'so-long-minor-mode)
          (should-not font-lock-mode)
          (should-not display-line-numbers-mode)
          (should-not corfu-mode)
          (should-not buffer-read-only)
          (let ((noninteractive nil)) (so-long-revert))
          (should font-lock-mode)
          (should display-line-numbers-mode)
          (should corfu-mode)
          (should corfu-auto))
      (kill-buffer buffer))))

(ert-deftest config-test/benchmark-summary-preserves-samples ()
  (let* ((samples '(3.0 1.0 4.0 2.0))
         (summary (benchmark/summarize samples)))
    (should (= (plist-get summary :count) 4))
    (should (= (plist-get summary :median) 2.5))
    (should (= (plist-get summary :p95) 4.0))
    (should (= (plist-get summary :max) 4.0))
    (should (equal samples '(3.0 1.0 4.0 2.0))))
  (should (= (benchmark/percentile (number-sequence 1 100) 0.95) 95))
  (should-error (benchmark/summarize nil)))

(ert-deftest config-test/benchmark-gc-populations ()
  (let ((summary (benchmark/summarize-records
                  '([0.01 0 0.0] [0.04 1 0.025]
                    [0.02 0 0.0] [0.06 2 0.04]))))
    (should (= (plist-get summary :count) 4))
    (should (= (plist-get summary :gc-count) 3))
    (should (= (plist-get summary :gc-seconds) 0.065))
    (should (= (plist-get (plist-get summary :gc-free) :count) 2))
    (should (= (plist-get (plist-get summary :gc-free) :median) 0.015))
    ;; GC-hit timing is actual wall time, not wall time minus GC.
    (should (= (plist-get (plist-get summary :gc-hit) :count) 2))
    (should (= (plist-get (plist-get summary :gc-hit) :median) 0.05)))
  (let ((summary (benchmark/summarize-records '([0.01 0 0.0]))))
    (should-not (plist-get summary :gc-hit)))
  (let ((summary (benchmark/summarize-records '([0.04 1 0.02]))))
    (should-not (plist-get summary :gc-free))))

(ert-deftest config-test/benchmark-counts-gc-only-in-timed-callback ()
  (let ((gcs-done 10)
        (gc-elapsed 1.0))
    (let ((sample (benchmark/sample
                   "gc" (lambda () (cl-incf gcs-done 2)
                          (cl-incf gc-elapsed 0.5) 'stable)
                   'stable)))
      (should (= (aref sample 1) 2))
      (should (= (aref sample 2) 0.5)))))

(ert-deftest config-test/benchmark-pairs-alternate-order ()
  (let (order summaries)
    (with-temp-buffer
      (let ((standard-output (current-buffer)))
        (setq summaries
              (benchmark/measure-many
               (list (cons "a" (lambda () (push 'a order) 'result-a))
                     (cons "b" (lambda () (push 'b order) 'result-b)))
               4))))
    ;; Three warmups per function precede four alternating paired rounds.
    (should (equal (nreverse order) '(a a a b b b a b b a a b b a)))
    (should (equal (mapcar (lambda (s) (plist-get s :name)) summaries)
                   '("a" "b")))
    (should (cl-every (lambda (s) (= (plist-get s :count) 4)) summaries))))

(ert-deftest config-test/benchmark-dabbrev-cached-prefix-does-not-rescan ()
  (require 'cape)
  (with-temp-buffer
    (text-mode)
    (insert "benchword1900 benchword1901 benchword1800\n")
    (let* ((start (point))
           (scans 0)
           (scope (lambda () (cl-incf scans) (current-buffer)))
           cached)
      (benchmark/set-prefix start "benchw")
      (setq cached (benchmark/dabbrev-workload scope t))
      (should (= scans 1))
      (should (= (funcall cached) 3))
      (benchmark/set-prefix start "benchword19")
      (should (= (funcall cached) 2))
      (should (= (funcall cached) 2))
      (should (= scans 1))
      ;; A fresh table at the narrower prefix must return the same count.
      (should (= (funcall (benchmark/dabbrev-workload scope)) 2))
      (should (= scans 2)))))

(ert-deftest config-test/benchmark-detects-workload-drift ()
  (let ((calls 0))
    (should-error
     (let ((standard-output (generate-new-buffer " *benchmark output*")))
       (unwind-protect
           (benchmark/measure "drift" (lambda () (cl-incf calls)) 2)
         (kill-buffer standard-output)))))
  (let ((calls 0))
    (with-temp-buffer
      (let ((standard-output (current-buffer)))
        ;; Detect drift inside the timed series, not just during warmup.
        (should-error
         (benchmark/measure "drift" (lambda () (< (cl-incf calls) 4)) 2)))))
  (should-error (benchmark/measure "invalid" #'ignore 0))
  (should-error (benchmark/measure-many nil 1)))

;;; performance-tests.el ends here
