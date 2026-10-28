;;; jujutsu-tests.el --- On-demand Majutsu regressions -*- lexical-binding: t; -*-

(require 'ert)

(defconst config-test/majutsu-loaded-on-startup (featurep 'majutsu)
  "Whether configuration startup eagerly loaded Majutsu.")

(ert-deftest config-test/majutsu-startup-is-lazy-and-source-declared ()
  (should-not config-test/majutsu-loaded-on-startup)
  (should (memq 'majutsu packages/declared))
  (let ((source (alist-get 'majutsu packages/vc-sources)))
    (should (equal (plist-get source :url) "https://github.com/0WD0/majutsu"))
    (should (eq (plist-get source :vc-backend) 'Git)))
  (dolist (command '(majutsu majutsu-log majutsu-dispatch))
    (should (commandp command))))

(ert-deftest config-test/majutsu-owns-vcs-bindings ()
  (dolist (binding '(("C-x g" . majutsu-log)
                     ("C-x M-g" . majutsu-dispatch)
                     ("C-x j" . majutsu-log)
                     ("C-x M-j" . majutsu-dispatch)))
    (should (eq (key-binding (kbd (car binding))) (cdr binding))))
  (should-not magit-define-global-key-bindings)
  ;; Magit's after-init callback must not restore the old standalone shortcut.
  (magit-maybe-define-global-key-bindings)
  (should-not (key-binding (kbd "C-c M-g")))
  (should (memq 'magit packages/declared))
  (should (commandp 'magit-status)))

(provide 'jujutsu-tests)
;;; jujutsu-tests.el ends here
