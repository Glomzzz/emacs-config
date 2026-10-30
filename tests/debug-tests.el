;;; debug-tests.el --- Dape menu and command integration -*- lexical-binding: t; -*-

(require 'ert)
(require 'cl-lib)
(require 'dape)

(ert-deftest config-test/debug-menu-keeps-stepping-active-and-runs-foreign-keys ()
  (save-window-excursion
    (with-temp-buffer
      (switch-to-buffer (current-buffer))
      (insert "abc")
      (goto-char (point-min))
      (let (steps)
        (cl-letf (((symbol-function 'dape-next)
                   (lambda () (interactive) (push 'next steps)))
                  ((symbol-function 'dape-continue)
                   (lambda () (interactive) (push 'continue steps))))
          (unwind-protect
              (progn
                (execute-kbd-macro (kbd "C-x C-h d n C-f c q"))
                (should (equal (nreverse steps) '(next continue)))
                (should (= (point) 2))
                (should-not hydra-curr-map))
            (hydra-keyboard-quit)))))))

(ert-deftest config-test/debug-menu-prefixes-dispatch-and-exit-for-buffer-commands ()
  (dolist (entry '(("ss" dape-select-session nil)
                   ("st" dape-select-thread nil)
                   ("sf" dape-select-stack nil)
                   ("su" dape-stack-select-up nil)
                   ("sd" dape-stack-select-down nil)
                   ("r" dape-restart-frame nil)
                   ("ds" dape-restart nil)
                   ("sl" debug/locals t)
                   ("sb" debug/breakpoints t)
                   ("se" debug/watches t)
                   ("dd" dape t)
                   ("Q" dape-disconnect-quit t)))
    (pcase-let ((`(,keys ,command ,exit) entry))
      (let (called)
        (cl-letf (((symbol-function command)
                   (lambda () (interactive) (setq called t))))
          (unwind-protect
              (progn
                (execute-kbd-macro (vconcat (kbd "C-x C-h d") (kbd keys)))
                (should called)
                (should (eq (not hydra-curr-map) exit)))
            (hydra-keyboard-quit)))))))

(ert-deftest config-test/debug-evaluation-uses-region-and-symbol-without-moving-point ()
  (with-temp-buffer
    (insert "before value_name after")
    (goto-char 10)
    (let ((source-point (point))
          (source-mark (mark t))
          (transient-mark-mode t)
          expressions)
      (cl-letf (((symbol-function 'dape-evaluate-expression)
                 (lambda (connection expression context)
                   (interactive
                    (progn
                      (should (use-region-p))
                      (list 'connection
                            (buffer-substring-no-properties
                             (region-beginning) (region-end)))))
                   (should (eq connection 'connection))
                   (should (equal context "watch"))
                   (push expression expressions))))
        (debug/evaluate-symbol)
        (should (equal expressions '("value_name")))
        (should (= (point) source-point))
        (should (eq (mark t) source-mark))
        (should-not (use-region-p))
        (should-error (debug/evaluate-region) :type 'user-error)
        (goto-char 1)
        (push-mark 7 t t)
        (debug/evaluate-region)
        (should (equal (car expressions) "before"))))))

(ert-deftest config-test/debug-info-selects-native-locals-breakpoints-and-watches ()
  (let ((dape--connections nil)
        (dape--connection-selected nil)
        (dape--info-buffers nil)
        (dape--info-buffer-display-history nil))
    (unwind-protect
        (save-window-excursion
          (delete-other-windows)
          (dolist (entry '((debug/locals . dape-info-scope-mode)
                           (debug/breakpoints . dape-info-breakpoints-mode)
                           (debug/watches . dape-info-watch-mode)))
            (call-interactively (car entry))
            (should (derived-mode-p (cdr entry)))
            (should (eq (window-parameter nil 'window-side) 'right))))
      (dolist (buffer dape--info-buffers)
        (when (buffer-live-p buffer) (kill-buffer buffer))))))

(ert-deftest config-test/debug-breakpoint-heads-change-real-source-breakpoints ()
  (let ((dape--connections nil)
        (dape--breakpoints nil)
        (dape-update-ui-hook nil))
    (save-window-excursion
      (with-temp-buffer
        (setq buffer-file-name (expand-file-name "debug-menu.c" temporary-file-directory))
        (insert "int value = 1;\n")
        (goto-char 1)
        (switch-to-buffer (current-buffer))
        (unwind-protect
            (progn
              (execute-kbd-macro (kbd "C-x C-h d bb q"))
              (should (= (length dape--breakpoints) 1))
              (should (cl-some #'overlayp (overlays-at (point))))
              (cl-letf (((symbol-function 'read-string) (lambda (&rest _) "value > 2")))
                (execute-kbd-macro (kbd "C-x C-h d bc q")))
              (let ((breakpoint (car dape--breakpoints)))
                (should (eq (dape--source-breakpoint-type breakpoint) 'expression))
                (should (equal (dape--source-breakpoint-value breakpoint) "value > 2")))
              (execute-kbd-macro (kbd "C-x C-h d bd q"))
              (should-not dape--breakpoints))
          (hydra-keyboard-quit)
          (dape-breakpoint-remove-all))))))

(provide 'debug-tests)
;;; debug-tests.el ends here
