;;; java.el --- Java editing, builds, and Eglot integration -*- lexical-binding: t; -*-

(declare-function eglot-ensure "eglot" ())

(defun my/java-lsp-server-available-p ()
  "Return non-nil when a Java language server is installed."
  (my/executable-available-p "jdtls" "java-language-server"))

(defun my/java-maybe-eglot-ensure ()
  "Start Eglot when a Java language server is available."
  (when (my/java-lsp-server-available-p)
    (eglot-ensure)))

(defun my/java-buffer-setup ()
  "Set Java indentation and a useful compilation command."
  (setq-local c-basic-offset 4)
  (when (boundp 'java-ts-mode-indent-offset)
    (setq-local java-ts-mode-indent-offset 4))
  (my/jvm-buffer-setup
   (when (and buffer-file-name (executable-find "javac"))
     (format "javac %s" (shell-quote-argument buffer-file-name)))))

(add-hook 'java-mode-hook #'my/java-buffer-setup)
(add-hook 'java-mode-hook #'my/java-maybe-eglot-ensure)
(add-hook 'java-ts-mode-hook #'my/java-buffer-setup)
(add-hook 'java-ts-mode-hook #'my/java-maybe-eglot-ensure)

;;; java.el ends here
