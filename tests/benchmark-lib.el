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

(defun benchmark/sample (name function expected)
  "Time FUNCTION, validate EXPECTED, and return [seconds GC-count GC-seconds].
NAME labels failures.  GC counters cover the same interval as elapsed time;
validation and recording occur outside it.  Do not subtract GC from wall time."
  (let* ((gc-start gcs-done)
         (gc-time-start gc-elapsed)
         (start (current-time))
         (result (funcall function))
         (seconds (float-time (time-subtract (current-time) start)))
         (gc-count (- gcs-done gc-start))
         (gc-seconds (- gc-elapsed gc-time-start)))
    (unless (equal result expected)
      (error "%s workload result changed: %S != %S" name result expected))
    (vector seconds gc-count gc-seconds)))

(defun benchmark/summarize-records (records)
  "Summarize sample RECORDS, separating those with and without measured GC."
  (let ((gc-count 0) (gc-seconds 0.0) times free hit)
    (mapc (lambda (record)
            (push (aref record 0) times)
            (if (zerop (aref record 1))
                (push (aref record 0) free)
              (push (aref record 0) hit))
            (cl-incf gc-count (aref record 1))
            (cl-incf gc-seconds (aref record 2)))
          records)
    (append (benchmark/summarize times)
            (list :gc-count gc-count :gc-seconds gc-seconds
                  :gc-free (and free (benchmark/summarize free))
                  :gc-hit (and hit (benchmark/summarize hit))))))

(defun benchmark/print-summary (name summary)
  "Print NAME's overall SUMMARY and its GC-conditioned populations."
  (princ (format "%-29s %5d %10.3f %10.3f %10.3f %5d %10.3f %S\n"
                 name (plist-get summary :count)
                 (* 1000 (plist-get summary :median))
                 (* 1000 (plist-get summary :p95))
                 (* 1000 (plist-get summary :max))
                 (plist-get summary :gc-count)
                 (* 1000 (plist-get summary :gc-seconds))
                 (plist-get summary :result)))
  (dolist (population '(:gc-free :gc-hit))
    (let ((group (plist-get summary population)))
      (if group
          (princ (format "#   %-7s n=%d median=%.3f ms p95=%.3f ms max=%.3f ms\n"
                         population (plist-get group :count)
                         (* 1000 (plist-get group :median))
                         (* 1000 (plist-get group :p95))
                         (* 1000 (plist-get group :max))))
        (princ (format "#   %-7s n=0 (no observed samples)\n" population))))))

(defun benchmark/measure-many (workloads iterations)
  "Measure WORKLOADS for ITERATIONS, alternating their order each round.
WORKLOADS is an alist of names and functions returning stable results.
Warm each function three times, then collect once before the entire series.
Keep natural GC enabled; report collections between callbacks separately.
Return summaries in WORKLOADS order.  Recording/reporting is not timed."
  (unless (and workloads (integerp iterations) (> iterations 0))
    (error "Expected workloads and a positive iteration count"))
  (let ((entries
         (mapcar (lambda (workload)
                   (let* ((name (car workload))
                          (function (cdr workload))
                          (expected (funcall function)))
                     (dotimes (_ 2)
                       (unless (equal (funcall function) expected)
                         (error "%s workload changed during warmup" name)))
                     (list name function expected (make-vector iterations nil))))
                 workloads)))
    (garbage-collect)
    (let ((gc-start gcs-done)
          (gc-time-start gc-elapsed)
          (reverse-entries (reverse entries)))
      (dotimes (round iterations)
        (dolist (entry (if (cl-evenp round) entries reverse-entries))
          (aset (nth 3 entry) round
                (benchmark/sample (nth 0 entry) (nth 1 entry) (nth 2 entry)))))
      ;; Snapshot before summarizing/printing, which can itself allocate and GC.
      (let* ((series-gcs (- gcs-done gc-start))
             (series-gc-seconds (- gc-elapsed gc-time-start))
             (summaries
              (mapcar (lambda (entry)
                        (append (benchmark/summarize-records (nth 3 entry))
                                (list :name (car entry) :result (nth 2 entry))))
                      entries))
             (measured-gcs (cl-loop for s in summaries sum (plist-get s :gc-count)))
             (measured-gc-seconds
              (cl-loop for s in summaries sum (plist-get s :gc-seconds))))
        (dolist (summary summaries)
          (benchmark/print-summary (plist-get summary :name) summary))
        (princ (format "# Between timed callbacks: GCs=%d GC-ms=%.3f (excluded from rows)\n"
                       (- series-gcs measured-gcs)
                       (* 1000 (max 0.0 (- series-gc-seconds measured-gc-seconds)))))
        summaries))))

(defun benchmark/measure (name function iterations)
  "Measure FUNCTION for ITERATIONS and return its summary labelled NAME."
  (car (benchmark/measure-many (list (cons name function)) iterations)))

(defun benchmark/dabbrev-count (&optional capf)
  "Return Cape Dabbrev candidate count at point, optionally reusing CAPF.
Use the current prefix rather than CAPF's original integer end position."
  (pcase-let ((`(,beg ,_end ,table . ,properties) (or capf (cape-dabbrev))))
    (length (all-completions (buffer-substring-no-properties beg (point))
                             table (plist-get properties :predicate)))))

(defun benchmark/dabbrev-workload (scope &optional cached)
  "Build a Dabbrev callback using SCOPE, optionally with a primed CACHED table.
Creating and priming a table is untimed.  Fresh callbacks create one per call."
  (let* ((cape-dabbrev-buffer-function scope)
         (capf (and cached (cape-dabbrev))))
    (when capf (benchmark/dabbrev-count capf))
    (lambda ()
      (let ((cape-dabbrev-buffer-function scope))
        (benchmark/dabbrev-count capf)))))

(defun benchmark/set-prefix (start prefix)
  "Replace text from START to buffer end with PREFIX, outside measurement."
  (delete-region start (point-max))
  (goto-char start)
  (insert prefix))

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
            (insert "\n")
            (let ((start (point))
                  (scope cape-dabbrev-buffer-function))
              (princ "# Dabbrev: 2000 local words, eight same-mode buffers of 5000 unrelated words.\n")
              (princ "# Paired scan scopes alternate A/B and B/A each round; no GC between samples.\n")
              (dolist (prefix '("benchw" "benchword19"))
                (benchmark/set-prefix start prefix)
                (princ (format "# Fresh tables; prefix=%s\n" prefix))
                (benchmark/measure-many
                 (list (cons "dabbrev/fresh-configured"
                             (benchmark/dabbrev-workload scope))
                       (cons "dabbrev/fresh-same-mode"
                             (benchmark/dabbrev-workload #'cape-same-mode-buffers)))
                 iterations))
              (benchmark/set-prefix start "benchw")
              (let ((workloads
                     (list (cons "dabbrev/cached-configured"
                                 (benchmark/dabbrev-workload scope t))
                           (cons "dabbrev/cached-same-mode"
                                 (benchmark/dabbrev-workload #'cape-same-mode-buffers t)))))
                (benchmark/set-prefix start "benchword19")
                (princ "# Primed at benchw, extended to benchword19; repeated cached queries only.\n")
                (benchmark/measure-many workloads iterations)))))
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
