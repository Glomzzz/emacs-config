;;; projects-tests.el --- Projectile and Counsel integration -*- lexical-binding: t; -*-

(require 'ert)
(require 'cl-lib)
(require 'projectile)
(require 'counsel-projectile)

(ert-deftest config-test/projects-prefix-and-completion-frontends-coexist ()
  (should (memq 'projectile packages/declared))
  (should (memq 'counsel-projectile packages/declared))
  (should projectile-mode)
  (should counsel-projectile-mode)
  (should (eq (key-binding (kbd "C-c P f")) #'counsel-projectile-find-file))
  (should (eq (key-binding (kbd "C-c P p")) #'counsel-projectile-switch-project))
  (should vertico-mode)
  (should-not (bound-and-true-p ivy-mode))
  (should-not (bound-and-true-p counsel-mode))
  (should (eq completing-read-function #'completing-read-default))
  (require 'fingertip)
  (with-temp-buffer
    (let ((fingertip-mode t))
      (should (eq (key-binding (kbd "C-c p n")) #'fingertip-jump-right))
      (should (eq (key-binding (kbd "C-c P f")) #'counsel-projectile-find-file)))))

(ert-deftest config-test/projects-mode-keeps-project-el-root-discovery ()
  (should-not (memq #'project-projectile project-find-functions))
  ;; The guard also applies if either package is explicitly re-enabled.
  (counsel-projectile-mode 1)
  (should-not (memq #'project-projectile project-find-functions))
  (config-test/with-directory
    (config-test/file root "package.json" "{}")
    (config-test/file root "nested/hie.yaml" "cradle: {}")
    (make-directory (expand-file-name "nested/src/" root))
    (should (equal (project-root (project-current nil (expand-file-name "nested/src/" root)))
                   (expand-file-name "nested/" root)))))

(ert-deftest config-test/projects-keep-known-project-registration-explicit ()
  (config-test/with-directory
    (should (zerop (call-process "git" nil nil nil "init" "--quiet" root)))
    (let ((projectile-known-projects nil)
          (projectile-known-projects-on-file nil)
          (projectile-known-projects-file (expand-file-name "known-projects.eld" root))
          (file (config-test/file root "example.txt")))
      (unwind-protect
          (progn
            (find-file-noselect file)
            (should-not projectile-track-known-projects-automatically)
            (should-not projectile-known-projects)
            (projectile-add-known-project root)
            (should (member root projectile-known-projects)))
        (when-let* ((buffer (get-file-buffer file))) (kill-buffer buffer))))))

(ert-deftest config-test/projects-counsel-file-command-uses-real-index-and-action ()
  (config-test/with-directory
    (should (zerop (call-process "git" nil nil nil "init" "--quiet" root)))
    (config-test/file root ".gitignore" "ignored.txt\n")
    (config-test/file root "kept.txt" "Project file\n")
    (config-test/file root "ignored.txt" "Ignored file\n")
    (let (prompted)
      (unwind-protect
          (save-window-excursion
            (cl-letf (((symbol-function 'ivy-read)
                       (lambda (_prompt collection &rest options)
                         (should (member "kept.txt" collection))
                         (should-not (member "ignored.txt" collection))
                         (should (eq (plist-get options :caller) 'counsel-projectile-find-file))
                         (setq prompted t)
                         (counsel-projectile-find-file-action "kept.txt"))))
              (call-interactively (key-binding (kbd "C-c P f")))
              (should prompted)
              (should (equal buffer-file-name (expand-file-name "kept.txt" root)))))
        (when-let* ((buffer (get-file-buffer (expand-file-name "kept.txt" root))))
          (kill-buffer buffer))))))

(ert-deftest config-test/projects-hydra-dispatches-counsel-and-task-commands ()
  (should (eq (key-binding (kbd "C-x C-h P")) #'hydra-proj/body))
  (should (eq (key-binding (kbd "C-c P .")) #'hydra-proj/body))
  (dolist (entry '(("f" . counsel-projectile-find-file)
                   ("p" . counsel-projectile-switch-project)
                   ("s" . counsel-projectile-rg)
                   ("c" . projectile-compile-project)
                   ("t" . projectile-test-project)
                   ("r" . projectile-run-project)))
    (let (called)
      (cl-letf (((symbol-function (cdr entry))
                 (lambda ()
                   (interactive)
                   (should-not hydra-curr-map)
                   (setq called t))))
        (unwind-protect
            (progn
              (execute-kbd-macro (vconcat (kbd "C-c P .") (kbd (car entry))))
              (should called)
              (should-not hydra-curr-map))
          (hydra-keyboard-quit)))))
  (execute-kbd-macro (kbd "C-x C-h P q"))
  (should-not hydra-curr-map))

(ert-deftest config-test/projects-state-and-cache-policy ()
  (dolist (file (list projectile-known-projects-file projectile-frecency-file
                      projectile-session-directory))
    (should (string-prefix-p (expand-file-name cache/root) (expand-file-name file))))
  (should (equal projectile-mode-line-prefix " Projectile"))
  (should-not projectile-dynamic-mode-line)
  ;; Persistent indexes write into project roots in the current Projectile.
  (should (eq projectile-enable-caching t))
  (should-not (projectile-persistent-cache-p)))

(provide 'projects-tests)
;;; projects-tests.el ends here
