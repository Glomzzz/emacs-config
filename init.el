;;; init.el --- Module loader for Glom's Emacs configuration -*- lexical-binding: t; -*-

(setq custom-file (expand-file-name "theme.el" user-emacs-directory))

(defconst my/modules-dir
  (expand-file-name "modules/" user-emacs-directory))

;; Load order matters only for the modules listed here: shared helpers
;; and package infrastructure must be defined before dependent modules.
;; The list is grouped by directory for readability:
;;
;;   core/    bootstrap, global defaults, UI and theme
;;   apps/    whole-window applications (task dashboard, file manager, AI)
;;   editor/  editing subsystems (completion, LSP, VC, terminal)
;;   lang/    per-language configuration
;;
;; Any .el file under modules/ that is NOT listed here is discovered
;; automatically and loaded after these, sorted by path -- adding a new
;; module is just dropping a file into the tree, no init.el edit needed.
(defconst my/module-load-order
  '("core/bootstrap"
    "core/core"
    "apps/async-tasks"
    "core/ui"
    "core/appearance"
    "apps/async-tasks"
    "apps/dired"
    "apps/mounts"
    "apps/dirvish"
    "editor/version-control"
    "editor/completion"
    "editor/lsp"
    "editor/terminal"
    "apps/ai"
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

(defun my/module-discovered-files ()
  "Return module files not listed in `my/module-load-order', sorted.
Modules are plain .el files under `my/modules-dir'."
  (let (files)
    (dolist (file (directory-files-recursively
                   my/modules-dir "\\.el\\'" nil nil nil))
      (let ((relative (file-relative-name file my/modules-dir)))
        (unless (member relative my/module-load-order)
          (push relative files))))
    (sort files #'string<)))

(defun my/module-load-sequence ()
  "Return the module load sequence: ordered modules, then the rest."
  (append my/module-load-order (my/module-discovered-files)))

(defun my/load-module (relative-path)
  "Load RELATIVE-PATH from `my/modules-dir'."
  (load (expand-file-name relative-path my/modules-dir) nil 'nomessage))

;; Load order matters: shared helpers are defined before dependent modules.
(condition-case error
    (dolist (module (my/module-load-sequence))
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
