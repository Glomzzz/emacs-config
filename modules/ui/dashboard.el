;;; dashboard.el --- Daily actions and shortcut memory aid -*- lexical-binding: t; -*-

(require 'button)
(require 'cl-lib)

(defgroup dashboard nil
  "Daily actions and their normal Emacs shortcuts."
  :group 'convenience)

(defcustom dashboard/show-on-startup t
  "Show the dashboard at startup and in empty emacsclient frames.
Explicit file visits and initial buffer choices are left alone.  Restart
Emacs after changing this option; `dashboard/open' is always available."
  :type 'boolean :group 'dashboard)

(defconst dashboard--buffer-name "*Daily Dashboard*")

(defconst dashboard--actions
  '(("Files and projects"
     ("Open file" find-file "C-x C-f")
     ("Recent files" consult-recent-file "C-c r")
     ("Switch buffer" consult-buffer "C-x b")
     ("Switch project" project-switch-project "C-x p p")
     ("Find project file" project-find-file "C-x p f")
     ("Browse directory" dirvish-dwim "C-x d"))
    ("Search and tools"
     ("Search files (ripgrep)" consult-ripgrep "C-c s")
     ("Git status" magit-status "C-x g")
     ("Terminal in another window" vterm-other-window "C-c t")
     ("Process tasks" task-dashboard "C-c T"))
    ("Learn the keys"
     ("Run any command" execute-extended-command "M-x")
     ("Describe a key" describe-key "C-h k")
     ("List current bindings" describe-bindings "C-h b")
     ("Read manuals" consult-info "C-c i")))
  "Button labels, commands, and preferred existing global shortcuts.
These are launch actions, not a second set of dashboard-only shortcuts.")

(defconst dashboard--editing-keys
  '(("Save file" save-buffer "C-x C-s")
    ("Undo" undo "C-x u")
    ("Duplicate line" funcs/duplicate-line "C-,")
    ("Format buffer" funcs/format-buffer "C-c f")
    ("Complete at point" completion-at-point "C-M-i")
    ("Structural editing" nil "C-c p ?"))
  "Non-clickable reminders for commands used in editable buffers.
The structural-editing prefix is buffer-local, so it is shown literally.")

(defun dashboard--key-label (command preferred)
  "Return a real global shortcut for COMMAND, preferring PREFERRED.
Show M-x when the command is unbound instead of advertising a stale key."
  (cond
   ((null command) preferred)
   ((eq (lookup-key (current-global-map) (kbd preferred)) command) preferred)
   ((when-let* ((key (where-is-internal command (list (current-global-map)) t)))
      (key-description key)))
   (t (format "M-x %s" command))))

(defun dashboard--activate (button)
  "Run BUTTON's command interactively, honoring its normal prompts."
  (let ((command (button-get button 'dashboard-command)))
    (unless (commandp command)
      (user-error "Command %s is unavailable; run the package bootstrap" command))
    (call-interactively command)))

(defun dashboard/refresh ()
  "Refresh buttons and shortcut labels without loading tool packages."
  (interactive)
  (let ((inhibit-read-only t)
        (position (point)))
    (erase-buffer)
    (insert (propertize "emc | Daily dashboard\n" 'face 'bold)
            "Click a button or use TAB / RET.  Practise the key at left.\n\n")
    (dolist (section dashboard--actions)
      (insert (propertize (concat (car section) "\n") 'face 'bold))
      (pcase-dolist (`(,label ,command ,preferred) (cdr section))
        (insert "  ")
        (insert-text-button
         (format "%-14s %s" (dashboard--key-label command preferred) label)
         'dashboard-command command
         'action #'dashboard--activate
         'follow-link t
         'help-echo (format "Run %s (also available with the shortcut shown)" command))
        (insert "\n"))
      (insert "\n"))
    (insert (propertize "In an editing buffer (reminders, not buttons)\n" 'face 'bold))
    (pcase-dolist (`(,label ,command ,preferred) dashboard--editing-keys)
      (insert (format "  %-14s %s\n"
                      (dashboard--key-label command preferred) label)))
    (insert (format "\n%s: this dashboard    g: refresh    q: leave\n"
                    (dashboard--key-label #'dashboard/open "C-c D")))
    (goto-char (min position (point-max)))
    (set-buffer-modified-p nil)))

(defvar dashboard-mode-map
  (let ((map (make-sparse-keymap)))
    (set-keymap-parent map special-mode-map)
    (define-key map (kbd "TAB") #'forward-button)
    (define-key map (kbd "<backtab>") #'backward-button)
    (define-key map (kbd "g") #'dashboard/refresh)
    map)
  "Dashboard navigation; daily commands keep their normal global keys.")

(define-derived-mode dashboard-mode special-mode "Daily Dashboard"
  "Clickable daily actions with shortcuts to learn and reuse elsewhere."
  (setq-local truncate-lines nil))

(defun dashboard/buffer ()
  "Return the refreshed dashboard, using the caller's working directory.
This is the initial-buffer callback for empty emacsclient frames."
  (let ((directory default-directory)
        (buffer (get-buffer-create dashboard--buffer-name)))
    (with-current-buffer buffer
      (unless (derived-mode-p 'dashboard-mode) (dashboard-mode))
      (setq default-directory directory)
      (dashboard/refresh))
    buffer))

(defun dashboard/open ()
  "Open the daily dashboard in the selected window."
  (interactive)
  (switch-to-buffer (dashboard/buffer)))

(defun dashboard/startup ()
  "Show daily actions only when startup has not selected another buffer.
Install the client callback after command-line file handling, so explicit
startup files are neither displaced nor split alongside a dashboard."
  (when (and dashboard/show-on-startup
             (not noninteractive)
             (null initial-buffer-choice))
    (setq initial-buffer-choice #'dashboard/buffer)
    (when (and (not (daemonp))
               (eq (current-buffer) (get-buffer "*scratch*"))
               (not (buffer-modified-p))
               (not (cl-some (lambda (window)
                               (buffer-file-name (window-buffer window)))
                             (window-list))))
      (dashboard/open))))

(global-set-key (kbd "C-c D") #'dashboard/open)
(add-hook 'emacs-startup-hook #'dashboard/startup)

(provide 'dashboard)
;;; dashboard.el ends here
