;;; snippets-tests.el --- Snippet lifecycle regressions -*- lexical-binding: t; -*-

(require 'ert)
(require 'cl-lib)
(require 'tempel)
(require 'eglot-tempel)

(defmacro config-test/with-snippet-buffer (mode &rest body)
  "Run BODY in a displayed temporary buffer using MODE."
  (declare (indent 1) (debug (form body)))
  `(let ((buffer (generate-new-buffer " *snippet test*"))
         (treesit-auto-install nil)
         (corfu-auto nil))
     (unwind-protect
         (save-window-excursion
           (switch-to-buffer buffer)
           ;; No file is visited and no language server is needed.
           (cl-letf (((symbol-function 'eglot-ensure) #'ignore))
             (funcall ,mode))
           ,@body)
       (kill-buffer buffer))))

(defun config-test/snippet-fields ()
  "Return Tempel field overlays in the current buffer."
  (cl-remove-if-not
   (lambda (overlay) (overlay-get overlay 'tempel--field))
   (overlays-in (point-min) (point-max))))

(ert-deftest config-test/snippets-rust-motion-clears-stale-argument-fields ()
  (dolist (mode (append '(rust-mode)
                       (when (treesit-ready-p 'rust t) '(rust-ts-mode))))
    (dolist (motion '("C-n" "C-p"))
      (config-test/with-snippet-buffer mode
        (insert "before\n\nafter\n")
        (goto-char 8)
        (eglot-tempel-expand-yas-snippet "call(${1:arg}, ${2:other})$0")
        ;; Editing the default produces the reported purple tempel-field face.
        (execute-kbd-macro "x")
        (should (cl-some (lambda (overlay)
                           (eq (overlay-get overlay 'face) 'tempel-field))
                         (config-test/snippet-fields)))
        (let ((text (buffer-string)))
          (execute-kbd-macro (kbd motion))
          (should-not tempel--active)
          (should-not (config-test/snippet-fields))
          (should-not (assq 'tempel--active minor-mode-overriding-map-alist))
          (should (equal (buffer-string) text)))))))

(ert-deftest config-test/snippets-stay-active-inside-call-and-between-arguments ()
  (config-test/with-snippet-buffer #'rust-mode
    (eglot-tempel-expand-yas-snippet "call(${1:arg}, ${2:other})$0")
    (execute-kbd-macro "x")
    (should tempel--active)
    ;; Ordinary cursor motion between fields must not end the snippet.
    (execute-kbd-macro (kbd "C-f"))
    (should (eq (char-before) ?,))
    (should tempel--active)
    (execute-kbd-macro (kbd "M-}"))
    (should tempel--active)
    (execute-kbd-macro "y")
    (should (equal (buffer-string) "call(x, y)"))
    (execute-kbd-macro (kbd "M-}"))
    (should-not tempel--active)
    (should-not (config-test/snippet-fields))))

(ert-deftest config-test/snippets-boundaries-remain-editable ()
  (config-test/with-snippet-buffer #'text-mode
    (insert "before\n\nafter")
    (goto-char 8)
    (tempel-insert '(p))
    ;; A zero-width template and its boundary are still valid editing positions.
    (execute-kbd-macro "x")
    (should tempel--active)
    (execute-kbd-macro (kbd "C-b"))
    (should tempel--active)
    (execute-kbd-macro (kbd "C-f"))
    (should tempel--active)
    (execute-kbd-macro (kbd "C-n"))
    (should-not tempel--active)))

(ert-deftest config-test/snippets-nested-fields-survive-inside-outer-template ()
  (config-test/with-snippet-buffer #'rust-mode
    (insert "\nafter")
    (goto-char (point-min))
    (eglot-tempel-expand-yas-snippet "outer(${1:arg}, ${2:other})$0")
    (tempel-insert '("inner(" (p "value") ")"))
    (should (= (length tempel--active) 2))
    ;; Leave the inner call but stay in the enclosing template's second field.
    (goto-char (point-min))
    (search-forward "other")
    (execute-kbd-macro (kbd "C-b"))
    (should (= (length tempel--active) 2))
    (execute-kbd-macro (kbd "C-n"))
    (should-not tempel--active)
    (should-not (config-test/snippet-fields))))

(ert-deftest config-test/snippets-cleanup-finalizes-post-action-once ()
  (config-test/with-snippet-buffer #'text-mode
    (insert "\nafter")
    (goto-char (point-min))
    (let ((count 0))
      (tempel-insert
       (list '(p "value") :post (list 'funcall (lambda () (cl-incf count)))))
      (let ((text (buffer-string)))
        (execute-kbd-macro (kbd "C-n"))
        (should (= count 1))
        (should-not tempel--active)
        (should (equal (buffer-string) text))
        (execute-kbd-macro (kbd "C-b"))
        (should (= count 1))))))

(ert-deftest config-test/snippets-cleanup-is-local-and-idempotent ()
  (dolist (mode '(rust-mode text-mode conf-mode))
    (config-test/with-snippet-buffer mode
      (snippets/setup-capf)
      (snippets/setup-capf)
      (should (local-variable-p 'post-command-hook))
      (should (= (cl-count #'snippets/finish-outside post-command-hook) 1))
      (should-not tempel--active)
      (insert "text")
      (goto-char (point-min))
      (execute-kbd-macro (kbd "C-f"))))
  (should-not (memq #'snippets/finish-outside (default-value 'post-command-hook))))

(provide 'snippets-tests)
;;; snippets-tests.el ends here
