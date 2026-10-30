;;; dashboard-config.el --- Dashboard startup screen and menu -*- lexical-binding: t; -*-

(require 'cl-lib)
(require 'packages)

(declare-function dashboard-insert-startupify-lists "dashboard" (&optional force-refresh))
(declare-function dashboard-next-section "dashboard" ())
(declare-function dashboard-previous-section "dashboard" ())
(defvar dashboard-buffer-name)

(defcustom dashboard/show-on-startup t
  "Show Dashboard at startup and in empty emacsclient frames.
Restart Emacs after changing this option.  Explicit file visits and
existing initial buffer choices take precedence."
  :type 'boolean
  :group 'dashboard)

(defun dashboard/buffer ()
  "Return a refreshed Dashboard using the caller's working directory.
This is the initial-buffer callback for empty emacsclient frames."
  (let ((directory default-directory))
    (with-current-buffer (get-buffer-create dashboard-buffer-name)
      (setq default-directory directory)
      (dashboard-insert-startupify-lists t)
      (current-buffer))))

(defun dashboard/open ()
  "Open Dashboard in the selected window."
  (interactive)
  (switch-to-buffer (dashboard/buffer)))

(defun dashboard/startup ()
  "Select Dashboard on an empty startup and in future empty client frames.
Install the client callback after command-line file handling so explicit
startup files are not split alongside Dashboard."
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

(packages/declare 'dashboard)
(use-package dashboard
  :ensure nil
  :demand t
  :after hydra
  :custom
  (dashboard-banner-logo-title "The truth is the whole.")
  (dashboard-projects-backend 'project-el)
  (dashboard-startup-banner 'logo)
  (dashboard-items '((recents . 5)
                     (bookmarks . 5)
                     (projects . 10)))
  :bind (("C-c D" . dashboard/open)
         ("C-x C-h s" . hydra-dashboard/body)
         :map dashboard-mode-map
         ("." . hydra-dashboard/body))
  :hydra (hydra-dashboard
          (:color pink :hint nil :body-pre (dashboard/open))
          "
 Dashboard: _n_ext section  _p_revious section  _g_ refresh
 Open: _f_ file  _r_ recent file  _m_ bookmark  _P_ project  _b_ buffer
 _q_ leave menu"
          ("n" dashboard-next-section)
          ("p" dashboard-previous-section)
          ("g" dashboard/open)
          ("f" find-file :exit t)
          ("r" consult-recent-file :exit t)
          ("m" consult-bookmark :exit t)
          ("P" project-switch-project :exit t)
          ("b" consult-buffer :exit t)
          ("q" nil :exit t))
  :config
  ;; The upstream startup hook checks argv length and does not provide the
  ;; initial-buffer callback used by empty daemon/client frames.
  (add-hook 'emacs-startup-hook #'dashboard/startup))

;;; dashboard-config.el ends here
