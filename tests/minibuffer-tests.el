;;; minibuffer-tests.el --- Completion session regressions -*- lexical-binding: t; -*-

(require 'ert)
(require 'cl-lib)

(defun config-test/record-vertico-session (command input)
  "Exercise the configured recording hook for COMMAND with INPUT.
Batch Emacs reads prompts from stdin, so simulate the input reader while
using the extension's real buffer-local command and exit hooks."
  (with-temp-buffer
    (let ((this-command command))
      (setq-local vertico--input (cons input (length input)))
      (funcall (car (memq #'vertico-repeat-save minibuffer-setup-hook)))
      (should (local-variable-p 'post-command-hook))
      (should (local-variable-p 'minibuffer-exit-hook))
      (cl-letf (((symbol-function 'minibuffer-contents-no-properties)
                 (lambda () input)))
        (dolist (hook '(post-command-hook minibuffer-exit-hook))
          ;; Skip the `t' sentinel for global hooks: only the recorder's
          ;; local callbacks belong to this simulated completion session.
          (dolist (function (symbol-value hook))
            (unless (eq function t) (funcall function))))))))

(ert-deftest config-test/vertico-repeat-bindings-and-history ()
  (should (eq (key-binding (kbd "M-R")) #'vertico-repeat))
  (should (eq (lookup-key vertico-map (kbd "C-r")) #'vertico-repeat-select))
  (should (eq (lookup-key minibuffer-local-map (kbd "M-r")) #'consult-history))
  (should (eq (lookup-key vertico-map (kbd "RET")) #'vertico-directory-enter))
  (should (memq #'vertico-repeat-save minibuffer-setup-hook))
  (should (memq 'vertico-repeat-history savehist-additional-variables)))

(ert-deftest config-test/vertico-repeat-records-sessions-and-keeps-default-filters ()
  (require 'vertico-repeat)
  (let ((vertico-repeat-history nil)
        (savehist-minibuffer-history-variables nil))
    (config-test/record-vertico-session 'consult-line "needle")
    (should (equal vertico-repeat-history '((consult-line "needle"))))
    (config-test/record-vertico-session 'consult-line "needle")
    (should (= (length vertico-repeat-history) 1))
    (config-test/record-vertico-session 'consult-line "")
    (config-test/record-vertico-session 'execute-extended-command "find-file")
    (should (equal vertico-repeat-history '((consult-line "needle"))))
    ;; Ordinary buffers do not get the recorder's local timer/exit hooks.
    (with-temp-buffer
      (vertico-repeat-save)
      (should-not (local-variable-p 'minibuffer-exit-hook)))))

(ert-deftest config-test/vertico-repeat-history-survives-savehist-round-trip ()
  (require 'vertico-repeat)
  (config-test/with-directory
    (let ((savehist-file (expand-file-name "history" root))
          (savehist-additional-variables '(vertico-repeat-history))
          (savehist-minibuffer-history-variables nil)
          (savehist-ignored-variables nil)
          (savehist-last-checksum nil)
          (vertico-repeat-history '((consult-line "needle")
                                   (consult-recent-file "notes"))))
      (savehist-save)
      (setq vertico-repeat-history nil)
      (load savehist-file nil 'nomessage)
      (should (equal vertico-repeat-history
                     '((consult-line "needle")
                       (consult-recent-file "notes")))))))

(ert-deftest config-test/vertico-repeat-replays-without-changing-global-hooks ()
  (require 'vertico-repeat)
  (with-temp-buffer
    (let ((vertico-repeat-history '((consult-line "needle")))
          (setup-hooks minibuffer-setup-hook)
          replayed)
      (cl-letf (((symbol-function 'command-execute)
                 (lambda (command &rest _)
                   (should (eq command #'consult-line))
                   (should (eq this-command #'consult-line))
                   (should-not (equal minibuffer-setup-hook setup-hooks))
                   (setq replayed t))))
        (vertico-repeat)
        (should replayed)
        (should (equal minibuffer-setup-hook setup-hooks))))))

(ert-deftest config-test/vertico-file-input-literal-versus-selected-candidate ()
  (should (eq (lookup-key vertico-map (kbd "M-RET")) #'vertico-exit-input))
  ;; Batch Emacs reads prompts from stdin, so simulate the minibuffer contents
  ;; while exercising the configured bindings and Vertico's real exit commands.
  (dolist (case '(("RET" . "plt-plan.org") ("M-RET" . "plan.org")))
    (with-temp-buffer
      (insert "plan.org")
      (let ((vertico--index 0)
            (vertico--candidates '("plt-plan.org"))
            (vertico--total 1)
            (vertico--base "")
            (vertico--metadata '(metadata (category . file)))
            (minibuffer--require-match nil)
            (current-prefix-arg nil)
            accepted)
        (cl-letf (((symbol-function 'minibuffer-contents-no-properties)
                   (lambda () (buffer-string)))
                  ((symbol-function 'delete-minibuffer-contents) #'erase-buffer)
                  ((symbol-function 'exit-minibuffer)
                   (lambda () (setq accepted (buffer-string)))))
          (call-interactively (lookup-key vertico-map (kbd (car case))))
          (should (equal accepted (cdr case))))))))

(provide 'minibuffer-tests)
;;; minibuffer-tests.el ends here
