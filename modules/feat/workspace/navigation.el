;;; navigation.el --- Consult navigation and search commands -*- lexical-binding: t; -*-

(require 'packages)
(declare-function consult--customize-put "consult" (cmds prop form))

(packages/declare 'consult)
(use-package consult
  :ensure nil
  :custom
  ;; A short debounce keeps previews responsive without opening every transient
  ;; candidate while typing quickly.
  (consult-preview-key '(:debounce 0.2 any))
  ;; Press `<', then a source key, to narrow multi-source commands.
  (consult-narrow-key "<")
  (register-preview-delay 0.5)
  (xref-show-definitions-function #'consult-xref)
  (xref-show-xrefs-function #'consult-xref)
  ;; Keep the stock commands available through familiar keys while replacing
  ;; their UI with Consult's richer candidates and live previews.
  :bind (;; C-c bindings in `mode-specific-map'
         ("C-c s" . consult-ripgrep)
         ("C-c R" . consult-recent-file)
         ("C-c M-x" . consult-mode-command)
         ("C-c h" . consult-history)
         ("C-c k" . consult-kmacro)
         ("C-c m" . consult-man)
         ("C-c i" . consult-info)
         ([remap Info-search] . consult-info)
         ;; C-x bindings in `ctl-x-map'
         ("C-x M-:" . consult-complex-command)     ;; orig. repeat-complex-command
         ("C-x b" . consult-buffer)                ;; orig. switch-to-buffer
         ("C-x 4 b" . consult-buffer-other-window) ;; orig. switch-to-buffer-other-window
         ("C-x 5 b" . consult-buffer-other-frame)  ;; orig. switch-to-buffer-other-frame
         ("C-x t b" . consult-buffer-other-tab)    ;; orig. switch-to-buffer-other-tab
         ("C-x r b" . consult-bookmark)            ;; orig. bookmark-jump
         ("C-x p b" . consult-project-buffer)      ;; orig. project-switch-to-buffer
         ;; Custom M-# bindings for fast register access
         ("M-#" . consult-register-load)
         ("M-'" . consult-register-store)          ;; orig. abbrev-prefix-mark
         ("C-M-#" . consult-register)
         ;; Other custom bindings
         ("M-y" . consult-yank-pop)                ;; orig. yank-pop
         ;; M-g bindings in `goto-map'
         ("M-g e" . consult-compile-error)
         ("M-g r" . consult-grep-match)
         ("M-g f" . consult-flymake)               ;; Alternative: consult-flycheck
         ("M-g g" . consult-goto-line)             ;; orig. goto-line
         ("M-g M-g" . consult-goto-line)           ;; orig. goto-line
         ("M-g o" . consult-outline)               ;; Alternative: consult-org-heading
         ("M-g m" . consult-mark)
         ("M-g k" . consult-global-mark)
         ("M-g i" . consult-imenu)
         ("M-g I" . consult-imenu-multi)
         ;; M-s bindings in `search-map'
         ("M-s d" . consult-find)                  ;; Alternative: consult-fd
         ("M-s c" . consult-locate)
         ("M-s g" . consult-grep)
         ("M-s G" . consult-git-grep)
         ("M-s r" . consult-ripgrep)
         ("M-s l" . consult-line)
         ("M-s L" . consult-line-multi)
         ("M-s k" . consult-keep-lines)
         ("M-s u" . consult-focus-lines)
         ;; Isearch integration
         ("M-s e" . consult-isearch-history)
         :map isearch-mode-map
         ("M-e" . consult-isearch-history)         ;; orig. isearch-edit-string
         ("M-s e" . consult-isearch-history)       ;; orig. isearch-edit-string
         ("M-s l" . consult-line)                  ;; needed by consult-line
         ("M-s L" . consult-line-multi)            ;; needed by consult-line
         ;; Minibuffer history
         :map minibuffer-local-map
         ("M-s" . consult-history)                 ;; orig. next-matching-history-element
         ("M-r" . consult-history))                ;; orig. previous-matching-history-element
  :config
  ;; Use Consult's compact register preview for built-in register commands too.
  (unless (advice-member-p #'consult-register-window #'register-preview)
    (advice-add #'register-preview :override #'consult-register-window))

  ;; Theme/manual rendering stays automatic but waits for selection to settle.
  ;; File-backed previews are explicit: moving through results must not visit
  ;; each file, including virtual file candidates in `consult-buffer'.
  (consult-customize
   consult-theme consult-man
   :preview-key '(:debounce 0.4 any)
   consult-ripgrep consult-git-grep consult-grep
   consult-bookmark consult-recent-file consult-xref
   consult-source-bookmark consult-source-file-register
   consult-source-recent-file consult-source-project-recent-file
   ;; This source is a separate plist copied from the visible project source.
   consult-source-project-recent-file-hidden
   :preview-key "M-.")

  ;; `< ?' displays available narrowing keys through Embark.
  (keymap-set consult-narrow-map
              (concat (or consult-narrow-key "<") " ?")
              #'embark-prefix-help-command))

(packages/declare 'consult-dir)
(use-package consult-dir
  :ensure nil
  ;; The current release has an Emacs 31 native-compiler warning while its
  ;; source plist variables are defined later in the file.  Keep the package
  ;; autoloaded until a directory command is actually used.
  :bind (:map minibuffer-local-completion-map
              ("C-x C-d" . consult-dir)
              ("C-x C-j" . consult-dir-jump-file)
              :map minibuffer-local-filename-completion-map
              ("C-x C-d" . consult-dir)
              ("C-x C-j" . consult-dir-jump-file)))

;; Jump to visible text without opening a completion prompt.  Keep Avy's
;; optional default-key setup off so Embark, Consult, and Isearch retain keys.
(packages/declare 'avy)
(use-package avy
  :ensure nil
  :after hydra
  :bind (("C-'" . avy-goto-char-timer)
         ("C-x C-h a" . hydra-avy/body))
  :custom
  (avy-all-windows t)
  (avy-timeout-seconds 0.5)
  ;; Menu adapted from the hydra wiki's avy example.  Every head runs its
  ;; command and then leaves the menu.
  :hydra (hydra-avy (:exit t :hint nil)
                    "
 Line^^       Region^^        Goto
----------------------------------------------------------
 [_y_] yank   [_Y_] yank      [_c_] timed char  [_C_] char
 [_m_] move   [_M_] move      [_w_] word        [_W_] any word
 [_k_] kill   [_K_] kill      [_l_] line        [_L_] end of line"
                    ("c" avy-goto-char-timer)
                    ("C" avy-goto-char)
                    ("w" avy-goto-word-1)
                    ("W" avy-goto-word-0)
                    ("l" avy-goto-line)
                    ("L" avy-goto-end-of-line)
                    ("m" avy-move-line)
                    ("M" avy-move-region)
                    ("k" avy-kill-whole-line)
                    ("K" avy-kill-region)
                    ("y" avy-copy-line)
                    ("Y" avy-copy-region)))

;; Window menu adapted from the hydra wiki's "Window moving" example.  Its
;; ace-window and helm heads are left out because this config does not install
;; those packages.  `winner-mode' supplies the undo and redo heads.
(use-package window
  :ensure nil
  :after hydra
  :bind ("C-x C-h w" . hydra-window/body)
  :hydra (hydra-window
          (:color red :hint nil)
          "
 Move: _h_ left  _j_ down  _k_ up  _l_ right    Swap: _s_
 Split: _v_ertical  _x_ horizontal    Resize: _H_ narrower  _L_ wider  _J_ shorter  _K_ taller
 Delete: _o_nly  _dw_ window  _db_ buffer  _df_ frame    Frame: _f_ new
 History: _u_ undo  _r_ redo    _q_ quit"
          ("h" windmove-left)
          ("j" windmove-down)
          ("k" windmove-up)
          ("l" windmove-right)
          ("H" shrink-window-horizontally)
          ("L" enlarge-window-horizontally)
          ("J" shrink-window)
          ("K" enlarge-window)
          ("|" (lambda ()
                (interactive)
                (split-window-right)
                (windmove-right)))
          ("_" (lambda ()
                (interactive)
                (split-window-below)
                (windmove-down)))
          ("v" split-window-right)
          ("x" split-window-below)
          ("u" winner-undo)
          ("r" winner-redo)
          ("o" delete-other-windows :exit t)
          ("s" window-swap-states)
          ("dw" delete-window)
          ("db" kill-this-buffer)
          ("df" delete-frame :exit t)
          ("f" make-frame-command :exit t)
          ("q" nil)))

;; Ibuffer menus adapted from the hydra wiki's Ibuffer example.  The main menu
;; opens the mark, action, sort, and filter menus, and `.' opens it from Ibuffer
;; itself.  `C-x C-b' still opens Ibuffer as before.
(use-package ibuffer
  :ensure nil
  :after hydra
  :bind (("C-x C-h b" . hydra-ibuffer-main/body)
         :map ibuffer-mode-map
         ("." . hydra-ibuffer-main/body))
  :hydra
  ((hydra-ibuffer-main
    (:color pink :hint nil)
    "
 ^Mark^         ^Actions^          ^View^          ^Navigation^
 _m_: mark      _D_: delete        _g_: refresh    _k_: up     _j_: down
 _u_: unmark    _S_: save marked   _s_: sort       _h_: prev group  _l_: next group
 _*_: specific  _a_: all actions   _/_: filter     _RET_: visit  _o_: other window
 _t_: toggle    _._: toggle menu   _H_: help       _TAB_: toggle group   _q_: quit"
    ("m" ibuffer-mark-forward)
    ("u" ibuffer-unmark-forward)
    ("*" hydra-ibuffer-mark/body :color blue)
    ("t" ibuffer-toggle-marks)
    ("D" ibuffer-do-delete)
    ("S" ibuffer-do-save)
    ("a" hydra-ibuffer-action/body :color blue)
    ("g" ibuffer-update)
    ("s" hydra-ibuffer-sort/body :color blue)
    ("/" hydra-ibuffer-filter/body :color blue)
    ("H" describe-mode :color blue)
    ("h" ibuffer-backward-filter-group)
    ("k" ibuffer-backward-line)
    ("l" ibuffer-forward-filter-group)
    ("j" ibuffer-forward-line)
    ("RET" ibuffer-visit-buffer :color blue)
    ("TAB" ibuffer-toggle-filter-group)
    ("o" ibuffer-visit-buffer-other-window :color blue)
    ("q" quit-window :color blue)
    ("." nil :color blue))
   (hydra-ibuffer-mark
    (:color teal :columns 5 :after-exit (hydra-ibuffer-main/body))
    "Mark"
    ("*" ibuffer-unmark-all "unmark all")
    ("M" ibuffer-mark-by-mode "mode")
    ("m" ibuffer-mark-modified-buffers "modified")
    ("u" ibuffer-mark-unsaved-buffers "unsaved")
    ("s" ibuffer-mark-special-buffers "special")
    ("r" ibuffer-mark-read-only-buffers "read-only")
    ("/" ibuffer-mark-dired-buffers "dired")
    ("e" ibuffer-mark-dissociated-buffers "dissociated")
    ("h" ibuffer-mark-help-buffers "help")
    ("z" ibuffer-mark-compressed-file-buffers "compressed")
    ("b" hydra-ibuffer-main/body "back" :color blue))
   (hydra-ibuffer-action
    (:color teal :columns 4
     :after-exit (if (eq major-mode 'ibuffer-mode)
                     (hydra-ibuffer-main/body)))
    "Action"
    ("A" ibuffer-do-view "view")
    ("E" ibuffer-do-eval "eval")
    ("I" ibuffer-do-query-replace-regexp "query-replace-regexp")
    ("H" ibuffer-do-view-other-frame "view-other-frame")
    ("M" ibuffer-do-toggle-modified "toggle-modified")
    ("O" ibuffer-do-occur "occur")
    ("P" ibuffer-do-print "print")
    ("Q" ibuffer-do-query-replace "query-replace")
    ("R" ibuffer-do-rename-uniquely "rename-uniquely")
    ("T" ibuffer-do-toggle-read-only "toggle-read-only")
    ("U" ibuffer-do-replace-regexp "replace-regexp")
    ("V" ibuffer-do-revert "revert")
    ("W" ibuffer-do-view-and-eval "view-and-eval")
    ("b" nil "back"))
   (hydra-ibuffer-sort
    (:color amaranth :columns 3)
    "Sort"
    ("i" ibuffer-invert-sorting "invert")
    ("a" ibuffer-do-sort-by-alphabetic "alphabetic")
    ("v" ibuffer-do-sort-by-recency "recently used")
    ("s" ibuffer-do-sort-by-size "size")
    ("f" ibuffer-do-sort-by-filename/process "filename")
    ("m" ibuffer-do-sort-by-major-mode "mode")
    ("b" hydra-ibuffer-main/body "back" :color blue))
   (hydra-ibuffer-filter
    (:color amaranth :columns 4)
    "Filter"
    ("m" ibuffer-filter-by-used-mode "mode")
    ("M" ibuffer-filter-by-derived-mode "derived mode")
    ("n" ibuffer-filter-by-name "name")
    ("c" ibuffer-filter-by-content "content")
    ("e" ibuffer-filter-by-predicate "predicate")
    ("f" ibuffer-filter-by-filename "filename")
    (">" ibuffer-filter-by-size-gt "size")
    ("<" ibuffer-filter-by-size-lt "size")
    ("/" ibuffer-filter-disable "disable")
    ("b" hydra-ibuffer-main/body "back" :color blue))))

;; Recent-buffer switcher adapted from the hydra wiki's "Switch to buffer"
;; example.  The wiki's C-o is `funcs/open-line-below' in this config, so the
;; menu uses C-x C-h o.
(defvar buffers/recent-names nil
  "Names offered by `hydra-buffers', most recently used first.")

(defun buffers/recent-names (count)
  "Return up to COUNT visible buffer names, skipping the current buffer."
  (let ((names (delq nil
                     (mapcar (lambda (buffer)
                               (let ((name (buffer-name buffer)))
                                 (unless (string-prefix-p " " name) name)))
                             (buffer-list)))))
    (seq-take (cdr names) count)))

(defun buffers/number-names (names)
  "Return NAMES as a numbered, comma-separated string."
  (let ((index 0))
    (mapconcat (lambda (name)
                 (setq index (1+ index))
                 (format "%d. %s" index name))
               names
               ", ")))

(defun buffers/switch-to-recent (arg)
  "Switch to the ARGth buffer in `buffers/recent-names'."
  (interactive "p")
  (switch-to-buffer (nth (1- arg) buffers/recent-names)))

(defun buffers/switch-to-recent-other-window (arg)
  "Switch to the ARGth buffer in `buffers/recent-names' in another window."
  (interactive "p")
  (switch-to-buffer-other-window (nth (1- arg) buffers/recent-names)))

(require 'hydra)
(defhydra hydra-buffers (:exit t
                         :body-pre
                         (setq buffers/recent-names (buffers/recent-names 4)))
  "
Other buffers: %s(buffers/number-names buffers/recent-names)
"
  ("o" buffers/switch-to-recent "this window")
  ("O" buffers/switch-to-recent-other-window "other window")
  ("1" (buffers/switch-to-recent 1))
  ("2" (buffers/switch-to-recent 2))
  ("3" (buffers/switch-to-recent 3))
  ("4" (buffers/switch-to-recent 4))
  ("<escape>" nil))
(keymap-global-set "C-x C-h o" #'hydra-buffers/body)

;;; navigation.el ends here
