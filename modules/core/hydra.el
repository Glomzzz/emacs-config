;;; hydra.el --- Shared repeatable key menus -*- lexical-binding: t; -*-

(require 'packages)

;; Hydra supplies `defhydra', and `use-package-hydra' adds the `:hydra' keyword
;; that feature modules use for their menus.  Keep both in core so feature
;; modules can load after them.  Menus live under the `C-x C-h' prefix, next to
;; the built-in help keys.
(packages/declare 'hydra 'use-package-hydra)
(use-package hydra
  :ensure nil)
(use-package use-package-hydra
  :ensure nil)

;;; hydra.el ends here
