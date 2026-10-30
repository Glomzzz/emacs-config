;;; org.el --- Core Org settings -*- lexical-binding: t; -*-

(require 'packages)

;; Org ships with Emacs, so it needs no package declaration.  Its settings are
;; split across this file and the sibling files listed in mod.el.

(declare-function org-at-timestamp-p "org" (&optional extended))
(declare-function org-toggle-pretty-entities "org" ())
(defvar org-outline-regexp-bol)
(defvar org-pretty-entities)

(defgroup org-config nil
  "Personal Org notes, agenda, capture, and bibliography settings."
  :group 'org)

;; Org reads `org-directory' when it loads.  Set it first so the defaults below
;; expand from the resolved directory rather than from a symbolic link.
(defvar org-directory)
(setq org-directory (file-truename "~/org/"))

(defcustom org/agenda-files (list (expand-file-name "Agenda/" org-directory))
  "Files and directories read by the Org agenda."
  :type '(repeat (choice file directory))
  :group 'org-config)

(defcustom org/refile-file (expand-file-name "refile.org" org-directory)
  "Inbox file used by capture templates and as the default refile target."
  :type 'file
  :group 'org-config)

(defcustom org/bibtex-files
  (list (expand-file-name "References/references.bib" org-directory))
  "BibTeX files that supply citation keys to Org."
  :type '(repeat file)
  :group 'org-config)

(defcustom org/bibtex-library (expand-file-name "References/" org-directory)
  "Directory of PDFs and other files attached to bibliography entries."
  :type 'directory
  :group 'org-config)

(defun org--find-time-file-property (property &optional anywhere)
  "Return the position after the file keyword PROPERTY, or nil if it is absent.
PROPERTY is a keyword name such as \"last_modified\".  Unless ANYWHERE is
non-nil, only the preamble above the first heading is searched."
  (save-excursion
    (goto-char (point-min))
    (let ((first-heading
           (save-excursion
             (re-search-forward org-outline-regexp-bol nil t))))
      (when (re-search-forward (format "^#\\+%s:" property)
                               (if anywhere nil first-heading)
                               t)
        (point)))))

(defun org--has-time-file-property-p (property &optional anywhere)
  "Return the position of PROPERTY when it holds a timestamp.
Return -1 when the keyword exists without a timestamp, and nil when it is
absent.  ANYWHERE has the same meaning as in `org--find-time-file-property'."
  (when-let* ((pos (org--find-time-file-property property anywhere)))
    (save-excursion
      (goto-char pos)
      (if (and (looking-at-p " ")
               (progn (forward-char)
                      (org-at-timestamp-p 'lax)))
          pos
        -1))))

(defun org--set-time-file-property (property &optional anywhere pos)
  "Replace the value of the file keyword PROPERTY with the current time.
ANYWHERE has the same meaning as in `org--find-time-file-property'.  POS is
the keyword position when the caller has already computed it."
  (when-let* ((pos (or pos (org--find-time-file-property property anywhere))))
    (save-excursion
      (goto-char pos)
      (if (looking-at-p " ")
          (forward-char)
        (insert " "))
      (delete-region (point) (line-end-position))
      (insert (format-time-string "[%Y-%m-%d %a %H:%M]")))))

(defun org/set-last-modified ()
  "Update the LAST_MODIFIED keyword in the preamble of the current Org buffer."
  (when (derived-mode-p 'org-mode)
    (org--set-time-file-property "last_modified")))

(defun org/setup-buffer ()
  "Prepare the current Org buffer for editing."
  (setq-local truncate-lines nil)
  ;; Display TeX-style entities such as \alpha as Unicode characters.
  (unless org-pretty-entities
    (org-toggle-pretty-entities))
  ;; Buffer-local, so only Org buffers refresh their LAST_MODIFIED keyword.
  (add-hook 'before-save-hook #'org/set-last-modified nil t))

(packages/declare 'counsel)
(use-package counsel
  :ensure nil
  :commands (counsel-org-tag))

(use-package org
  :ensure nil
  :defer t
  :hook (org-mode . org/setup-buffer)
  :custom
  ;; Hide leading stars and show inline images at a fixed width.
  (org-hide-leading-stars t)
  (org-startup-with-inline-images t)
  (org-image-actual-width 600)
  (org-adapt-indentation t)
  (org-outline-path-complete-in-steps nil)
  (org-cite-global-bibliography org/bibtex-files)
  (org-todo-keywords
   '((sequence "TODO(t)" "NEXT(n)" "|" "DONE(d)")
     (sequence "WAITING(w@/!)" "|" "CANCELLED(c@/!)" "MEETING")))
  (org-todo-keyword-faces
   '(("TODO" :foreground "goldenrod1" :weight bold)
     ("NEXT" :foreground "DodgerBlue1" :weight bold)
     ("DONE" :foreground "SpringGreen2" :weight bold)
     ("WAITING" :foreground "LightSalmon1" :weight bold)
     ("CANCELLED" :foreground "LavenderBlush4" :weight bold)
     ("MEETING" :foreground "IndianRed1" :weight bold)))
  (org-todo-state-tags-triggers
   '(("CANCELLED" ("CANCELLED" . t))
     ("WAITING" ("WAITING" . t))
     (done ("WAITING"))
     ("TODO" ("WAITING") ("CANCELLED"))
     ("NEXT" ("WAITING") ("CANCELLED"))
     ("DONE" ("WAITING") ("CANCELLED"))))
  :bind (:map org-mode-map
              ("C-c C-q" . counsel-org-tag)))

;;; org.el ends here
