;;; workspaces.el --- Tabspaces workspaces and Consult integration -*- lexical-binding: t; -*-

(require 'cl-lib)
(require 'packages)

(declare-function tabspaces-remove-current-buffer "tabspaces" ())
(declare-function tabspaces-close-workspace "tabspaces" ())
(declare-function tabspaces-rename-workspace "tabspaces" (&optional name tab-number))

(defvar consult-buffer-list-function)
(defvar consult-buffer-sources)
(defvar consult-source-buffer)
(defvar workspaces/project-session-directory nil
  "Directory for cached per-project Tabspaces sessions, set by cache helpers.")
(defvar tabspaces-mode)
(defvar tabspaces-session-auto-restore)
(defvar tabspaces-session)

(defvar workspaces/consult-source-buffer nil
  "Workspace-local copy of Consult's ordinary buffer source.")
(defvar workspaces/consult-source-all-buffers nil
  "Global buffer source available through Consult's b narrowing key.")

(defun workspaces/project-session-file (root)
  "Return the cached Tabspaces session filename for project ROOT.
Hash the full path so projects with the same basename do not share state.
Do not resolve symlinks or contact remote hosts to compute the filename."
  (expand-file-name
   (concat (secure-hash 'sha256 (directory-file-name (expand-file-name root)))
           ".el")
   workspaces/project-session-directory))

(defun workspaces/consult-items ()
  "Return ordinary Consult buffer candidates from the current workspace.
Scope the buffer list to this source only, leaving project-wide selection,
recent-file deduplication, and multi-buffer search unchanged."
  (let ((consult-buffer-list-function #'tabspaces-local-buffer-list))
    (funcall (plist-get consult-source-buffer :items))))

(defun workspaces/configure-consult ()
  "Make Consult's default buffer source workspace-local while Tabspaces is on.
Keep all buffers available with b narrowing, without modifying Consult's
original source or depending on its private candidate-building functions."
  (when (featurep 'consult)
    (setq workspaces/consult-source-buffer (copy-sequence consult-source-buffer)
          workspaces/consult-source-all-buffers (copy-sequence consult-source-buffer))
    (setf (plist-get workspaces/consult-source-buffer :name) "Workspace Buffer"
          (plist-get workspaces/consult-source-buffer :narrow) ?w
          (plist-get workspaces/consult-source-buffer :items) #'workspaces/consult-items
          (plist-get workspaces/consult-source-all-buffers :hidden) t
          (plist-get workspaces/consult-source-all-buffers :default) nil)
    (setq consult-buffer-sources
          (cl-loop for source in consult-buffer-sources
                   append
                   (pcase source
                     ('consult-source-buffer
                      (if tabspaces-mode
                          '(workspaces/consult-source-buffer
                            workspaces/consult-source-all-buffers)
                        (list source)))
                     ('workspaces/consult-source-buffer
                      (list (if tabspaces-mode source 'consult-source-buffer)))
                     ('workspaces/consult-source-all-buffers
                      (when tabspaces-mode (list source)))
                     (_ (list source)))))))

(defun workspaces/save-session ()
  "Save a complete startup snapshot after Tabspaces' per-project exit saver.
The upstream saver keeps project tabs in separate files; also save all tabs
so automatic startup restoration includes projects without reopening each."
  (when (and tabspaces-mode tabspaces-session (not noninteractive))
    (tabspaces-save-session)))

(defun workspaces/configure-session-save ()
  "Keep a complete exit snapshot only while interactive Tabspaces is active."
  (remove-hook 'kill-emacs-hook #'workspaces/save-session)
  (when (and tabspaces-mode tabspaces-session (not noninteractive))
    (add-hook 'kill-emacs-hook #'workspaces/save-session 90)))

(defun workspaces/enable ()
  "Enable native tabs and Tabspaces without restoring sessions in batch runs.
Interactive startup uses Tabspaces' own restoration, which defers daemon
restoration until the first client frame is available."
  ;; Tabspaces requires dired-x.  Load it after all feature declarations so
  ;; Dired's after-load integrations cannot run halfway through configuration.
  (require 'tabspaces)
  (tab-bar-mode 1)
  (let ((tabspaces-session-auto-restore
         (and (not noninteractive) tabspaces-session-auto-restore)))
    (tabspaces-mode 1)))

(packages/declare 'tabspaces)
(use-package tabspaces
  :ensure nil
  :defer t
  :after hydra
  :init
  (add-hook 'emacs-startup-hook #'workspaces/enable)
  :custom
  (tabspaces-keymap-prefix nil)
  (tabspaces-use-filtered-buffers-as-default nil)
  (tabspaces-initialize-project-with-todo nil)
  (tabspaces-fully-resolve-paths t)
  ;; Preserve existing project.el discovery and project-switch entry points.
  (tabspaces-project-fallback-to-tab nil)
  (tabspaces-project-switch-opens-workspace nil)
  (tabspaces-session t)
  (tabspaces-session-auto-restore t)
  (tabspaces-session-project-session-store #'workspaces/project-session-file)
  (tab-bar-new-tab-choice "*scratch*")
  ;; Tabs stay active for workspaces; the visible tab bar is hidden.
  (tab-bar-show nil)
  :bind (("C-x C-h W" . hydra-workspaces/body)
         :map tabspaces-mode-map
         ("C-c w" . tabspaces-command-map)
         :map tabspaces-command-map
         ("." . hydra-workspaces/body)
         ("S" . tabspaces-save-session)
         ("L" . tabspaces-restore-session))
  :hydra (hydra-workspaces
          (:exit t :hint nil)
          "
 _s_ switch/create  _o_ project  _b_ buffer
 _n_ next  _p_ previous  _R_ rename  _d_ close
 _r_ remove buffer  _S_ save  _L_ restore  _q_ quit"
          ("s" tabspaces-switch-or-create-workspace)
          ("o" tabspaces-open-or-create-project-and-workspace)
          ("b" consult-buffer)
          ("n" tab-next)
          ("p" tab-previous)
          ("R" tabspaces-rename-workspace)
          ("d" tabspaces-close-workspace)
          ("r" tabspaces-remove-current-buffer)
          ("S" tabspaces-save-session)
          ("L" tabspaces-restore-session)
          ("q" nil))
  :config
  (add-hook 'tabspaces-mode-hook #'workspaces/configure-consult)
  (add-hook 'tabspaces-mode-hook #'workspaces/configure-session-save)
  (with-eval-after-load 'consult
    (workspaces/configure-consult)))

;;; workspaces.el ends here
