;;; jujutsu-tests.el --- On-demand Majutsu regressions -*- lexical-binding: t; -*-

(require 'ert)

(defconst config-test/majutsu-loaded-on-startup (featurep 'majutsu)
  "Whether configuration startup eagerly loaded Majutsu.")

(ert-deftest config-test/majutsu-startup-is-lazy-and-source-declared ()
  (should-not config-test/majutsu-loaded-on-startup)
  (should (memq 'majutsu packages/declared))
  (let ((source (alist-get 'majutsu packages/vc-sources)))
    (should (equal (plist-get source :url) "https://github.com/0WD0/majutsu"))
    (should (eq (plist-get source :vc-backend) 'Git)))
  (dolist (command '(majutsu majutsu-log majutsu-dispatch))
    (should (commandp command))))

(ert-deftest config-test/majutsu-owns-vcs-bindings ()
  (dolist (binding '(("C-x g" . majutsu-log)
                     ("C-x M-g" . majutsu-dispatch)
                     ("C-x j" . majutsu-log)
                     ("C-x M-j" . majutsu-dispatch)))
    (should (eq (key-binding (kbd (car binding))) (cdr binding))))
  (should-not magit-define-global-key-bindings)
  ;; Magit's after-init callback must not restore the old standalone shortcut.
  (magit-maybe-define-global-key-bindings)
  (should-not (key-binding (kbd "C-c M-g")))
  (should (memq 'magit packages/declared))
  (should (commandp 'magit-status)))

(load (expand-file-name "scripts/patch-majutsu.el" user-emacs-directory)
      nil 'nomessage)

(defconst config-test/majutsu-diff-fixture
  (concat ";;; majutsu-diff.el --- Majutsu build fixture -*- lexical-binding: t; -*-\n"
          ";;; Code:\n"
          "(defun majutsu-test-apply-changes (changes)\n"
          "  (majutsu-jjdescription-apply-descriptions changes))\n")
  "Standalone call to a function defined in Majutsu's jjdescription module.")

(ert-deftest config-test/majutsu-build-patch-is-idempotent ()
  (let ((file (make-temp-file "majutsu-patch-" nil ".el"
                              config-test/majutsu-diff-fixture)))
    (unwind-protect
        (progn
          (jujutsu/patch-majutsu file)
          (let ((patched (with-temp-buffer
                           (insert-file-contents file)
                           (buffer-string)))
                (timestamp (seconds-to-time 1000000)))
            (should (string-match-p
                     "(declare-function majutsu-jjdescription-apply-descriptions"
                     patched))
            (set-file-times file timestamp)
            (jujutsu/patch-majutsu file)
            (should (equal timestamp
                           (file-attribute-modification-time (file-attributes file))))
            (should (equal patched (with-temp-buffer
                                     (insert-file-contents file)
                                     (buffer-string))))))
      (delete-file file))))

(ert-deftest config-test/majutsu-build-patch-rejects-unknown-layout-without-writing ()
  (let* ((original ";;; No Majutsu code marker here.\n")
         (file (make-temp-file "majutsu-layout-" nil ".el" original)))
    (unwind-protect
        (progn
          (should-error (jujutsu/patch-majutsu file))
          (should (equal original (with-temp-buffer
                                    (insert-file-contents file)
                                    (buffer-string)))))
      (delete-file file))))

(ert-deftest config-test/majutsu-build-command-fixes-clean-worker-compilation ()
  (require 'package-vc)
  (should (or (eq package-vc-allow-build-commands t)
              (memq 'majutsu package-vc-allow-build-commands)))
  (let* ((source (alist-get 'majutsu packages/vc-sources))
         (directory (file-name-as-directory (make-temp-file "majutsu-build-" t)))
         (default-directory directory)
         (file (expand-file-name "majutsu-diff.el" directory)))
    (unwind-protect
        (progn
          (should (equal source (alist-get 'majutsu package-vc-selected-packages)))
          (with-temp-file file (insert config-test/majutsu-diff-fixture))
          (with-temp-buffer
            ;; A fresh -Q worker compiles the patched source with warnings fatal,
            ;; so an undeclared cross-file call fails here as it does in a build.
            (let ((command
                   (concat (plist-get source :shell-command) " --eval "
                           (shell-quote-argument
                            (prin1-to-string
                             `(progn
                                (require 'bytecomp)
                                (setq byte-compile-error-on-warn t)
                                (unless (byte-compile-file ,file)
                                  (kill-emacs 1))))))))
              (should (zerop (call-process-shell-command command nil t))))
            (should-not (string-match-p "Warning\\|Error" (buffer-string))))
          (should (file-exists-p (concat file "c"))))
      (delete-directory directory t))))

(provide 'jujutsu-tests)
;;; jujutsu-tests.el ends here
