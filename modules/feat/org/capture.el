;;; capture.el --- Org capture and refile -*- lexical-binding: t; -*-

(use-package org
  :ensure nil
  :defer t
  :bind ("C-c c" . org-capture)
  :custom
  (org-capture-templates
   '(("t" "todo" entry (file org/refile-file)
      "* TODO %?\n%U\n%a\n" :clock-in t :clock-resume t)
     ("r" "respond" entry (file org/refile-file)
      "* NEXT Respond to %:from on %:subject\nSCHEDULED: %t\n%U\n%a\n"
      :clock-in t :clock-resume t :immediate-finish t)
     ("n" "note" entry (file org/refile-file)
      "* %? :NOTE:\n%U\n%a\n" :clock-in t :clock-resume t)
     ("w" "org-protocol" entry (file org/refile-file)
      "* TODO Review %c\n%U\n" :immediate-finish t)
     ("m" "Meeting" entry (file org/refile-file)
      "* MEETING with %? :MEETING:\n%U" :clock-in t :clock-resume t)))
  (org-refile-targets '((nil :maxlevel . 9)
                        (org-agenda-files :maxlevel . 9)))
  ;; Refile into full outline paths within a file.
  (org-refile-use-outline-path 'file)
  ;; Creating a missing parent heading during refile needs confirmation.
  (org-refile-allow-creating-parent-nodes 'confirm))

;;; capture.el ends here
