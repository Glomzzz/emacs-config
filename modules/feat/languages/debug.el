;;; debug.el --- Debug Adapter Protocol integration -*- lexical-binding: t; -*-

(require 'packages)
(require 'seq)

(defvar dape-info-buffer-window-groups)

(defvar debug/dape-language-configs nil
  "Dape configurations registered by language-specific modules.

Each entry is an alist element of the form (NAME . CONFIG), where NAME is a
symbol and CONFIG is a Dape configuration plist.  The list is kept separately
from Dape so language modules can register configurations before Dape loads.")

(defun debug/apply-language-configs ()
  "Apply registered language configurations to `dape-configs'."
  (when (boundp 'dape-configs)
    (dolist (entry debug/dape-language-configs)
      (setf (alist-get (car entry) dape-configs)
            (cdr entry)))))

(defun debug/register-config (name config)
  "Register Dape CONFIG under NAME.

Language modules can call this function without loading Dape eagerly.  Dape's
built-in configurations are not copied here; use this for adapters or launch
conventions that are specific to a project or language mode.  A matching NAME
intentionally replaces an existing Dape entry."
  (unless (symbolp name)
    (signal 'wrong-type-argument (list 'symbolp name)))
  (setf (alist-get name debug/dape-language-configs) config)
  (if (featurep 'dape)
      (debug/apply-language-configs)
    (with-eval-after-load 'dape
      (debug/apply-language-configs)))
  name)

(defun debug/show-info (mode)
  "Display and select Dape's info tab for MODE using its public UI commands."
  (require 'dape)
  (dape-info)
  (let* ((group (seq-find
                 (lambda (group)
                   (seq-some (lambda (spec) (eq (car (ensure-list spec)) mode)) group))
                 dape-info-buffer-window-groups))
         (modes (mapcar (lambda (spec) (car (ensure-list spec))) group))
         (window
          (seq-find
           (lambda (window)
             (with-current-buffer (window-buffer window)
               (apply #'derived-mode-p modes)))
           (window-list))))
    (unless window
      (user-error "No Dape info window for %s" mode))
    (select-window window)
    ;; Scope tabs depend on the adapter, so stop if the tabs cycle without
    ;; finding the requested mode (for example before the first stop).
    (let ((first (current-buffer)))
      (unless (derived-mode-p mode)
        (dape-info-buffer-tab)
        (set-buffer (window-buffer window))
        (while (and (not (derived-mode-p mode))
                    (not (eq (current-buffer) first)))
          (dape-info-buffer-tab)
          (set-buffer (window-buffer window))))
      (unless (derived-mode-p mode)
        (user-error "No %s information is available in this session" mode)))))

(defun debug/locals ()
  "Show the current Dape scope, normally local variables."
  (interactive)
  (debug/show-info 'dape-info-scope-mode))

(defun debug/breakpoints ()
  "Show Dape's breakpoint list."
  (interactive)
  (debug/show-info 'dape-info-breakpoints-mode))

(defun debug/watches ()
  "Show Dape's watched expressions."
  (interactive)
  (debug/show-info 'dape-info-watch-mode))

(defun debug/edit-configurations ()
  "Edit the Dape launch configurations through Customize."
  (interactive)
  (require 'dape)
  (customize-variable 'dape-configs))

(defun debug/evaluate-expression ()
  "Evaluate an expression using Dape's watch context.
Use Dape's interactive argument reader to select the connection and
expression.  The watch context evaluates plain expressions even when an
adapter's REPL context expects debugger commands, as GDB does."
  (interactive)
  (require 'dape)
  (apply #'dape-evaluate-expression
         (append (advice-eval-interactive-spec
                  (cadr (interactive-form #'dape-evaluate-expression)))
                 '("watch"))))

(defun debug/evaluate-region ()
  "Evaluate the active region in the current Dape session."
  (interactive)
  (unless (use-region-p)
    (user-error "Select a region to evaluate"))
  (debug/evaluate-expression))

(defun debug/evaluate-symbol ()
  "Evaluate the symbol at point in the current Dape session without prompting."
  (interactive)
  (let ((bounds (bounds-of-thing-at-point 'symbol))
        (transient-mark-mode t))
    (unless bounds
      (user-error "No symbol at point"))
    (save-mark-and-excursion
      (goto-char (car bounds))
      (push-mark (cdr bounds) t t)
      (debug/evaluate-region))))

(packages/declare 'dape)
(use-package dape
  :ensure nil
  :commands (dape
             dape-breakpoint-toggle
             dape-breakpoint-remove-at-point
             dape-breakpoint-remove-all
             dape-breakpoint-expression
             dape-breakpoint-hits
             dape-breakpoint-log
             dape-breakpoint-function
             dape-breakpoint-load
             dape-breakpoint-save
             dape-continue
             dape-next
             dape-step-in
             dape-step-out
             dape-pause
             dape-restart-frame
             dape-restart
             dape-select-session
             dape-select-thread
             dape-select-stack
             dape-stack-select-up
             dape-stack-select-down
             dape-info
             dape-info-buffer-tab
             dape-repl
             dape-evaluate-expression
             dape-watch-dwim
             dape-disconnect-quit
             dape-kill)
  :after hydra
  :bind ("C-x C-h d" . hydra-dape/body)
  ;; Hydra calls Dape heads with `this-command' set to the Dape command.
  ;; Restore the actual Hydra wrapper before Repeat's post-command hook so
  ;; Dape's repeat map cannot take precedence over this persistent menu.
  :hydra (hydra-dape
          (:color pink :hint nil :foreign-keys run
           :after-exit (setq this-command real-this-command))
          "
 Stepping^^          Switch / inspect^^       Breakpoints
 -----------------------------------------------------------------------
 _n_ next            _ss_ session             _bb_ toggle   _bd_ delete
 _i_ step in         _st_ thread              _bc_ condition _bh_ hit count
 _o_ step out        _sf_ stack frame         _bl_ log      _bf_ function
 _c_ continue        _su_ up / _sd_ down      _bs_ save     _bL_ load
 _p_ pause           _sl_ locals              _bD_ delete all
 _r_ restart frame   _sb_ breakpoints         _se_ watches

 Debug: _dd_ launch/history  _ds_ restart session  _de_ edit configurations
 Eval:  _ee_ expression  _er_ region  _es_ symbol  _ea_ toggle watch
 UI:    _ui_ info panes  _ur_ REPL
 _k_ terminate  _Q_ disconnect  _q_ leave menu"
          ("n" dape-next)
          ("i" dape-step-in)
          ("o" dape-step-out)
          ("c" dape-continue)
          ("p" dape-pause)
          ("r" dape-restart-frame)
          ("ss" dape-select-session)
          ("st" dape-select-thread)
          ("sf" dape-select-stack)
          ("su" dape-stack-select-up)
          ("sd" dape-stack-select-down)
          ("sl" debug/locals :exit t)
          ("sb" debug/breakpoints :exit t)
          ("se" debug/watches :exit t)
          ("bb" dape-breakpoint-toggle)
          ("bd" dape-breakpoint-remove-at-point)
          ("bD" dape-breakpoint-remove-all)
          ("bc" dape-breakpoint-expression)
          ("bh" dape-breakpoint-hits)
          ("bl" dape-breakpoint-log)
          ("bf" dape-breakpoint-function)
          ("bs" dape-breakpoint-save)
          ("bL" dape-breakpoint-load)
          ("dd" dape :exit t)
          ("ds" dape-restart)
          ("de" debug/edit-configurations :exit t)
          ("ee" debug/evaluate-expression)
          ("er" debug/evaluate-region)
          ("es" debug/evaluate-symbol)
          ("ea" dape-watch-dwim)
          ("ui" dape-info :exit t)
          ("ur" dape-repl :exit t)
          ("k" dape-kill :exit t)
          ("Q" dape-disconnect-quit :exit t)
          ("q" nil :exit t))
  :custom
  ;; Keep downloaded adapters and breakpoint state in the shared cache.
  (dape-adapter-dir (cache/folder "debug-adapters"))
  (dape-default-breakpoints-file (cache/file "dape-breakpoints"))
  ;; A side window keeps source buffers focused while debugging.
  (dape-buffer-window-arrangement 'right)
  :config
  (debug/apply-language-configs))

;;; debug.el ends here
