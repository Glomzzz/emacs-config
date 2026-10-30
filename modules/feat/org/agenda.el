;;; agenda.el --- Org agenda views and skip rules -*- lexical-binding: t; -*-

(require 'cl-lib)

(declare-function org-end-of-subtree "org" (&optional invisible-ok to-heading))
(declare-function org-entry-end-position "org" ())
(declare-function org-entry-get "org" (pom property &optional inherit literal-nil))
(declare-function org-get-priority "org" (s))
(declare-function org-get-tags "org" (&optional pos local))
(declare-function org-get-todo-state "org" ())
(declare-function org-up-heading-safe "org" ())
(declare-function outline-next-heading "outline" ())
(defvar org-done-keywords)
(defvar org-lowest-priority)
(defvar org-outline-regexp-bol)

(defcustom org/hide-scheduled-and-waiting-next-tasks t
  "Non-nil hides scheduled, deadline, and WAITING tasks from the Projects view."
  :type 'boolean
  :group 'org-config)

;; The skip functions below return nil to keep the entry at point, or a buffer
;; position to skip to.  Skipping one entry resumes at the next heading, so the
;; children of a skipped project still get their own checks.

(defun org--subtree-end ()
  "Return the end position of the subtree at point."
  (save-excursion
    (org-end-of-subtree t)
    (point)))

(defun org--next-heading-position ()
  "Return the position of the heading after the current one, or the buffer end."
  (save-excursion
    (if (outline-next-heading)
        (point)
      (point-max))))

(defun org--descendant-values (end function)
  "Return the values of FUNCTION at each heading between point and END.
Point must be on a heading.  Only headings below it are visited."
  (save-excursion
    (let (values)
      (forward-line 1)
      ;; Moving past the last child can put point beyond END, which is not a
      ;; valid search bound, so check the position before each search.
      (while (and (< (point) end)
                  (re-search-forward org-outline-regexp-bol end t))
        (beginning-of-line)
        (push (funcall function) values)
        (forward-line 1))
      (nreverse values))))

(defun org--habit-p ()
  "Return non-nil when the heading at point has the habit STYLE."
  (equal (org-entry-get nil "STYLE") "habit"))

(defun org--waiting-p ()
  "Return non-nil when the heading at point has the WAITING tag.
Inherited tags count, so a WAITING parent hides its children."
  (member "WAITING" (org-get-tags)))

(defun org--project-p ()
  "Return non-nil when the heading at point is a project.
A project is a TODO heading with at least one TODO heading below it."
  (and (org-get-todo-state)
       (cl-some #'identity
                (org--descendant-values (org--subtree-end)
                                        #'org-get-todo-state))))

(defun org--next-task-p ()
  "Return non-nil when the heading at point is a NEXT task without WAITING."
  (and (equal (org-get-todo-state) "NEXT")
       (not (org--waiting-p))))

(defun org--has-next-task-p ()
  "Return non-nil when a NEXT task appears below the heading at point."
  (cl-some #'identity
           (org--descendant-values (org--subtree-end) #'org--next-task-p)))

(defun org--in-project-p ()
  "Return non-nil when a heading above the one at point is a project."
  (save-excursion
    (let (found)
      (while (and (not found) (org-up-heading-safe))
        (setq found (org--project-p)))
      found)))

(defun org--current-and-previous-months ()
  "Return the current and the previous month as \"YYYY-MM\" strings."
  (let* ((now (decode-time))
         (year (decoded-time-year now))
         (month (decoded-time-month now)))
    (list (format "%04d-%02d" year month)
          (if (= month 1)
              (format "%04d-%02d" (1- year) 12)
            (format "%04d-%02d" year (1- month))))))

(defun org--body-has-recent-timestamp-p ()
  "Return non-nil when the entry body at point has a recent timestamp.
Recent means dated in the current or the previous month.  Child headings are
not part of the body."
  (let ((months (org--current-and-previous-months))
        (end (org-entry-end-position)))
    (save-excursion
      (forward-line 1)
      (and (< (point) end)
           (catch 'found
             (while (re-search-forward
                     "[[<]\\([0-9]\\{4\\}-[0-9]\\{2\\}\\)-[0-9]\\{2\\}"
                     end t)
               (when (member (match-string 1) months)
                 (throw 'found t)))
             nil)))))

(defun org/skip-subtree-if-habit ()
  "Skip the agenda subtree at point when its heading is a habit."
  (when (org--habit-p)
    (org--subtree-end)))

(defun org/skip-subtree-if-priority (priority)
  "Skip the agenda subtree at point when its priority is PRIORITY.
PRIORITY is a character such as ?A, ?B, or ?C."
  (when (= (* 1000 (- org-lowest-priority priority))
           (org-get-priority (thing-at-point 'line t)))
    (org--subtree-end)))

(defun org/skip-non-stuck-projects ()
  "Skip every entry except projects that have no NEXT task below them."
  (save-restriction
    (widen)
    (if (and (org--project-p)
             (not (org--has-next-task-p)))
        nil
      (org--next-heading-position))))

(defun org/skip-projects-and-habits-and-single-tasks ()
  "Skip every entry except NEXT tasks that belong to a project.
When `org/hide-scheduled-and-waiting-next-tasks' is non-nil, WAITING tasks are
skipped too.  Scheduled and deadline items are left to the agenda's
`org-agenda-todo-ignore-*' options."
  (save-restriction
    (widen)
    (if (and (not (org--project-p))
             (not (org--habit-p))
             (org--in-project-p)
             (not (and org/hide-scheduled-and-waiting-next-tasks
                       (org--waiting-p))))
        nil
      (org--next-heading-position))))

(defun org/skip-non-archivable-tasks ()
  "Skip every entry except DONE tasks without a recent timestamp."
  (save-restriction
    (widen)
    (if (and (member (org-get-todo-state) org-done-keywords)
             (not (org--body-has-recent-timestamp-p)))
        nil
      (org--next-heading-position))))

(defun org/agenda-daily ()
  "Show today's agenda with the high-priority and all-TODO blocks."
  (interactive)
  (org-agenda nil "d"))

(defun org/agenda-projects ()
  "Show the Projects agenda: refile, stuck projects, and project tasks."
  (interactive)
  (org-agenda nil "p"))

(use-package org
  :ensure nil
  :defer t
  :after hydra
  :bind (("C-c a" . org-agenda)
         ("C-x C-h A" . hydra-org-agenda/body))
  ;; C-x C-h A groups the agenda views and capture into one menu.
  :hydra (hydra-org-agenda
          (:color blue :hint nil)
          "
 _a_: dispatcher  _d_: daily  _p_: projects  _t_: TODO list  _m_: tags  _s_: search  _c_: capture  _q_: quit"
          ("a" org-agenda)
          ("d" org/agenda-daily)
          ("p" org/agenda-projects)
          ("t" org-todo-list)
          ("m" org-tags-view)
          ("s" org-search-view)
          ("c" org-capture)
          ("q" nil "quit"))
  :custom
  (org-agenda-files org/agenda-files)
  ;; Keep blocked tasks at full brightness.
  (org-agenda-dim-blocked-tasks nil)
  (org-agenda-compact-blocks t)
  (org-agenda-span 7)
  (org-agenda-start-day "-2d")
  (org-agenda-start-on-weekday nil)
  ;; The default `auto' column setting does not work well here.
  (org-agenda-tags-column -86)
  (org-agenda-custom-commands
   '(("d" "Daily agenda and all TODOs"
      ((tags "PRIORITY=\"A\""
             ((org-agenda-skip-function '(org-agenda-skip-entry-if 'todo 'done))
              (org-agenda-overriding-header "High-priority unfinished tasks:")))
       (agenda "" ((org-agenda-ndays 1)))
       (alltodo ""
                ((org-agenda-skip-function
                  '(or (org/skip-subtree-if-habit)
                       (org/skip-subtree-if-priority ?A)
                       (org-agenda-skip-if nil '(scheduled deadline))))
                 (org-agenda-overriding-header "ALL normal priority tasks:"))))
      ((org-agenda-compact-blocks t)))
     ("p" "Projects"
      ((agenda "" nil)
       (tags "REFILE"
             ((org-agenda-overriding-header "Tasks to Refile")
              (org-tags-match-list-sublevels nil)))
       (tags-todo "-CANCELLED/!"
                  ((org-agenda-overriding-header "Stuck Projects")
                   (org-agenda-skip-function 'org/skip-non-stuck-projects)
                   (org-agenda-sorting-strategy '(category-keep))))
       (tags-todo "-CANCELLED/!NEXT"
                  ((org-agenda-overriding-header
                    (concat "Project Next Tasks"
                            (if org/hide-scheduled-and-waiting-next-tasks
                                ""
                              " (including WAITING and SCHEDULED tasks)")))
                   (org-agenda-skip-function
                    'org/skip-projects-and-habits-and-single-tasks)
                   (org-tags-match-list-sublevels t)
                   (org-agenda-todo-ignore-scheduled
                    org/hide-scheduled-and-waiting-next-tasks)
                   (org-agenda-todo-ignore-deadlines
                    org/hide-scheduled-and-waiting-next-tasks)
                   (org-agenda-todo-ignore-with-date
                    org/hide-scheduled-and-waiting-next-tasks)
                   (org-agenda-sorting-strategy
                    '(todo-state-down effort-up category-keep))))
       (tags "-REFILE/"
             ((org-agenda-overriding-header "Tasks to Archive")
              (org-agenda-skip-function 'org/skip-non-archivable-tasks)
              (org-tags-match-list-sublevels nil))))
      nil))))

;;; agenda.el ends here
