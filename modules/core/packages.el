;;; packages.el --- package.el setup and helpers -*- lexical-binding: t; -*-

(require 'cl-lib)
(require 'package)

(defvar packages/declared nil
  "Packages declared by the loaded configuration modules.")

(defvar packages/bootstrap-mode nil
  "When non-nil, install declarations as they are evaluated.
Set this before loading the configuration for a one-shot bootstrap pass.")

(defvar packages--archives-refreshed nil)
(defvar packages--installed-count 0)

(setq package-user-dir
      (cache/folder "elpa")
      ;; Load one generated autoload file instead of opening every package's
      ;; autoload file during startup.  Bootstrap refreshes it after changes.
      package-quickstart t
      package-quickstart-file (cache/file "package-quickstart.el")
      package-archives
      '(("gnu" . "https://elpa.gnu.org/packages/")
        ;; The official host can accept a connection and then stall mid-transfer.
        ;; Use a nearby HTTPS mirror so a cold bootstrap cannot block startup.
        ("nongnu" . "https://mirrors.tuna.tsinghua.edu.cn/elpa/nongnu/")
        ("melpa" . "https://melpa.org/packages/"))
      package-archive-priorities
      '(("gnu" . 30)
        ("nongnu" . 20)
        ("melpa" . 10))
      use-package-always-ensure nil
      use-package-expand-minimally t)

;; Pins must precede `package-initialize', which reads cached archive metadata.
;; NonGNU's old Smartparens build lacks its dependency and Tree-sitter rules.
(add-to-list 'package-pinned-packages '(smartparens . "melpa"))

(make-directory package-user-dir t)
(package-initialize)
(require 'use-package)

(defun packages--package-list (package-arguments)
  "Return package symbols from PACKAGE-ARGUMENTS."
  (cl-mapcan (lambda (argument)
               (if (listp argument)
                   argument
                 (list argument)))
             package-arguments))

(defun packages--refresh-archives ()
  "Refresh package archive metadata at most once per bootstrap pass."
  (unless packages--archives-refreshed
    (package-refresh-contents)
    (setq packages--archives-refreshed t)))

(defun packages--install (package)
  "Install PACKAGE without changing the selected list immediately."
  (unless (package-installed-p package)
    (unless (assq package package-archive-contents)
      (packages--refresh-archives))
    (package-install package 'dont-select)
    (setq packages--installed-count (1+ packages--installed-count))))

(defun packages/declare (&rest package-arguments)
  "Declare packages used by the current configuration module.
Declarations are collected without network access during normal startup.
When `packages/bootstrap-mode' is non-nil, missing packages are installed
as the declarations are evaluated."
  (dolist (package (packages--package-list package-arguments))
    (unless (symbolp package)
      (signal 'wrong-type-argument (list 'symbolp package)))
    (add-to-list 'packages/declared package t)
    (when packages/bootstrap-mode
      (packages--install package)))
  packages/declared)

(defun packages/save-selection ()
  "Persist declared packages in `package-selected-packages'."
  (let* ((selection
          (delete-dups (append packages/declared package-selected-packages)))
         (changed (not (equal selection package-selected-packages))))
    (setq package-selected-packages selection)
    (customize-save-variable 'package-selected-packages
                             package-selected-packages)
    (when (and package-quickstart
               (fboundp 'package-quickstart-refresh)
               (or changed
                   (> packages--installed-count 0)
                   (not (file-readable-p package-quickstart-file))))
      (package-quickstart-refresh))
    (setq packages--installed-count 0)))

(defun packages/bootstrap ()
  "Install packages declared by the loaded configuration modules.
Run this interactively after loading the configuration, or set
`packages/bootstrap-mode' before loading it for a one-shot setup pass."
  (interactive)
  (unless packages/declared
    (user-error "No package declarations have been loaded"))
  (let ((packages/bootstrap-mode t)
        (missing-count 0))
    (setq packages--archives-refreshed nil
          packages--installed-count 0)
    (dolist (package packages/declared)
      (unless (package-installed-p package)
        (setq missing-count (1+ missing-count)))
      (packages--install package))
    (packages/save-selection)
    (message "Package bootstrap complete: %d declared, %d installed"
             (length packages/declared)
             missing-count)))


(provide 'packages)

;;; packages.el ends here
