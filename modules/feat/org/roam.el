;;; roam.el --- Org-roam note graph -*- lexical-binding: t; -*-

(require 'packages)

;; Notes live under `org-directory'.  The database path is kept in the cache
;; root by `cache/configure-state-paths', not in this repository.
(packages/declare 'org-roam)
(use-package org-roam
  :ensure nil
  :defer t
  :custom
  (org-roam-directory (expand-file-name "roam/" org-directory))
  (org-roam-capture-templates
   '(("d" "default" plain "%?"
      :if-new
      (file+head "${slug}-%<%Y%m%d%H%M%S>.org"
                 "#+title: ${title}\n#+date: %u\n#+last_modified: \n\n")
      :immediate-finish t)))
  :bind ("C-c n f" . org-roam-node-find)
  :config
  ;; The database indexes the notes directory.  When that directory does not
  ;; exist yet, syncing would signal an error during startup, so skip it.
  ;; `org-roam-db-autosync-mode' replaces the obsolete `org-roam-setup' alias.
  (when (file-directory-p org-roam-directory)
    (org-roam-db-autosync-mode 1)))

;; Note keys that only apply inside Org buffers.  The commands are autoloaded,
;; so these bindings do not load org-roam.
(use-package org
  :ensure nil
  :defer t
  :bind (:map org-mode-map
              ("C-c n i" . org-roam-node-insert)
              ("C-c n o" . org-id-get-create)
              ("C-c n t" . org-roam-tag-add)
              ("C-c n a" . org-roam-alias-add)
              ("C-c n l" . org-roam-buffer-toggle)))

;;; roam.el ends here
