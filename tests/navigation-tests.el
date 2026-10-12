;;; navigation-tests.el --- Navigation and preview regressions -*- lexical-binding: t; -*-

(require 'ert)
(require 'cl-lib)
(require 'consult)

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

(provide 'navigation-tests)
;;; navigation-tests.el ends here
