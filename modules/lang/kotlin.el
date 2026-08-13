;;; kotlin.el --- Kotlin modes, builds, and Eglot integration -*- lexical-binding: t; -*-

(defvar eglot-server-programs)
(declare-function eglot-alternatives "eglot" (alternatives))
(declare-function eglot-ensure "eglot" ())

(use-package kotlin-mode
  :mode "\\.kts?\\'"
  :interpreter ("kotlin" . kotlin-mode)
  :custom
  (kotlin-tab-width 4))

(use-package kotlin-ts-mode
  :commands kotlin-ts-mode
  :custom
  (kotlin-ts-mode-indent-offset 4))

(defun my/kotlin-eglot-command ()
  "Pick an available Kotlin language server."
  (eglot-alternatives
   '(("kotlin-lsp" "--stdio")
     ("kotlin-lsp.sh" "--stdio")
     ("kotlin-language-server"))))

(defun my/kotlin-lsp-server-available-p ()
  "Return non-nil when a Kotlin language server is installed."
  (my/executable-available-p
   "kotlin-lsp" "kotlin-lsp.sh" "kotlin-language-server"))

(defun my/kotlin-maybe-eglot-ensure ()
  "Start Eglot when a Kotlin language server is available."
  (when (my/kotlin-lsp-server-available-p)
    (my/eglot-ensure-idle)))

(defun my/kotlin-standalone-command ()
  "Return a compiler command for the current standalone Kotlin file."
  (when (and buffer-file-name (executable-find "kotlinc"))
    (if (string-equal (file-name-extension buffer-file-name) "kts")
        (format "kotlinc -script %s"
                (shell-quote-argument buffer-file-name))
      (format "kotlinc %s -d %s"
              (shell-quote-argument buffer-file-name)
              (shell-quote-argument
               (expand-file-name "emacs-kotlin.jar"
                                 temporary-file-directory))))))

(defun my/kotlin-buffer-setup ()
  "Set Kotlin indentation and compilation defaults."
  (when (boundp 'kotlin-tab-width)
    (setq-local kotlin-tab-width 4))
  (when (boundp 'kotlin-ts-mode-indent-offset)
    (setq-local kotlin-ts-mode-indent-offset 4))
  (my/jvm-buffer-setup (my/kotlin-standalone-command)))

(add-hook 'kotlin-mode-hook #'my/kotlin-buffer-setup)
(add-hook 'kotlin-mode-hook #'my/kotlin-maybe-eglot-ensure)
(add-hook 'kotlin-ts-mode-hook #'my/kotlin-buffer-setup)
(add-hook 'kotlin-ts-mode-hook #'my/kotlin-maybe-eglot-ensure)

(with-eval-after-load 'eglot
  (add-to-list 'eglot-server-programs
               `((kotlin-mode kotlin-ts-mode)
                 . ,(my/kotlin-eglot-command))))

;;; kotlin.el ends here
