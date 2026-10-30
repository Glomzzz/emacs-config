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
  :after hydra
  :hook (org-mode . citar-capf-setup)
  :bind (("C-c B" . citar-open)
         ("C-x C-h B" . hydra-citar/body))
  ;; C-x C-h B groups the library and resource commands.  Inserting a citation
  ;; stays on C-c b in Org buffers, where org-cite handles it.
  :hydra (hydra-citar
          (:color blue :hint nil)
          "
 _o_: open resources  _f_: library file  _e_: BibTeX entry  _l_: URL or DOI  _a_: add file  _q_: quit"
          ("o" citar-open)
          ("f" citar-open-files)
          ("e" citar-open-entry)
          ("l" citar-open-links)
          ("a" citar-add-file-to-library)
          ("q" nil "quit")))

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
