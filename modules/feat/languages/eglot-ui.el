;;; eglot-ui.el --- Eglot navigation previews and key menu -*- lexical-binding: t; -*-

(require 'packages)
(require 'xref)

(declare-function consult--customize-put "consult" (cmds prop form))

(defun eglot-ui--show-xrefs (fetcher alist)
  "Show FETCHER's locations below the source, using Xref's native UI.
Preview the first of multiple results in another window.  A single
result opens directly in another window.  Preserve Xref's ALIST context."
  (xref-show-definitions-buffer-at-bottom
   fetcher (append '((auto-jump . show) (display-action . window)) alist)))

(defun eglot-ui/peek-definition ()
  "Preview definitions without replacing the source window.
Use the active Xref backend, including Eglot when it manages the buffer."
  (interactive)
  (let ((xref-show-definitions-function #'eglot-ui--show-xrefs)
        (this-command 'xref-find-definitions-other-window))
    (call-interactively #'xref-find-definitions-other-window)))

(defun eglot-ui/peek-references ()
  "Preview references without replacing the source window."
  (interactive)
  (let ((xref-show-xrefs-function #'eglot-ui--show-xrefs)
        (this-command 'xref-find-references))
    (call-interactively #'xref-find-references)))

(packages/declare 'consult-eglot)
(use-package consult-eglot
  :ensure nil
  :commands consult-eglot-symbols
  :config
  ;; Opening files while moving through results stays explicit, as with the
  ;; other Consult file sources in workspace/navigation.el.
  (consult-customize consult-eglot-symbols :preview-key "M-."))

(use-package eldoc
  :ensure nil
  :config
  ;; Explicit Eldoc requests use the same top pane in GUI and TTY frames.
  ;; The normal automatic Eldoc/Eldoc Box display remains feature-owned.
  (add-to-list 'display-buffer-alist
               '("\\` ?\\*eldoc\\(?: for .*\\)?\\*\\'"
                 (display-buffer-in-side-window)
                 (side . top)
                 (slot . 0)
                 (window-height . 0.25))))

(use-package flymake
  :ensure nil
  :commands (flymake-show-buffer-diagnostics flymake-show-project-diagnostics))

(use-package eglot
  :ensure nil
  :commands (eglot-find-typeDefinition eglot-find-implementation
             eglot-code-actions eglot-rename eglot-reconnect)
  :after hydra
  :bind ("C-x C-h l" . hydra-eglot/body)
  :hydra (hydra-eglot
          (:exit t :hint nil)
          "
 Eglot: _d_ definitions  _r_ references  _b_ back  _f_ forward
 Symbols: _s_ workspace  _i_ document  _t_ type  _I_ implementation
 Tools: _h_ documentation  _H_ doc buffer  _a_ actions  _R_ rename
 Diagnostics: _e_ buffer  _E_ project    Server: _c_ reconnect  _q_ quit"
          ("d" eglot-ui/peek-definition)
          ("r" eglot-ui/peek-references)
          ("b" xref-go-back)
          ("f" xref-go-forward)
          ("s" consult-eglot-symbols)
          ("i" consult-imenu)
          ("t" eglot-find-typeDefinition)
          ("I" eglot-find-implementation)
          ("h" eldoc-print-current-symbol-info)
          ("H" eldoc-doc-buffer)
          ("a" eglot-code-actions)
          ("R" eglot-rename)
          ("e" flymake-show-buffer-diagnostics)
          ("E" flymake-show-project-diagnostics)
          ("c" eglot-reconnect)
          ("q" nil)))

;;; eglot-ui.el ends here
