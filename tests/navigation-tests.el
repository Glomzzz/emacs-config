;;; navigation-tests.el --- Navigation and preview regressions -*- lexical-binding: t; -*-

(require 'ert)
(require 'cl-lib)
(require 'consult)

(defconst config-test/avy-loaded-on-startup (featurep 'avy)
  "Whether configuration startup eagerly loaded Avy.")

(ert-deftest config-test/consult-file-commands-preview-only-on-request ()
  (dolist (command '(consult-ripgrep consult-git-grep consult-grep
                     consult-bookmark consult-recent-file consult-xref))
    (let ((this-command command))
      (should (equal (plist-get (consult--customize-args
                                nil :preview-key consult-preview-key)
                               :preview-key)
                     "M-.")))))

(ert-deftest config-test/consult-local-navigation-keeps-automatic-preview ()
  (dolist (command '(consult-buffer consult-project-buffer
                     consult-line consult-line-multi consult-imenu))
    (let ((this-command command))
      (should (equal (plist-get (consult--customize-args
                                nil :preview-key consult-preview-key)
                               :preview-key)
                     '(:debounce 0.2 any)))))
  (dolist (command '(consult-theme consult-man))
    (let ((this-command command))
      (should (equal (plist-get (consult--customize-args
                                nil :preview-key consult-preview-key)
                               :preview-key)
                     '(:debounce 0.4 any)))))
  ;; Consult disables previews for these destinations; do not override it.
  (dolist (command '(consult-buffer-other-frame consult-buffer-other-tab))
    (let ((this-command command))
      (should-not (plist-get (consult--customize-args
                             nil :preview-key consult-preview-key)
                            :preview-key)))))

(ert-deftest config-test/consult-virtual-files-use-manual-preview-gate ()
  (dolist (symbol '(consult-source-bookmark consult-source-file-register
                    consult-source-recent-file consult-source-project-recent-file
                    consult-source-project-recent-file-hidden))
    (let* ((source (symbol-value symbol))
           (preview-key (consult--multi-preview-key
                         (vector consult-source-buffer source)))
           (file-candidate (cons "/tmp/preview-test.txt" source))
           (buffer-candidate (cons "*scratch*" consult-source-buffer)))
      (should (equal (plist-get source :preview-key) "M-."))
      (dolist (key '("C-n" "<down>" "x"))
        (cl-letf (((symbol-function 'this-single-command-keys)
                   (lambda () (kbd key))))
          ;; Exercise Consult's actual per-source trigger calculation.
          (should-not (consult--preview-key-debounce preview-key file-candidate))
          (should (= (consult--preview-key-debounce preview-key buffer-candidate)
                     0.2))))
      (cl-letf (((symbol-function 'this-single-command-keys)
                 (lambda () (kbd "M-."))))
        (should (= (consult--preview-key-debounce preview-key file-candidate) 0))))))

(ert-deftest config-test/consult-manual-preview-preserves-safety-exclusions ()
  (dolist (file '("/ssh:example:/tmp/file.txt" "/tmp/encrypted.gpg"))
    (should (cl-some (lambda (regexp) (string-match-p regexp file))
                     consult-preview-excluded-files)))
  (should-not (alist-get 'enable-dir-local-variables consult-preview-variables)))

(ert-deftest config-test/avy-startup-is-lazy-and-bindings-do-not-conflict ()
  (should-not config-test/avy-loaded-on-startup)
  (should (memq 'avy packages/declared))
  (should (eq (key-binding (kbd "C-'")) #'avy-goto-char-timer))
  (should (eq (key-binding (kbd "C-;")) #'embark-dwim))
  (should (eq (key-binding (kbd "M-'")) #'consult-register-store))
  (should (eq (key-binding (kbd "M-g f")) #'consult-flymake))
  (should-not (eq (lookup-key isearch-mode-map (kbd "C-'")) #'avy-isearch)))

(defmacro config-test/with-avy-buffer (text &rest body)
  "Run BODY in a displayed isolated buffer containing TEXT."
  (declare (indent 1) (debug (form body)))
  `(let ((buffer (generate-new-buffer " *avy test*"))
         (avy-ring (make-ring 20)))
     (unwind-protect
         (save-window-excursion
           (delete-other-windows)
           (switch-to-buffer buffer)
           (insert ,text)
           (goto-char (point-min))
           (set-window-start nil (point-min))
           ,@body)
       (kill-buffer buffer))))

(ert-deftest config-test/avy-timer-jumps-and-return-restores-source ()
  (require 'avy)
  (should (eq avy-all-windows t))
  (should (= avy-timeout-seconds 0.5))
  (config-test/with-avy-buffer "start\nneedle\nend\n"
    (let ((characters (string-to-list "needle")) delays)
      (cl-letf (((symbol-function 'read-char)
                 (lambda (_prompt &optional _inherit seconds)
                   (push seconds delays)
                   (pop characters)))
                ((symbol-function 'read-key)
                 (lambda (&rest _) (ert-fail "Single match asked for a label"))))
        (call-interactively (key-binding (kbd "C-'"))))
      (should (= (point) 7))
      (should (equal (reverse delays) '(nil 0.5 0.5 0.5 0.5 0.5 0.5)))
      (avy-pop-mark)
      (should (= (point) 1))
      (should (equal (buffer-string) "start\nneedle\nend\n"))
      (should-not (overlays-in (point-min) (point-max))))))

(ert-deftest config-test/avy-label-selects-match-in-another-window ()
  (require 'avy)
  (config-test/with-avy-buffer "one needle\n"
    (let ((source-window (selected-window))
          (other (generate-new-buffer " *avy other window*"))
          (characters (append (string-to-list "needle") '(13)))
          (avy-keys '(?a ?s)))
      (unwind-protect
          (progn
            (let ((window (split-window-below)))
              (set-window-buffer window other)
              (with-current-buffer other (insert "two needle\n"))
              (set-window-start window 1))
            (cl-letf (((symbol-function 'read-char)
                       (lambda (&rest _) (pop characters)))
                      ((symbol-function 'read-key) (lambda (&rest _) ?s)))
              (call-interactively #'avy-goto-char-timer))
            (should (eq (current-buffer) other))
            (should (= (point) 5))
            (should (= (length avy-last-candidates) 2))
            (should-not (overlays-in (point-min) (point-max)))
            (avy-pop-mark)
            (should (eq (selected-window) source-window))
            (should (= (point) 1)))
        (kill-buffer other)))))

(ert-deftest config-test/avy-cancel-cleans-query-and-label-overlays ()
  (require 'avy)
  (config-test/with-avy-buffer "needle needle\n"
    (let ((characters '(?n quit)))
      (cl-letf (((symbol-function 'read-char)
                 (lambda (&rest _)
                   (let ((character (pop characters)))
                     (if (eq character 'quit) (signal 'quit nil) character)))))
        ;; Supply one character, then cancel during query entry.
        (should (eq (condition-case nil (avy-goto-char-timer) (quit 'cancelled))
                    'cancelled)))
      (should (= (point) 1))
      (should-not (overlays-in (point-min) (point-max))))
    (let ((characters (append (string-to-list "needle") '(13))))
      (cl-letf (((symbol-function 'read-char) (lambda (&rest _) (pop characters)))
                ((symbol-function 'read-key) (lambda (&rest _) ?\C-g)))
        (avy-goto-char-timer))
      (should (= (point) 1))
      (should (ring-empty-p avy-ring))
      (should (equal (buffer-string) "needle needle\n"))
      (should-not (overlays-in (point-min) (point-max))))))

(ert-deftest config-test/isearch-count-and-highlight-policy ()
  (should isearch-lazy-highlight)
  (should isearch-lazy-count)
  (should (equal lazy-count-prefix-format "%s/%s "))
  (should lazy-highlight-cleanup))

(ert-deftest config-test/isearch-backspace-remap-preserves-consult-bindings ()
  (let ((overriding-terminal-local-map isearch-mode-map))
    (should (eq (key-binding (kbd "DEL")) #'isearch-del-char))
    (should (eq (key-binding (kbd "M-e")) #'consult-isearch-history))
    (should (eq (key-binding (kbd "M-s l")) #'consult-line))
    (should (eq (key-binding (kbd "M-s L")) #'consult-line-multi))))

(ert-deftest config-test/isearch-backspace-edits-query-after-repeating-search ()
  (let ((buffer (generate-new-buffer " *isearch test*"))
        (isearch-mode-map (copy-keymap isearch-mode-map))
        (search-ring nil)
        query)
    (unwind-protect
        (save-window-excursion
          (switch-to-buffer buffer)
          (insert "foo foo food\n")
          (goto-char (point-min))
          (define-key isearch-mode-map (kbd "<f12>")
                      (lambda ()
                        (interactive)
                        (setq query isearch-string)
                        (isearch-exit)))
          ;; Default Backspace would only undo the repeated-search step.
          (execute-kbd-macro
           (vconcat (kbd "C-s") "foo" (kbd "C-s DEL <f12>")))
          (should (equal query "fo"))
          (should (equal (buffer-string) "foo foo food\n")))
      (when (buffer-live-p buffer)
        (with-current-buffer buffer
          (when isearch-mode (isearch-done)))
        (kill-buffer buffer)))))

(ert-deftest config-test/isearch-browser-keys-preserve-meta-prefix ()
  (let ((overriding-terminal-local-map isearch-mode-map))
    (dolist (key '("RET" "<return>"))
      (should (eq (key-binding (kbd key)) #'emacs/isearch-repeat)))
    (dolist (key '("<escape>" "M-RET" "M-<return>"))
      (should (eq (key-binding (kbd key)) #'emacs/isearch-exit)))
    (should (eq (key-binding (kbd "C-s")) #'isearch-repeat-forward))
    (should (eq (key-binding (kbd "C-r")) #'isearch-repeat-backward))
    (should (keymapp (lookup-key isearch-mode-map (kbd "ESC"))))
    (should (eq (key-binding (kbd "C-g")) #'isearch-abort))))

(defmacro config-test/with-browser-isearch (&rest body)
  "Run BODY in a displayed search buffer with isolated search history."
  (declare (indent 0) (debug t))
  `(let ((buffer (generate-new-buffer " *browser isearch test*"))
         (isearch-mode-map (copy-keymap isearch-mode-map))
         (search-ring nil)
         (regexp-search-ring nil))
     (unwind-protect
         (save-window-excursion
           (switch-to-buffer buffer)
           (insert "foo foo foo foo\n")
           (goto-char (point-min))
           ,@body)
       (when (buffer-live-p buffer)
         (with-current-buffer buffer
           (when isearch-mode (isearch-done)))
         (kill-buffer buffer)))))

(ert-deftest config-test/isearch-enter-follows-initial-and-reversed-direction ()
  (dolist (fixture '(("C-s foo RET <f12> <escape>" 8 t)
                     ("C-s foo <return> <f12> <escape>" 8 t)
                     ("C-r foo RET <f12> <escape>" 9 nil)
                     ("C-s foo RET C-r RET <f12> <escape>" 1 nil)
                     ("C-r foo RET C-s RET <f12> <escape>" 16 t)
                     ;; The next session must use its own initial direction.
                     ("C-r foo <escape> C-a C-s foo RET <f12> <escape>" 8 t)))
    (pcase-let ((`(,keys ,expected-point ,forward) fixture))
      (config-test/with-browser-isearch
        (when (string-prefix-p "C-r" keys) (goto-char (point-max)))
        (let (snapshot)
          (define-key isearch-mode-map (kbd "<f12>")
                      (lambda ()
                        (interactive)
                        (setq snapshot (list (point) isearch-forward isearch-string
                                             (and isearch-mode t)))))
          (execute-kbd-macro (kbd keys))
          (should (equal snapshot (list expected-point forward "foo" t)))
          (should (= (point) expected-point))
          (should-not isearch-mode)
          (should (equal (buffer-string) "foo foo foo foo\n")))))))

(ert-deftest config-test/isearch-enter-keeps-numeric-prefix-behavior ()
  (dolist (forward '(t nil))
    (config-test/with-browser-isearch
      (unless forward (goto-char (point-max)))
      (let ((isearch-mode-hook
             (cons (lambda () (setq-local isearch-allow-prefix t))
                   isearch-mode-hook)))
        (execute-kbd-macro
         (vconcat (kbd (if forward "C-s" "C-r"))
                  "foo" (kbd "C-u 2 RET <escape>")))
        (should (= (point) (if forward 12 5)))
        (should-not isearch-mode)))))

(ert-deftest config-test/isearch-escape-exits-empty-query-without-prompting ()
  (dolist (key '("<escape>" "M-RET" "M-<return>"))
    (config-test/with-browser-isearch
      (let ((search-nonincremental-instead t))
        (cl-letf (((symbol-function 'isearch-edit-string)
                   (lambda () (ert-fail "Exit opened a search prompt"))))
          (execute-kbd-macro (vconcat (kbd "C-s") (kbd key)))
          (should-not isearch-mode)
          (should (= (point) (point-min)))
          (should search-nonincremental-instead))))))

(ert-deftest config-test/isearch-meta-enter-finishes-at-current-match ()
  (config-test/with-browser-isearch
    (execute-kbd-macro (kbd "C-s foo RET M-RET"))
    (should (= (point) 8))
    (should-not isearch-mode)))

(ert-deftest config-test/isearch-enter-retains-empty-query-history-and-wrap ()
  (config-test/with-browser-isearch
    (let ((search-ring '("foo")))
      (execute-kbd-macro (kbd "C-s RET <escape>"))
      (should (= (point) 4))
      (should-not isearch-mode)))
  (config-test/with-browser-isearch
    ;; With the existing wrap pause, the first repeat fails at end of buffer;
    ;; another Enter wraps to the first match, just as another C-s would.
    (goto-char 13)
    (execute-kbd-macro (kbd "C-s foo RET RET <escape>"))
    (should (= (point) 4))
    (should-not isearch-mode)))

(provide 'navigation-tests)
;;; navigation-tests.el ends here
