;;; benchmark-lib.el --- Opt-in batch workload measurements -*- lexical-binding: t; -*-

;; This file is not loaded by the configuration.  Its helpers deliberately
;; measure synchronous workloads, not command-to-screen or LSP latency.
(require 'cl-lib)
(defvar cape-dabbrev-buffer-function)
(declare-function cape-dabbrev "cape" (&optional interactive))
(declare-function orderless-filter "orderless" (string table &optional pred))

(defun benchmark/percentile (sorted fraction)
  "Return the nearest-rank percentile FRACTION of nonempty SORTED samples."
  (unless (and sorted (<= 0 fraction 1))
    (error "Expected samples and a percentile between zero and one"))
  (nth (max 0 (1- (ceiling (* fraction (length sorted))))) sorted))

(defun benchmark/summarize (samples)
  "Return count, median, p95, and maximum for nonempty SAMPLES in seconds."
  (unless samples (error "No benchmark samples"))
  (let* ((sorted (sort (copy-sequence samples) #'<))
         (count (length sorted))
         (middle (/ count 2)))
    (list :count count
          :median (if (cl-oddp count)
                      (nth middle sorted)
                    (/ (+ (nth (1- middle) sorted) (nth middle sorted)) 2.0))
          :p95 (benchmark/percentile sorted 0.95)
          :max (car (last sorted)))))

(defun benchmark/measure (name function iterations)
  "Measure FUNCTION over ITERATIONS and print a summary labelled NAME.
Warm up three times, then collect once before the measurement series.
Do not collect between samples: allocation-related pauses must stay visible.
FUNCTION must return a stable result, typically a candidate count or size."
  (unless (and (integerp iterations) (> iterations 0))
    (error "Iterations must be a positive integer"))
  (let ((expected (funcall function)))
    (dotimes (_ 2) (funcall function))
    (garbage-collect)
    (let ((gc-start gcs-done)
          (gc-time-start gc-elapsed)
          samples)
      (dotimes (_ iterations)
        (let* ((start (current-time))
               (result (funcall function))
               (seconds (float-time (time-subtract (current-time) start))))
          (unless (equal result expected)
            (error "%s workload result changed: %S != %S" name result expected))
          (push seconds samples)))
      (let* ((gc-count (- gcs-done gc-start))
             (gc-seconds (- gc-elapsed gc-time-start))
             (summary (benchmark/summarize samples)))
        (princ (format "%-27s %5d %10.3f %10.3f %10.3f %5d %10.3f %S\n"
                       name iterations
                       (* 1000 (plist-get summary :median))
                       (* 1000 (plist-get summary :p95))
                       (* 1000 (plist-get summary :max))
                       gc-count (* 1000 gc-seconds) expected))
        (append summary (list :gc-count gc-count :gc-seconds gc-seconds
                              :result expected))))))

(defun benchmark/dabbrev-count ()
  "Return the number of fresh Cape Dabbrev candidates at point."
  (pcase-let ((`(,beg ,end ,table . ,properties) (cape-dabbrev)))
    (length (all-completions (buffer-substring-no-properties beg end)
                             table (plist-get properties :predicate)))))

(defun benchmark/run-workloads (directory iterations)
  "Run synthetic completion and file workloads in DIRECTORY for ITERATIONS."
  (require 'cape)
  (require 'orderless)
  (let ((candidates
         (cl-loop for i below 10000
                  collect (format "bench-candidate-%05d-command" i))))
    (benchmark/measure
     "orderless/10000-candidates"
     (lambda () (length (orderless-filter "bench 42 command" candidates)))
     iterations))
  (let (buffers)
    (unwind-protect
        (progn
          (dotimes (_ 8)
            (let ((buffer (generate-new-buffer " *benchmark other*")))
              (push buffer buffers)
              (with-current-buffer buffer
                (text-mode)
                (dotimes (i 5000) (insert (format "unrelated%04d " i))))))
          (with-temp-buffer
            (text-mode)
            (dotimes (i 2000) (insert (format "benchword%04d " i)))
            (insert "\nbenchw")
            (princ "# Dabbrev: 2000 local words, eight same-mode buffers of 5000 unrelated words.\n")
            (benchmark/measure "dabbrev/configured" #'benchmark/dabbrev-count iterations)
            (let ((cape-dabbrev-buffer-function #'cape-same-mode-buffers))
              (benchmark/measure "dabbrev/same-mode-compare" #'benchmark/dabbrev-count iterations))))
      (mapc #'kill-buffer buffers)))
  (dolist (fixture '(("small.el" . 2000) ("large.el" . 60000)))
    (let ((file (expand-file-name (car fixture) directory)))
      (with-temp-buffer
        ;; Comment-only Elisp avoids language servers and external toolchains.
        (dotimes (_ (cdr fixture))
          (insert ";; reproducible local file-opening fixture\n"))
        (write-region (point-min) (point-max) file nil 'silent))
      (benchmark/measure
       (concat "open/" (car fixture))
       (lambda ()
         (let ((buffer (find-file-noselect file)))
           (unwind-protect
               (with-current-buffer buffer
                 (list (buffer-size) (and display-line-numbers-mode t)))
             (kill-buffer buffer))))
       iterations))))

(provide 'benchmark-lib)
;;; benchmark-lib.el ends here
