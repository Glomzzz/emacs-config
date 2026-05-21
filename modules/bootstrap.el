;;; bootstrap.el --- Package bootstrap and shared package helpers -*- lexical-binding: t; -*-

(require 'cl-lib)
(require 'package)

(setq package-archives
      '(("gnu" . "https://elpa.gnu.org/packages/")
        ("nongnu" . "https://elpa.nongnu.org/nongnu/")
        ("melpa" . "https://melpa.org/packages/"))
      package-user-dir my/emacs-package-dir
      package-archive-priorities
      '(("gnu" . 30)
        ("nongnu" . 20)
        ("melpa" . 10))
      package-install-upgrade-built-in t
      package-quickstart-file my/emacs-package-quickstart-file
      use-package-always-ensure nil
      use-package-expand-minimally t)

(defconst my/required-packages
  '(corfu eldoc-box envrc gruber-darker-theme markdown-mode
    nix-ts-mode racket-mode treesit-auto typst-ts-mode vterm))

(defvar my/refresh-package-quickstart-after-startup nil)

(defun my/call-with-quiet-compilation (fn &rest args)
  "Call FN with ARGS while suppressing byte-compilation noise."
  (let ((byte-compile-verbose nil)
        (byte-compile-warnings nil)
        (inhibit-message t)
        (orig-display-warning (symbol-function 'display-warning)))
    (cl-letf (((symbol-function 'byte-compile-log-file) #'ignore)
              ((symbol-function 'byte-compile-log-warning) #'ignore)
              ((symbol-function 'display-warning)
               (lambda (type message &optional level buffer-name)
                 (unless (eq type 'bytecomp)
                   (funcall orig-display-warning
                            type message level buffer-name)))))
      (apply fn args))))

(defun my/bootstrap-packages ()
  "Install missing packages without refreshing quickstart on every install."
  (let (missing)
    (dolist (package my/required-packages)
      (unless (package-installed-p package)
        (push package missing)))
    (when missing
      (setq my/refresh-package-quickstart-after-startup t
            missing (nreverse missing))
      (let ((orig-package-compile (symbol-function 'package--compile)))
        (cl-letf (((symbol-function 'package--quickstart-maybe-refresh) #'ignore)
                  ((symbol-function 'package--compile)
                   (lambda (pkg-desc)
                     (my/call-with-quiet-compilation
                      orig-package-compile pkg-desc))))
          (unless package-archive-contents
            (package-refresh-contents))
          (dolist (package missing)
            (unless (package-installed-p package)
              (package-install package))))))))

(defun my/refresh-package-quickstart-on-startup ()
  "Generate package quickstart once, after startup has completed."
  (when my/refresh-package-quickstart-after-startup
    (setq my/refresh-package-quickstart-after-startup nil)
    (my/call-with-quiet-compilation #'package-quickstart-refresh)))

(my/bootstrap-packages)
(unless package-activated-list
  (package-activate-all))
(add-hook 'emacs-startup-hook #'my/refresh-package-quickstart-on-startup)

(require 'use-package)
