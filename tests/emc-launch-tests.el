;;; emc-launch-tests.el --- Launcher window fallback contract -*- lexical-binding: t; -*-

(require 'ert)
(require 'cl-lib)

(defvar mu4e-main-buffer-name "*mu4e-main*")

(ert-deftest config-test/emc-open-calc-waits-before-running-calc ()
  (let (delay function)
    (cl-letf (((symbol-function 'run-at-time)
               (lambda (secs _repeat fn &rest _)
                 (setq delay secs function fn)))
              ((symbol-function 'calc)
               (lambda (&rest _) (ert-fail "Calc ran before the frame settled"))))
      (emc/open-calc)
      (should (= delay 0.3))
      (should (eq function #'calc)))))

(ert-deftest config-test/emc-open-mail-uses-normal-mu4e-when-split-succeeds ()
  (let (called)
    (cl-letf (((symbol-function 'mu4e)
               (lambda (&rest _) (setq called 'split)))
              ((symbol-function 'switch-to-buffer)
               (lambda (&rest _) (ert-fail "Mail fell back without a refused split"))))
      (emc/open-mail)
      (should (eq called 'split)))))

(ert-deftest config-test/emc-open-mail-falls-back-when-split-is-refused ()
  (let (shown)
    (cl-letf (((symbol-function 'mu4e)
               (lambda (&rest _) (error "Window #<window 2> too small for splitting")))
              ((symbol-function 'switch-to-buffer)
               (lambda (buffer &rest _) (setq shown buffer))))
      (emc/open-mail)
      (should (equal shown mu4e-main-buffer-name)))))

(ert-deftest config-test/emc-open-mail-reraises-other-errors ()
  (let ((switched nil))
    (cl-letf (((symbol-function 'mu4e)
               (lambda (&rest _) (error "mu server is gone")))
              ((symbol-function 'switch-to-buffer)
               (lambda (&rest _) (setq switched t))))
      (should-error (emc/open-mail) :type 'error)
      (should-not switched))))

;;; emc-launch-tests.el ends here
