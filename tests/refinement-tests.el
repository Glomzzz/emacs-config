;;; refinement-tests.el --- Configurable-default regressions -*- lexical-binding: t; -*-

(require 'ert)
(require 'cl-lib)

(ert-deftest config-test/haskell-server-settings-are-project-local ()
  (let ((haskell/server-threads 4)
        (haskell/max-completions 250))
    (should (equal (haskell/server-command)
                   '("haskell-language-server-wrapper" "--lsp" "-j" "4")))
    (should (equal (haskell/eglot-workspace-configuration nil)
                   '(:haskell (:maxCompletions 250)))))
  (let ((haskell/server-threads nil))
    (should (equal (haskell/server-command)
                   '("haskell-language-server-wrapper" "--lsp")))))

(ert-deftest config-test/haskell-does-not-override-server-sorting ()
  (with-temp-buffer
    (cl-letf (((symbol-function 'eglot-ensure) #'ignore))
      (haskell-mode)
      (should-not (local-variable-p 'corfu-sort-override-function)))))

(ert-deftest config-test/shared-buffer-size-policy ()
  (with-temp-buffer
    (insert "12345")
    (let ((buffers/feature-size-limit 5))
      (should-not (buffers/small-p))
      (should (buffers/small-p 6)))
    (let ((buffers/feature-size-limit nil))
      (should (buffers/small-p)))))

(ert-deftest config-test/whitespace-preserves-prose-and-markdown-breaks ()
  (dolist (mode '(text-mode markdown-mode))
    (with-temp-buffer
      (funcall mode)
      (insert "line  \n")
      (emacs/delete-trailing-whitespace-maybe)
      (should (equal (buffer-string) "line  \n")))))

(ert-deftest config-test/whitespace-respects-project-policy ()
  (with-temp-buffer
    (emacs-lisp-mode)
    (insert "code  \n")
    (let ((editor/trim-trailing-whitespace nil))
      (emacs/delete-trailing-whitespace-maybe)
      (should (equal (buffer-string) "code  \n")))
    (emacs/delete-trailing-whitespace-maybe)
    (should (equal (buffer-string) "code\n")))
  (with-temp-buffer
    (text-mode)
    (insert "text  \n")
    (let ((editor/trim-trailing-whitespace t))
      (emacs/delete-trailing-whitespace-maybe)
      (should (equal (buffer-string) "text\n")))))

(ert-deftest config-test/text-layout-keeps-upstream-defaults ()
  (with-temp-buffer
    (text-mode)
    (should bidi-display-reordering)
    (should-not bidi-paragraph-direction)
    (should-not bidi-inhibit-bpa)
    (should-not sentence-end)))

(ert-deftest config-test/javascript-runtime-follows-project-not-buffer-type ()
  (config-test/with-directory
    (with-temp-buffer
      (setq major-mode 'typescript-mode)
      (cl-letf (((symbol-function 'executable-find)
                 (lambda (name) (concat "/bin/" name))))
        (should (equal (javascript--runtime root) "/bin/node"))
        (config-test/file root "bun.lock")
        (should (equal (javascript--runtime root) "/bin/bun"))
        (config-test/file root "deno.json" "{}")
        (should (equal (javascript--runtime root) "/bin/deno"))
        (let ((javascript/runtime 'node))
          (should (equal (javascript--runtime root) "/bin/node")))))))

(ert-deftest config-test/javascript-explicit-runtime-never-silently-falls-back ()
  (let ((javascript/runtime 'bun))
    (cl-letf (((symbol-function 'executable-find) (lambda (_name) nil)))
      (should-error (javascript--runtime default-directory) :type 'user-error))))

(ert-deftest config-test/javascript-project-commands-override-generated-commands ()
  (let ((javascript/run-command "npm run dev")
        (javascript/build-command "npm run build")
        (javascript/check-command "npm test")
        invoked)
    (cl-letf (((symbol-function 'javascript/project-root) (lambda () default-directory))
              ((symbol-function 'compile) (lambda (command) (push command invoked))))
      (javascript/run)
      (javascript/compile)
      (javascript/check)
      (should (equal (reverse invoked) '("npm run dev" "npm run build" "npm test"))))))

(ert-deftest config-test/javascript-debug-settings-are-evaluated-at-launch ()
  (require 'dape)
  (let ((javascript/inspector-port 9333)
        (javascript/browser-url "http://localhost:8080")
        (javascript/debug-adapter-command "custom-js-debug")
        (javascript/deno-permissions '("--allow-read")))
    (should (equal (javascript/deno-debug-arguments)
                   ["run" "--inspect-wait=127.0.0.1:9333" "--allow-read"]))
    (should (equal (dape-config-get (alist-get 'javascript-chrome dape-configs) :url)
                   "http://localhost:8080"))
    (should (equal (dape-config-get (alist-get 'javascript-node dape-configs) 'command)
                   "custom-js-debug"))
    (should (= (dape-config-get (alist-get 'typescript-deno dape-configs)
                               :attachSimplePort) 9333)))
  (let ((javascript/deno-permissions nil))
    (should-not (member "--allow-all" (append (javascript/deno-debug-arguments) nil)))))

(provide 'refinement-tests)
;;; refinement-tests.el ends here
