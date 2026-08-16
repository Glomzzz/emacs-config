;;; init.el --- Module loader for Glom's Emacs configuration -*- lexical-binding: t; -*-

(setq custom-file (expand-file-name "theme.el" user-emacs-directory))

(defconst my/modules-dir
  (expand-file-name "modules/" user-emacs-directory))

(defconst my/module-load-order
  '("bootstrap"
    "core"
    "async-tasks"
    "ui"
    "appearance"
    "file-manager"
    "version-control"
    "completion"
    "lsp"
    "terminal"
    "ai"
    "lang/fish"
    "lang/scheme"
    "lang/racket"
    "lang/rust"
    "lang/jvm"
    "lang/java"
    "lang/kotlin"
    "lang/scala"
    "lang/ocaml"
    "lang/flix-mode"
    "lang/flix"
    "lang/python"
    "lang/javascript"
    "lang/typst"
    "lang/markdown"
    "lang/leetcode"
    "lang/nix"
    "lang/koka"
    "lang/ryzenbit"))

(defun my/load-module (relative-path)
  "Load RELATIVE-PATH from `my/modules-dir' in documented order."
  (load (expand-file-name relative-path my/modules-dir) nil 'nomessage))

;; Load order matters: shared helpers are defined before dependent modules.
(condition-case error
    (dolist (module my/module-load-order)
      (my/load-module module))
  (error
   ;; A daemon with a half-loaded config looks healthy but serves stale
   ;; definitions (void-function errors on every client call, as the
   ;; launcher's restart probes rely on modules that never loaded).
   ;; Refuse to start instead: systemd marks the service failed and the
   ;; real error lands in the journal.
   (when (daemonp)
     (message "Emacs daemon refusing to start: config module failed to load: %s"
              (error-message-string error))
     (backtrace)
     (kill-emacs 1))
   ;; Interactive sessions keep Emacs' usual behavior: report the error
   ;; and continue with the modules loaded so far.
   (signal (car error) (cdr error))))

;;; init.el ends here
