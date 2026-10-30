;;; eglot-ui-tests.el --- Eglot navigation and documentation UI -*- lexical-binding: t; -*-

(require 'ert)
(require 'cl-lib)
(require 'xref)
(require 'eldoc)

(defvar config-test/eglot-ui-locations nil)

(cl-defmethod xref-backend-identifier-at-point ((_backend (eql config-test/eglot-ui)))
  "example")
(cl-defmethod xref-backend-definitions ((_backend (eql config-test/eglot-ui)) _identifier)
  config-test/eglot-ui-locations)
(cl-defmethod xref-backend-references ((_backend (eql config-test/eglot-ui)) _identifier)
  config-test/eglot-ui-locations)

(defmacro config-test/with-eglot-ui-xrefs (&rest body)
  "Run BODY with a source buffer and two real Xref destination buffers."
  (declare (indent 0) (debug t))
  `(let ((source (generate-new-buffer " *eglot-ui source*"))
         (first (generate-new-buffer " *eglot-ui first*"))
         (second (generate-new-buffer " *eglot-ui second*"))
         (history (list nil)))
     (let ((xref-history-storage (lambda () history))
           (xref-prompt-for-identifier nil))
       (unwind-protect
           (save-window-excursion
             (delete-other-windows)
             (switch-to-buffer source)
             (insert "example")
             (goto-char (point-min))
             (setq-local xref-backend-functions (list (lambda () 'config-test/eglot-ui)))
             (with-current-buffer first (insert "first definition\n"))
             (with-current-buffer second (insert "second definition\n"))
             ,@body)
         (xref-clear-marker-stack)
         (dolist (buffer (list source first second (get-buffer xref-buffer-name)))
           (when (buffer-live-p buffer) (kill-buffer buffer)))))))

(ert-deftest config-test/eglot-ui-single-definition-keeps-source-and-return-history ()
  (config-test/with-eglot-ui-xrefs
    (let ((config-test/eglot-ui-locations
           (list (xref-make "first definition" (xref-make-buffer-location first 1)))))
      (eglot-ui/peek-definition)
      (should (eq (current-buffer) first))
      (should (get-buffer-window source))
      (should (eq xref-show-definitions-function #'consult-xref))
      (xref-go-back)
      (should (eq (current-buffer) source))
      (should (= (point) 1)))))

(ert-deftest config-test/eglot-ui-multiple-xrefs-use-bottom-list-and-preview ()
  (dolist (command '(eglot-ui/peek-definition eglot-ui/peek-references))
    (config-test/with-eglot-ui-xrefs
      (let ((config-test/eglot-ui-locations
             (list (xref-make "first definition" (xref-make-buffer-location first 1))
                   (xref-make "second definition" (xref-make-buffer-location second 1)))))
        (call-interactively command)
        (should (eq (current-buffer) (get-buffer xref-buffer-name)))
        (should (get-buffer-window source))
        (should (get-buffer-window first))
        (should (= (window-total-width) (frame-width)))
        (should (> (window-top-line) 0))
        (xref-next-line)
        (should (get-buffer-window second))
        (xref-quit-and-goto-xref)
        (should (eq (current-buffer) second))
        (xref-go-back)
        (should (eq (current-buffer) source))
        (should (eq xref-show-xrefs-function #'consult-xref))))))

(ert-deftest config-test/eglot-ui-documentation-opens-at-top-and-updates-async ()
  (save-window-excursion
    (delete-other-windows)
    (with-temp-buffer
      (let ((source (current-buffer))
            (documentation (generate-new-buffer " *eldoc*"))
            callback)
        (unwind-protect
            (progn
              (switch-to-buffer source)
              (let ((eldoc--doc-buffer documentation)
                    (eldoc-documentation-strategy #'eldoc-documentation-compose)
                    (eldoc-display-functions '(eldoc-display-in-buffer))
                    (eldoc-documentation-functions
                     (list (lambda (cb &rest _) (setq callback cb) t))))
                (call-interactively #'eldoc-print-current-symbol-info)
                (should callback)
                (should-not (get-buffer-window documentation))
                (funcall callback "Example documentation" :thing 'example)
                (let ((window (get-buffer-window documentation)))
                  (should window)
                  (should (eq (window-parameter window 'window-side) 'top))
                  (should (eq (current-buffer) source))
                  (with-current-buffer documentation
                    (should (string-match-p "Example documentation" (buffer-string)))))))
          (kill-buffer documentation))))))

(ert-deftest config-test/eglot-ui-workspace-symbols-use-manual-file-preview ()
  (should (memq 'consult-eglot packages/declared))
  (require 'consult-eglot)
  (let ((this-command 'consult-eglot-symbols))
    (should (equal (plist-get (consult--customize-args nil :preview-key consult-preview-key)
                             :preview-key)
                   "M-.")))
  (with-temp-buffer
    (cl-letf (((symbol-function 'project-current) (lambda (&rest _) nil)))
      (should-error (consult-eglot-symbols) :type 'user-error))))

(ert-deftest config-test/eglot-ui-hydra-dispatches-and-leaves-menu ()
  (should (eq (key-binding (kbd "C-x C-h l")) #'hydra-eglot/body))
  (dolist (entry '(("d" . eglot-ui/peek-definition)
                   ("r" . eglot-ui/peek-references)
                   ("s" . consult-eglot-symbols)
                   ("h" . eldoc-print-current-symbol-info)))
    (let (called)
      (cl-letf (((symbol-function (cdr entry))
                 (lambda () (interactive) (setq called t))))
        (unwind-protect
            (progn
              (execute-kbd-macro (vconcat (kbd "C-x C-h l") (kbd (car entry))))
              (should called)
              (should-not hydra-curr-map))
          (hydra-keyboard-quit))))))

(provide 'eglot-ui-tests)
;;; eglot-ui-tests.el ends here
