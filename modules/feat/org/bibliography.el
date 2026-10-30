;;; bibliography.el --- Citations with citar and org-cite -*- lexical-binding: t; -*-

(require 'packages)

;; citar supplies the completing-read front end and the org-cite processor.  It
;; opens PDFs with the platform's default application itself.
(packages/declare 'citar)
(use-package citar
  :ensure nil
  :defer t
  :custom
  (citar-bibliography org/bibtex-files)
  (citar-library-paths (list org/bibtex-library))
  :hook (org-mode . citar-capf-setup)
  :bind ("C-c B" . citar-open))

(use-package org
  :ensure nil
  :defer t
  :bind (:map org-mode-map
              ("C-c b" . org-cite-insert)))

;; `citar-org' registers the `citar' processor with org-cite.  Loading it after
;; both citar and Org keeps citation activation and following in citar.
(use-package citar-org
  :ensure nil
  :after (citar org)
  :custom
  (org-cite-insert-processor 'citar)
  (org-cite-follow-processor 'citar)
  (org-cite-activate-processor 'citar))

;;; bibliography.el ends here
