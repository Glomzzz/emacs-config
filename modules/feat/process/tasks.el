;;; tasks.el --- Asynchronous task dashboard integration -*- lexical-binding: t; -*-

(let ((package-directory (expand-file-name "pkgs" user-emacs-directory)))
  (add-to-list 'load-path package-directory))

;; Keep the dashboard parser out of startup.  The first task command loads the
;; local package through these explicit autoloads.
(autoload 'task-dashboard "task-dashboard" nil t)
(autoload 'task-dashboard-run-shell-command "task-dashboard" nil t)

;; Keep task controls in an unused `C-c' namespace.  `C-c d' is already used
;; by the editing configuration, so it intentionally remains untouched.
(global-set-key (kbd "C-c T") #'task-dashboard)
(global-set-key (kbd "C-c C-T") #'task-dashboard-run-shell-command)

;; Compilation-error menu adapted from the hydra wiki's "Compilation" example.
;; The wiki also binds `C-x `' to the menu.  Here `C-x `' keeps its built-in
;; `next-error', and the menu lives on C-x C-h c.
(use-package compile
  :ensure nil
  :after hydra
  :bind (("C-x C-h c" . hydra-next-error/body))
  :hydra (hydra-next-error
          (:color red)
          "
Compilation errors: _j_ next  _k_ previous  _h_ first  _l_ last  _`_ next  _q_ quit"
          ("`" next-error)
          ("j" next-error)
          ("k" previous-error)
          ("h" first-error)
          ("l" (condition-case nil
                  (while t
                    (next-error))
                (user-error nil)))
          ("q" nil :color blue)))

;; Profiler menu adapted from the hydra wiki's "elisp profiling" example.  Its
;; s.el and dash.el helpers are replaced by plain Elisp, and the menu calls
;; `profiler-start' directly.  The hint names the profilers that are running.
(defun profiler/running-modes ()
  "Return the names of running profilers, or \"stopped\"."
  (let ((modes (delq nil (list (and (profiler-cpu-running-p) "cpu")
                               (and (profiler-memory-running-p) "mem")))))
    (if modes (mapconcat #'identity modes "+") "stopped")))

(use-package profiler
  :ensure nil
  :commands (profiler-start profiler-stop profiler-report profiler-reset
             profiler-find-profile profiler-find-profile-other-window
             profiler-find-profile-other-frame
             profiler-cpu-running-p profiler-memory-running-p)
  :after hydra
  :bind (("C-x C-h p" . hydra-profiler/body))
  :hydra (hydra-profiler
          (:color red :hint nil)
          "
elisp profiling (currently %s(profiler/running-modes))
 Start/stop: _s_ start (prompt)  _c_ cpu  _m_ memory  _b_ cpu+memory  _._ stop  _R_ reset  _C_ customize  _q_ quit
 Reports:    _r_ show report  _f_ find profile  _4_ other window  _5_ other frame"
          ("s" profiler-start)
          ("c" (profiler-start 'cpu))
          ("m" (profiler-start 'mem))
          ("b" (profiler-start 'cpu+mem))
          ("." profiler-stop)
          ("R" profiler-reset)
          ("C" (customize-group "profiler"))
          ("q" nil)
          ("r" profiler-report :color blue)
          ("f" profiler-find-profile :color blue)
          ("4" profiler-find-profile-other-window :color blue)
          ("5" profiler-find-profile-other-frame :color blue)))

;;; tasks.el ends here
