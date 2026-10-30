;;; projects.el --- Projectile commands with Counsel completion -*- lexical-binding: t; -*-

(require 'packages)
(require 'project)

(defun projects/keep-project-el-discovery ()
  "Keep project.el's existing root discovery when enabling Projectile.
Language modules register nested project markers with project.el, which
Eglot and the existing Consult/Dashboard commands continue to use."
  (remove-hook 'project-find-functions #'project-projectile))

(packages/declare 'projectile)
(use-package projectile
  :ensure nil
  :demand t
  :bind (:map projectile-mode-map
              ("C-c P" . projectile-command-map))
  :custom
  (projectile-mode-line-prefix " Projectile")
  (projectile-dynamic-mode-line nil)
  (projectile-track-known-projects-automatically nil)
  ;; Keep file indexes in memory; persistent indexes otherwise live in projects.
  (projectile-enable-caching t)
  :hook (projectile-mode . projects/keep-project-el-discovery))

(packages/declare 'counsel-projectile)
(use-package counsel-projectile
  :ensure nil
  :after (projectile hydra)
  :demand t
  :bind (("C-x C-h P" . hydra-proj/body)
         :map projectile-command-map
         ("." . hydra-proj/body))
  :hydra (hydra-proj
          (:exit t :hint nil)
          "
 Projectile: _p_ switch project  _f_ file  _d_ directory  _b_ buffer
 _SPC_ files/buffers  _s_ ripgrep
 Tasks: _c_ compile  _t_ test  _r_ run
 Projects: _a_ add  _x_ remove known    Buffers: _S_ save all  _k_ kill
 Cache: _i_ invalidate    _q_ quit"
          ("p" counsel-projectile-switch-project)
          ("f" counsel-projectile-find-file)
          ("d" counsel-projectile-find-dir)
          ("b" counsel-projectile-switch-to-buffer)
          ("SPC" counsel-projectile)
          ("s" counsel-projectile-rg)
          ("c" projectile-compile-project)
          ("t" projectile-test-project)
          ("r" projectile-run-project)
          ("a" projectile-add-known-project)
          ("x" projectile-remove-known-project)
          ("S" projectile-save-project-buffers)
          ("k" projectile-kill-buffers)
          ("i" projectile-invalidate-cache)
          ("q" nil))
  :config
  ;; This enables Projectile and its command remappings.  Ivy is used by
  ;; these commands directly; ordinary minibuffers keep Vertico.
  (counsel-projectile-mode 1))

;;; projects.el ends here
