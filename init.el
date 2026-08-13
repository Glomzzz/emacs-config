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
    "lang/koka"))

(defun my/load-module (relative-path)
  "Load RELATIVE-PATH from `my/modules-dir' in documented order."
  (load (expand-file-name relative-path my/modules-dir) nil 'nomessage))

;; Load order matters: shared helpers are defined before dependent modules.
(dolist (module my/module-load-order)
  (my/load-module module))

;;; init.el ends here
