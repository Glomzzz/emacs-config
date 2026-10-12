;;; help-tests.el --- On-demand Helpful regressions -*- lexical-binding: t; -*-

(require 'ert)
(require 'cl-lib)

(defconst config-test/helpful-loaded-on-startup (featurep 'helpful)
  "Whether configuration startup eagerly loaded Helpful.
Capture this before individual tests exercise its inspection commands.")

(defmacro config-test/with-helpful-buffer (&rest body)
  "Run BODY with Helpful's real renderer and isolated result buffers."
  (declare (indent 0) (debug t))
  `(let ((original-buffers (buffer-list))
         (helpful-switch-buffer-function #'set-buffer))
     (unwind-protect
         (save-window-excursion
           (save-current-buffer ,@body))
       (dolist (buffer (buffer-list))
         (unless (memq buffer original-buffers)
           (kill-buffer buffer))))))

(ert-deftest config-test/helpful-startup-is-lazy-and-declared ()
  (should-not config-test/helpful-loaded-on-startup)
  (should (memq 'helpful packages/declared)))

(ert-deftest config-test/helpful-bindings-preserve-built-in-alternatives ()
  (dolist (binding '(("C-h f" . helpful-callable)
                     ("C-h v" . helpful-variable)
                     ("C-h k" . helpful-key)
                     ("C-h x" . helpful-command)
                     ("C-h C-." . helpful-at-point)))
    (should (eq (key-binding (kbd (car binding))) (cdr binding))))
  (dolist (command '(describe-function describe-variable describe-key
                     describe-command))
    (should (commandp command)))
  (should (eq (key-binding (kbd "C-h o")) #'describe-symbol))
  (should (eq (key-binding (kbd "C-c i")) #'consult-info))
  (should (eq (key-binding (kbd "C-h B")) #'embark-bindings)))

(ert-deftest config-test/helpful-callable-renders-function-and-macro-source ()
  (require 'helpful)
  (dolist (symbol '(funcs/duplicate-line mod/import))
    (config-test/with-helpful-buffer
      (helpful-callable symbol)
      (should (derived-mode-p 'helpful-mode))
      (should buffer-read-only)
      (should (string-match-p (regexp-quote (symbol-name symbol)) (buffer-string)))
      (should (string-match-p "Source Code" (buffer-string)))))
  (config-test/with-helpful-buffer
    (helpful-callable 'config-test/with-helpful-buffer)
    (should (derived-mode-p 'helpful-mode))
    (should (string-match-p "macro" (buffer-string)))
    (should (string-match-p "defmacro" (buffer-string)))))

(ert-deftest config-test/helpful-variable-renders-buffer-local-value ()
  (require 'helpful)
  (config-test/with-helpful-buffer
    (with-temp-buffer
      (setq-local editor/trim-trailing-whitespace nil)
      (helpful-variable 'editor/trim-trailing-whitespace)
      (should (derived-mode-p 'helpful-mode))
      (should (string-match-p "Value in" (buffer-string)))
      (should (string-match-p "nil" (buffer-string))))))

(ert-deftest config-test/helpful-key-describes-current-binding ()
  (require 'helpful)
  (config-test/with-helpful-buffer
    (helpful-key (kbd "C-c f"))
    (should (derived-mode-p 'helpful-mode))
    (should (string-match-p "funcs/format-buffer" (buffer-string)))
    (should (string-match-p "C-c f" (buffer-string)))))

(ert-deftest config-test/helpful-at-point-uses-elisp-symbol ()
  (require 'helpful)
  (config-test/with-helpful-buffer
    (with-temp-buffer
      (emacs-lisp-mode)
      (insert "funcs/duplicate-line")
      (goto-char (point-min))
      (call-interactively #'helpful-at-point)
      (should (derived-mode-p 'helpful-mode))
      (should (string-match-p "funcs/duplicate-line" (buffer-string))))))

(provide 'help-tests)
;;; help-tests.el ends here
