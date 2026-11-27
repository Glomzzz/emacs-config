;;; startup-profile.el --- Isolated startup timing and require breakdown -*- lexical-binding: t; -*-

;; Usage: emacs --batch -Q -l tests/startup-profile.el
;; Optional: EMACS_STARTUP_PROFILE_TOP=60 sets the number of rows printed.
;; The real configuration loads with temporary state and the installed package
;; directory is reused, so history, recentf, and Customize data are not written.
;; Prints one machine-readable line, `startup-profile-total-ms N', for
;; `tests/startup-benchmark.sh'.

(unless noninteractive
  (user-error "Run this profiler in a separate --batch -Q Emacs"))
(require 'cl-lib)
(require 'seq)
(defvar packages/bootstrap-mode)

(setq user-emacs-directory
      (file-name-as-directory
       (file-name-directory
        (directory-file-name (file-name-directory load-file-name)))))
(setq native-comp-jit-compilation nil
      package-native-compile nil)

(load (expand-file-name "early-init.el" user-emacs-directory) nil 'nomessage)

(defvar startup-profile--stack nil
  "Labels of the `load' and `require' calls currently in progress.")
(defvar startup-profile--rows nil
  "Recorded entries as (MS LABEL PARENT GC-COUNT), newest first.")

(defun startup-profile--label (value)
  "Return VALUE as a short label relative to the configuration directory."
  (replace-regexp-in-string
   (regexp-quote (expand-file-name user-emacs-directory)) "" (format "%s" value)))

(defun startup-profile--record (kind orig args)
  "Call ORIG with ARGS, recording its inclusive time as a KIND entry."
  (let* ((label (format "%s %s" kind (startup-profile--label (car args))))
         (parent (car startup-profile--stack))
         (start (float-time))
         (gcs gcs-done))
    (push label startup-profile--stack)
    (unwind-protect (apply orig args)
      (pop startup-profile--stack)
      (push (list (* 1000 (- (float-time) start)) label parent
                  (- gcs-done gcs))
            startup-profile--rows))))

(defun startup-profile--load-advice (orig &rest args)
  (startup-profile--record 'load orig args))

(defun startup-profile--require-advice (orig &rest args)
  (startup-profile--record 'require orig args))

(defun startup-profile/run ()
  "Time the configuration load and print the slowest entries."
  (let* ((package-directory (cache/folder "elpa"))
         (state-directory (make-temp-file "emacs-startup-profile-" t))
         (cache/root (file-name-as-directory state-directory))
         (original-cache-folder (symbol-function 'cache/folder))
         (top (string-to-number (or (getenv "EMACS_STARTUP_PROFILE_TOP") "40")))
         (packages/bootstrap-mode nil)
         (enable-local-variables nil)
         (enable-dir-local-variables nil)
         total)
    (unwind-protect
        (cl-letf (((symbol-function 'cache/folder)
                   (lambda (path)
                     (if (equal path "elpa")
                         package-directory
                       (funcall original-cache-folder path)))))
          (advice-add 'load :around #'startup-profile--load-advice)
          (advice-add 'require :around #'startup-profile--require-advice)
          (unwind-protect
              (let ((start (float-time)))
                (load (expand-file-name "init.el" user-emacs-directory)
                      nil 'nomessage)
                (setq total (* 1000 (- (float-time) start))))
            (advice-remove 'load #'startup-profile--load-advice)
            (advice-remove 'require #'startup-profile--require-advice)))
      (delete-directory state-directory t))
    (let ((rows (sort (copy-sequence startup-profile--rows)
                      (lambda (a b) (> (car a) (car b))))))
      (message "%8s  %-6s %s" "ms" "gc" "entry  <- parent")
      (dolist (row (seq-take rows top))
        (message "%8.1f  %-6d %s%s" (nth 0 row) (nth 3 row) (nth 1 row)
                 (if (nth 2 row) (format "  <- %s" (nth 2 row)) "")))
      (message "startup-profile-total-ms %.1f" total))))

(startup-profile/run)

;;; startup-profile.el ends here
