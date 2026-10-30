;;; org-tests.el --- Org module contract -*- lexical-binding: t; -*-

(require 'ert)
(require 'org)
(require 'org-agenda)
(require 'org-capture)

(defmacro org-test/with-buffer (content &rest body)
  "Run BODY in an Org buffer holding CONTENT, with point at the start."
  (declare (indent 1) (debug t))
  `(with-temp-buffer
     (org-mode)
     (insert ,content)
     (goto-char (point-min))
     ,@body))

(defun org-test/skip-at (heading function)
  "Call FUNCTION with point on the heading whose text contains HEADING."
  (goto-char (point-min))
  (should (re-search-forward (concat "^\\*+ .*" (regexp-quote heading)) nil t))
  (beginning-of-line)
  (funcall function))

(defun org-test/head-runs-p (keymap key command)
  "Return non-nil when hydra KEYMAP runs COMMAND for KEY.
Hydra wraps each head in a generated function whose name ends with the
command, optionally followed by `-and-exit'."
  (let ((entry (lookup-key keymap (kbd key))))
    (and (symbolp entry)
         (string-match-p (concat "/" (regexp-quote (symbol-name command))
                                 "\\(?:-and-exit\\)?\\'")
                         (symbol-name entry)))))

(defconst org-test/projects-sample
  "* TODO Stuck project
** TODO Waiting for reply
* TODO Active project
** NEXT Write the draft
** NEXT Tagged waiting :WAITING:
** NEXT Daily habit
:PROPERTIES:
:STYLE: habit
:END:
* NEXT Single task
* TODO Habit
:PROPERTIES:
:STYLE: habit
:END:
"
  "Headings covering projects, NEXT tasks, habits, and single tasks.")

(ert-deftest config-test/org-keys-are-bound ()
  (should (eq (key-binding (kbd "C-c a")) 'org-agenda))
  (should (eq (key-binding (kbd "C-c c")) 'org-capture))
  (should (eq (lookup-key org-mode-map (kbd "C-c C-q")) 'counsel-org-tag))
  (should (eq (key-binding (kbd "C-c n f")) 'org-roam-node-find))
  (should (eq (lookup-key org-mode-map (kbd "C-c n i")) 'org-roam-node-insert))
  (should (eq (lookup-key org-mode-map (kbd "C-c b")) 'org-cite-insert))
  (should (eq (key-binding (kbd "C-c B")) 'citar-open)))

(ert-deftest config-test/org-state-stays-out-of-the-repository ()
  (let ((repository (expand-file-name user-emacs-directory)))
    (dolist (file (list org-id-locations-file
                        org-clock-persist-file
                        org-roam-db-location))
      (should-not (string-prefix-p repository (expand-file-name file))))
    (should-not (string-prefix-p repository
                                 (expand-file-name org-persist-directory)))))

(ert-deftest config-test/org-citar-uses-org-cite-processors ()
  (require 'citar-org)
  (should (equal citar-bibliography org/bibtex-files))
  (should (eq org-cite-insert-processor 'citar))
  (should (eq org-cite-follow-processor 'citar))
  (should (eq org-cite-activate-processor 'citar)))

(ert-deftest config-test/org-paths-live-under-org-directory ()
  (should (file-name-absolute-p org-directory))
  (should (string-prefix-p org-directory org/refile-file))
  (should (string-prefix-p org-directory (car org/agenda-files)))
  (should (string-prefix-p org-directory (car org/bibtex-files))))

(ert-deftest config-test/org-capture-templates-file-into-refile-file ()
  (dolist (key '("t" "r" "n" "w" "m"))
    (should (assoc key org-capture-templates)))
  (should (equal (nth 3 (assoc "t" org-capture-templates))
                 '(file org/refile-file))))

(ert-deftest config-test/org-agenda-commands-are-defined ()
  (should (assoc "d" org-agenda-custom-commands))
  (should (assoc "p" org-agenda-custom-commands)))

(ert-deftest config-test/org-last-modified-updates-preamble-only ()
  (org-test/with-buffer "#+title: Note\n#+last_modified: \n\n* Heading\n"
    (org/set-last-modified)
    (goto-char (point-min))
    (should (re-search-forward
             "^#\\+last_modified: \\[[0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\} [^]\n]+ [0-9]\\{2\\}:[0-9]\\{2\\}\\]$"
             nil t))
    (goto-char (point-min))
    (should (re-search-forward "^\\* Heading$" nil t))))

(ert-deftest config-test/org-last-modified-hook-is-buffer-local ()
  (org-test/with-buffer "#+last_modified: \n"
    (should (memq #'org/set-last-modified before-save-hook)))
  (should-not (memq #'org/set-last-modified (default-value 'before-save-hook))))

(ert-deftest config-test/org-stuck-projects-show-only-projects-without-next ()
  (org-test/with-buffer org-test/projects-sample
    (should-not (org-test/skip-at "Stuck project"
                                  #'org/skip-non-stuck-projects))
    (should (org-test/skip-at "Active project"
                              #'org/skip-non-stuck-projects))
    (should (org-test/skip-at "Waiting for reply"
                              #'org/skip-non-stuck-projects))
    (should (org-test/skip-at "Single task"
                              #'org/skip-non-stuck-projects))))

(ert-deftest config-test/org-next-view-keeps-project-tasks-only ()
  (org-test/with-buffer org-test/projects-sample
    (let ((org/hide-scheduled-and-waiting-next-tasks t))
      (should-not (org-test/skip-at "Write the draft"
                                    #'org/skip-projects-and-habits-and-single-tasks))
      (should (org-test/skip-at "Tagged waiting"
                                #'org/skip-projects-and-habits-and-single-tasks))
      (should (org-test/skip-at "Daily habit"
                                #'org/skip-projects-and-habits-and-single-tasks))
      (should (org-test/skip-at "Single task"
                                #'org/skip-projects-and-habits-and-single-tasks))
      (should (org-test/skip-at "Active project"
                                #'org/skip-projects-and-habits-and-single-tasks)))
    (let ((org/hide-scheduled-and-waiting-next-tasks nil))
      (should-not (org-test/skip-at "Tagged waiting"
                                    #'org/skip-projects-and-habits-and-single-tasks)))))

(ert-deftest config-test/org-habit-subtrees-are-skippable ()
  (org-test/with-buffer org-test/projects-sample
    (should (org-test/skip-at "Habit" #'org/skip-subtree-if-habit))
    (should-not (org-test/skip-at "Active project" #'org/skip-subtree-if-habit))))

(ert-deftest config-test/org-archive-view-keeps-stale-done-tasks ()
  (let ((stamp (format-time-string "[%Y-%m-%d %a]")))
    (org-test/with-buffer
        (format "* DONE Old finished\nCLOSED: [2020-01-02 Thu]\n* DONE Recent finished\nCLOSED: %s\n* TODO Open task\n"
                stamp)
      (should-not (org-test/skip-at "Old finished"
                                    #'org/skip-non-archivable-tasks))
      (should (org-test/skip-at "Recent finished"
                                #'org/skip-non-archivable-tasks))
      (should (org-test/skip-at "Open task"
                                #'org/skip-non-archivable-tasks)))))

(ert-deftest config-test/org-projects-agenda-builds-from-custom-command ()
  (let* ((directory (file-name-as-directory (make-temp-file "org-agenda-test-" t)))
         (file (expand-file-name "tasks.org" directory))
         (org-agenda-files (list file)))
    (unwind-protect
        (progn
          (with-temp-file file
            (insert org-test/projects-sample))
          (org-agenda nil "p")
          (let ((buffer (get-buffer org-agenda-buffer-name)))
            (should buffer)
            (with-current-buffer buffer
              (let ((text (buffer-string)))
                (should (string-match-p "Stuck Projects" text))
                (should (string-match-p "Stuck project" text))
                (should (string-match-p "Project Next Tasks" text))
                (should (string-match-p "Write the draft" text))
                (should-not (string-match-p "Daily habit" text))))
            (kill-buffer buffer)))
      (delete-directory directory t))))

(ert-deftest config-test/org-menus-are-bound-under-help-prefix ()
  (should (eq (key-binding (kbd "C-x C-h A")) 'hydra-org-agenda/body))
  (with-temp-buffer
    (org-mode)
    (should (eq (key-binding (kbd "C-x C-h O")) 'hydra-org-heading/body))
    ;; The mode-local prefix must not hide global menus or built-in C-x keys.
    (should (eq (key-binding (kbd "C-x C-h u")) 'hydra-undo-tree/body))
    (should (eq (key-binding (kbd "C-x C-f")) 'find-file)))
  (with-temp-buffer
    (fundamental-mode)
    (should-not (eq (key-binding (kbd "C-x C-h O")) 'hydra-org-heading/body))))

(ert-deftest config-test/org-agenda-menu-covers-views-and-capture ()
  (require 'org-agenda)
  (dolist (key '("a" "d" "p" "t" "m" "s" "c" "q"))
    (should (lookup-key hydra-org-agenda/keymap (kbd key))))
  (should (org-test/head-runs-p hydra-org-agenda/keymap "d" 'org/agenda-daily))
  (should (org-test/head-runs-p hydra-org-agenda/keymap "p" 'org/agenda-projects))
  (should (org-test/head-runs-p hydra-org-agenda/keymap "c" 'org-capture)))

(ert-deftest config-test/org-heading-menu-covers-structure-editing ()
  (dolist (key '("n" "p" "c" "t" "+" "-" "T" "s" "d" "i" "o" "r" "a" "q"))
    (should (lookup-key hydra-org-heading/keymap (kbd key))))
  (should (org-test/head-runs-p hydra-org-heading/keymap "t" 'org-todo))
  (should (org-test/head-runs-p hydra-org-heading/keymap "+" 'org-priority-up))
  (should (org-test/head-runs-p hydra-org-heading/keymap "r" 'org-refile)))

(provide 'org-tests)

;;; org-tests.el ends here
