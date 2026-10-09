;;; rust-tests.el --- Rust diagnostic-policy regressions -*- lexical-binding: t; -*-

(require 'ert)
(require 'cl-lib)
(require 'eglot)
(require 'flymake)

(ert-deftest config-test/rust-diagnostic-policy-is-buffer-local-and-preserves-opt-outs ()
  (let* ((ignored '(:inlayHintProvider :documentHighlightProvider))
         (eglot-ignored-server-capabilities ignored)
         (treesit-auto-install nil))
    (dolist (mode (append '(rust-mode)
                         (when (treesit-ready-p 'rust t) '(rust-ts-mode))))
      (with-temp-buffer
        (let ((starts 0))
          (cl-letf (((symbol-function 'eglot-ensure)
                     (lambda ()
                       (cl-incf starts)
                       (should (local-variable-p 'eglot-ignored-server-capabilities))
                       (should (memq :diagnosticProvider eglot-ignored-server-capabilities)))))
            (funcall mode)
            (should (= starts 1))
            (rust/eglot-ensure)
            (should (= starts 2))
            (should (= (cl-count :diagnosticProvider eglot-ignored-server-capabilities) 1))
            (should (memq :inlayHintProvider eglot-ignored-server-capabilities))
            (should (memq :documentHighlightProvider eglot-ignored-server-capabilities))
            (should (= flymake-no-changes-timeout 0.5))
            (should flymake-start-on-save-buffer)))))
    (should (eq eglot-ignored-server-capabilities ignored))
    (should-not (memq :diagnosticProvider ignored))
    (with-temp-buffer
      (cl-letf (((symbol-function 'eglot-ensure) #'ignore))
        (js-mode))
      (should-not (memq :diagnosticProvider eglot-ignored-server-capabilities)))))

(ert-deftest config-test/rust-rename-is-local-and-recent-files-stay-global ()
  (should (eq (key-binding (kbd "C-c R")) #'consult-recent-file))
  (should-not (eq (key-binding (kbd "C-c r")) #'consult-recent-file))
  (dolist (mode (append '(rust-mode)
                       (when (treesit-ready-p 'rust t) '(rust-ts-mode))))
    (with-temp-buffer
      (cl-letf (((symbol-function 'eglot-ensure) #'ignore))
        (funcall mode))
      (should (eq (key-binding (kbd "C-c r")) #'rust/rename))
      (should (eq (key-binding (kbd "C-c R")) #'consult-recent-file))))
  (with-temp-buffer
    (cl-letf (((symbol-function 'eglot-ensure) #'ignore))
      (js-mode))
    (should-not (eq (key-binding (kbd "C-c r")) #'rust/rename))
    (should (eq (key-binding (kbd "C-c R")) #'consult-recent-file))))

(ert-deftest config-test/rust-server-contact-negotiates-push-only-for-both-modes ()
  (dolist (mode '(rust-mode rust-ts-mode))
    (should (equal (alist-get mode eglot-server-programs)
                   '(rust/eglot-server "rust-analyzer")))))

(defmacro config-test/with-eglot-pipe-server (class &rest body)
  "Run BODY with SERVER of CLASS on a pipe, without an external process."
  (declare (indent 1) (debug (form body)))
  `(let* ((process (make-pipe-process :name "config-test rust" :noquery t))
          (server (make-instance ,class :name "config-test rust" :process process)))
     (unwind-protect
         (progn
           (setf (eglot--project server) (cons 'transient default-directory))
           ,@body)
       (delete-process process)
       (jsonrpc-shutdown server t)
       (when-let* ((events (get-buffer "*config-test rust events*")))
         (kill-buffer events)))))

(ert-deftest config-test/rust-client-capabilities-keep-unrelated-features ()
  (let (base)
    (config-test/with-eglot-pipe-server 'eglot-lsp-server
      (setq base (eglot-client-capabilities server)))
    (config-test/with-eglot-pipe-server 'rust/eglot-server
      (let ((actual (eglot-client-capabilities server))
            (expected (copy-tree base)))
        (cl-remf (plist-get expected :textDocument) :diagnostic)
        (should (equal actual expected))
        (should (plist-member (plist-get base :textDocument) :diagnostic))
        (should-not (plist-member (plist-get actual :textDocument) :diagnostic))))))

(ert-deftest config-test/rust-push-diagnostics-survive-unsaved-edit-and-clear-on-fresh-report ()
  (config-test/with-eglot-pipe-server 'rust/eglot-server
    (with-temp-buffer
      (let ((eglot--managed-mode t)
            (eglot--cached-server server)
            (eglot--docver 0)
            (flymake-diagnostic-functions '(eglot-flymake-backend)))
        (insert "let unused = 1;\n")
        (cl-letf (((symbol-function 'eglot-ensure) #'ignore))
          (rust/eglot-ensure))
        (setf (eglot--capabilities server)
              '(:diagnosticProvider (:identifier "rust-analyzer")))
        (setq eglot--pushed-diagnostics
              (list [(:range (:start (:line 0 :character 4)
                              :end (:line 0 :character 10))
                      :severity 2 :code "unused_variables" :source "rustc"
                      :message "unused variable: `unused`")]
                    eglot--docver))
        (cl-letf (((symbol-function 'trusted-content-p) (lambda (&rest _) t))
                  ((symbol-function 'eglot--flymake-pull)
                   (lambda () (ert-fail "Rust must not request pull diagnostics"))))
          (unwind-protect
              (progn
                (flymake-mode 1)
                (flymake-start nil t)
                (should (= (length (flymake-diagnostics)) 1))
                ;; Change another line, then run the normal idle-check backend.
                ;; No save or compiler invocation has occurred.
                (goto-char (point-max))
                (insert "// editing\n")
                (cl-incf eglot--docver)
                (flymake-start nil t)
                (should (= (length (flymake-diagnostics)) 1))
                (should (string-match-p
                         "unused variable"
                         (flymake-diagnostic-text (car (flymake-diagnostics)))))
                ;; A fresh push (e.g. after saving a fix) must remove the warning.
                (setq eglot--pushed-diagnostics (list [] eglot--docver))
                (flymake-start nil t)
                (should-not (flymake-diagnostics)))
            (flymake-mode -1)))))))

(provide 'rust-tests)
;;; rust-tests.el ends here
