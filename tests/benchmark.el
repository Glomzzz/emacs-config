;;; benchmark.el --- Isolated performance runner -*- lexical-binding: t; -*-

;; Usage: emacs --batch -Q -l tests/benchmark.el
;; Optional: EMACS_BENCHMARK_ITERATIONS=50
(unless noninteractive
  (user-error "Run this harness in a separate --batch -Q Emacs"))
(require 'cl-lib)
(defvar packages/bootstrap-mode)

(setq user-emacs-directory
      (file-name-as-directory
       (file-name-directory
        (directory-file-name (file-name-directory load-file-name)))))
(setq native-comp-jit-compilation nil
      package-native-compile nil)

(load (expand-file-name "early-init.el" user-emacs-directory)
      nil 'nomessage)

(let* ((package-directory (cache/folder "elpa"))
       (state-directory (make-temp-file "emacs-config-benchmark-" t))
       (cache/root (file-name-as-directory state-directory))
       (original-cache-folder (symbol-function 'cache/folder))
       (raw-iterations (or (getenv "EMACS_BENCHMARK_ITERATIONS") "30"))
       ;; Never install packages or honor project/file local code in fixtures.
       (packages/bootstrap-mode nil)
       (enable-local-variables nil)
       (enable-dir-local-variables nil))
  (unwind-protect
      (cl-letf (((symbol-function 'cache/folder)
                 (lambda (path)
                   (if (equal path "elpa")
                       package-directory
                     (funcall original-cache-folder path)))))
        (unless (and (string-match-p "\\`[0-9]+\\'" raw-iterations)
                     (<= 1 (string-to-number raw-iterations) 1000))
          (error "EMACS_BENCHMARK_ITERATIONS must be between 1 and 1000"))
        (load (expand-file-name "init.el" user-emacs-directory) nil 'nomessage)
        (load (expand-file-name "tests/benchmark-lib.el" user-emacs-directory)
              nil 'nomessage)
        ;; Auto settings live in Corfu's lazy extension; CAPFs load Cape lazily.
        (require 'corfu-auto)
        (require 'cape)
        (princ (format "# Emacs %s; %s\n# Features: %s\n"
                       emacs-version system-configuration system-configuration-features))
        (princ (format "# Runtime GC: threshold=%d, percentage=%s; JIT compilation disabled\n"
                       gc-cons-threshold gc-cons-percentage))
        (princ (format "# Auto-completion: prefix=%s delay=%s; Dabbrev=%S; buffer limit=%S\n"
                       corfu-auto-prefix corfu-auto-delay
                       cape-dabbrev-buffer-function buffers/feature-size-limit))
        (dolist (package '(cape corfu orderless))
          (when-let* ((descriptor (cadr (assq package package-alist))))
            (princ (format "# %s %s\n" package
                           (package-version-join (package-desc-version descriptor))))))
        (princ "# Warm synchronous workloads: no GUI redisplay, timers, LSP, or input latency.\n")
        (princ "# Natural GC retained; rows count GC only within timed callbacks.\n")
        (princ "# GC-free/GC-hit groups are wall times, not GC-subtracted estimates.\n")
        (princ (format "%-29s %5s %10s %10s %10s %5s %10s %s\n"
                       "workload" "n" "median-ms" "p95-ms" "max-ms" "GCs" "GC-ms" "result"))
        (benchmark/run-workloads state-directory (string-to-number raw-iterations)))
    (dolist (mode '(savehist-mode recentf-mode save-place-mode))
      ;; Do not autoload a persistence mode during cleanup after a failed init.
      (when (and (boundp mode) (symbol-value mode)) (funcall mode -1)))
    (delete-directory state-directory t)))

;;; benchmark.el ends here
