;;; scala.el --- Scala editing, builds, and Metals integration -*- lexical-binding: t; -*-

(declare-function eglot-ensure "eglot" ())

(use-package scala-mode
  :mode (("\\.scala\\'" . scala-mode)
         ("\\.sbt\\'" . scala-mode)
         ("\\.sc\\'" . scala-mode))
  :interpreter ("scala" . scala-mode)
  :custom
  (scala-indent:step 2))

(use-package jarchive
  :hook (after-init . jarchive-mode))

(defun my/scala-lsp-server-available-p ()
  "Return non-nil when Metals is installed."
  (my/executable-available-p "metals" "metals-emacs"))

(defun my/scala-maybe-eglot-ensure ()
  "Start Eglot when Metals is available."
  (when (my/scala-lsp-server-available-p)
    (eglot-ensure)))

(defun my/scala-standalone-command ()
  "Return a runner or compiler command for a standalone Scala file."
  (when (and buffer-file-name
             (not (string-equal (file-name-extension buffer-file-name) "sbt")))
    (cond
     ((executable-find "scala-cli")
      (format "scala-cli run %s"
              (shell-quote-argument buffer-file-name)))
     ((executable-find "scalac")
      (format "scalac -d %s %s"
              (shell-quote-argument temporary-file-directory)
              (shell-quote-argument buffer-file-name))))))

(defun my/scala-buffer-setup ()
  "Set Scala indentation, completion, and compilation defaults."
  (when (boundp 'scala-indent:step)
    (setq-local scala-indent:step 2))
  (when (boundp 'corfu-auto-trigger)
    (setq-local corfu-auto-trigger ".${"))
  (my/jvm-buffer-setup (my/scala-standalone-command)))

(add-hook 'scala-mode-hook #'my/scala-buffer-setup)
(add-hook 'scala-mode-hook #'my/scala-maybe-eglot-ensure)

;;; scala.el ends here
