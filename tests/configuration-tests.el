;;; configuration-tests.el --- Configuration regressions -*- lexical-binding: t; -*-

(require 'cl-lib)
(require 'ert)
(require 'eglot)
(require 'project)
(require 'apheleia)

(defmacro config-test/with-directory (&rest body)
  "Run BODY with a temporary project ROOT, then remove it."
  (declare (indent 0) (debug t))
  `(let* ((root (file-name-as-directory
                (make-temp-file "emacs-config-test-" t)))
          (default-directory root)
          (project-vc-cache-timeout 0)
          (project-vc-non-essential-cache-timeout 0))
     (unwind-protect
         (progn ,@body)
       (delete-directory root t))))

(defun config-test/file (root path &optional content)
  "Write CONTENT to PATH below ROOT and return its absolute name."
  (let ((file (expand-file-name path root)))
    (make-directory (file-name-directory file) t)
    (write-region (or content "") nil file nil 'silent)
    file))

(ert-deftest config-test/workspace-settings-are-separated ()
  (dolist (entry '((nix-ts-mode . :nixd)
                   (typst-ts-mode . :tinymist)
                   (typescript-ts-mode . :typescript)
                   (haskell-mode . :haskell)
                   (haskell-literate-mode . :haskell)))
    (with-temp-buffer
      (setq major-mode (car entry))
      (should (plist-member (lsp/workspace-configuration 'server)
                            (cdr entry))))))

(ert-deftest config-test/direct-completion-command-runs-after-exit ()
  (with-temp-buffer
    (let* ((command (list :title "Import" :command "extend-import"))
           (item (list :command command))
           (proxy (propertize "foo" 'eglot--lsp-item item))
           events)
      (cl-letf (((symbol-function 'eglot-execute)
                 (lambda (server action)
                   (should (eq server 'server))
                   (push action events)
                   (cl-remf action :title))))
        (lsp/completion-command-execute
         (lambda (_proxy _status) (push 'exit events))
         proxy 'finished (current-buffer) 'server (list proxy))
        (should (eq (cadr events) 'exit))
        (should (equal (plist-get (car events) :command) "extend-import"))
        (should (equal (plist-get (plist-get item :command) :title) "Import"))))))

(ert-deftest config-test/completion-command-uses-originating-buffer ()
  (let ((source (generate-new-buffer " *config-test source*")))
    (unwind-protect
        (let* ((item (list :command '(:command "import")))
               (proxy (propertize "foo" 'eglot--lsp-item item))
               (exit (lambda (_proxy _status)
                       (should (eq (current-buffer) source))))
               capf executed)
          (with-current-buffer source
            (cl-letf (((symbol-function 'eglot-current-server)
                       (lambda () 'origin-server)))
              (setq capf (lsp/completion-command-filter
                          (list 1 1 (list proxy) :exit-function exit)))))
          (with-temp-buffer
            (cl-letf (((symbol-function 'eglot-execute)
                       (lambda (server _command)
                         (should (eq server 'origin-server))
                         (should (eq (current-buffer) source))
                         (setq executed t))))
              ;; *Completions* strips candidate properties.
              (funcall (plist-get (cdddr capf) :exit-function)
                       (substring-no-properties proxy) 'finished)))
          (should executed))
      (kill-buffer source))))

(ert-deftest config-test/completion-command-does-not-run-on-abort-or-error ()
  (with-temp-buffer
    (let* ((proxy (propertize "foo" 'eglot--lsp-item
                              '(:command (:command "import"))))
           executed exited)
      (cl-letf (((symbol-function 'eglot-execute)
                 (lambda (&rest _) (setq executed t))))
        (lsp/completion-command-execute
         (lambda (&rest _) (setq exited t)) proxy 'sole
         (current-buffer) 'server (list proxy))
        (should exited)
        (should-not executed)
        (should-error
         (lsp/completion-command-execute
          (lambda (&rest _) (error "Edit failed")) proxy 'finished
          (current-buffer) 'server (list proxy)))
        (should-not executed)))))

(ert-deftest config-test/completion-after-source-buffer-is-killed ()
  (let ((source (generate-new-buffer " *config-test killed*")))
    (kill-buffer source)
    (lsp/completion-command-execute
     (lambda (&rest _) (ert-fail "Dead-buffer exit ran"))
     "foo" 'finished source 'server '("foo"))))

(ert-deftest config-test/completion-filter-preserves-original-capf ()
  (let* ((exit #'ignore)
         (capf (list 1 1 '("foo") :exit-function exit)))
    (cl-letf (((symbol-function 'eglot-current-server) (lambda () nil)))
      (let ((wrapped (lsp/completion-command-filter capf)))
        (should (eq (plist-get (cdddr capf) :exit-function) exit))
        (should-not (eq (plist-get (cdddr wrapped) :exit-function) exit)))))
  (should-not (lsp/completion-command-filter nil)))

(defun config-test/resolved-completion (prefetch strip-properties)
  "Check a resolved completion, optionally PREFETCH or STRIP-PROPERTIES."
  (with-temp-buffer
    (setq buffer-file-name "/tmp/emacs-config-test.hs"
          buffer-file-truename buffer-file-name)
    (insert "f")
    (let* ((eglot--capf-session :none)
           (item (list :label "foo" :sortText "1" :data '(:id 1)))
           (command (list :title "Import" :command "extend-import"))
           (resolved (append item (list :command command :detail ":: Int")))
           (resolve-count 0)
           executed)
      (cl-letf (((symbol-function 'eglot-server-capable) (lambda (&rest _) t))
                ((symbol-function 'eglot--current-server-or-lose)
                 (lambda () 'server))
                ((symbol-function 'eglot-current-server) (lambda () 'server))
                ((symbol-function 'jsonrpc-request)
                 (lambda (&rest args)
                   (apply #'lsp/completion-resolve-command
                          (lambda (_server method &rest _args)
                            (pcase method
                              (:textDocument/completion (vector item))
                              (:completionItem/resolve
                               (cl-incf resolve-count)
                               resolved)
                              (_ (error "Unexpected request: %S" method))))
                          args)))
                ((symbol-function 'eglot--signal-textDocument/didChange) #'ignore)
                ((symbol-function 'eglot-execute)
                 (lambda (_server action) (setq executed action))))
        (let* ((capf (eglot-completion-at-point))
               (proxy (car (funcall (nth 2 capf) "" nil t))))
          (when prefetch
            (funcall (plist-get (cdddr capf) :company-docsig) proxy))
          (funcall (plist-get (cdddr capf) :exit-function)
                   (if strip-properties (substring-no-properties proxy) proxy)
                   'finished)
          (should (equal executed command))
          (should (= resolve-count 1)))))))

(ert-deftest config-test/resolved-completion-command-is-not-lost ()
  (config-test/resolved-completion nil nil))

(ert-deftest config-test/cached-resolution-does-not-request-again ()
  (config-test/resolved-completion t nil))

(ert-deftest config-test/resolved-completion-without-properties ()
  (config-test/resolved-completion nil t))

(ert-deftest config-test/unrelated-requests-do-not-modify-params ()
  (let ((params (list :data 1)))
    (lsp/completion-resolve-command
     (lambda (&rest _) '(:command (:command "ignore")))
     'server :textDocument/hover params)
    (should-not (plist-member params :command))))

(ert-deftest config-test/manual-format-respects-apheleia-owner ()
  (with-temp-buffer
    (setq-local format/apheleia-owns t)
    (let (formatter)
      (cl-letf (((symbol-function 'eglot-managed-p) (lambda () t))
                ((symbol-function 'eglot-format)
                 (lambda (&rest _) (interactive) (setq formatter 'eglot)))
                ((symbol-function 'apheleia-format-buffer)
                 (lambda (&rest _) (interactive) (setq formatter 'apheleia))))
        (funcs/format-buffer)
        (should (eq formatter 'apheleia))))))

(ert-deftest config-test/manual-format-falls-back-without-capability ()
  (with-temp-buffer
    (let (formatter)
      (cl-letf (((symbol-function 'eglot-managed-p) (lambda () t))
                ((symbol-function 'eglot-server-capable) (lambda (&rest _) nil))
                ((symbol-function 'apheleia-format-buffer)
                 (lambda (&rest _) (interactive) (setq formatter 'apheleia))))
        (funcs/format-buffer)
        (should (eq formatter 'apheleia))))))

(ert-deftest config-test/manual-format-selects-supported-eglot ()
  (with-temp-buffer
    (let (formatter)
      (cl-letf (((symbol-function 'eglot-managed-p) (lambda () t))
                ((symbol-function 'eglot-server-capable)
                 (lambda (cap) (eq cap :documentFormattingProvider)))
                ((symbol-function 'eglot-format)
                 (lambda (&rest _) (interactive) (setq formatter 'eglot))))
        (funcs/format-buffer)
        (should (eq formatter 'eglot))))))

(ert-deftest config-test/manual-range-falls-back-to-whole-buffer-eglot ()
  (with-temp-buffer
    (insert "example")
    (set-mark (point-min))
    (setq mark-active t)
    (let ((transient-mark-mode t)
          (called 'not-called))
      (cl-letf (((symbol-function 'eglot-managed-p) (lambda () t))
                ((symbol-function 'eglot-server-capable)
                 (lambda (cap) (eq cap :documentFormattingProvider)))
                ((symbol-function 'eglot-format)
                 (lambda (&rest bounds) (interactive) (setq called bounds))))
        (should (region-active-p))
        (funcs/format-buffer)
        (should (null called))))))

(ert-deftest config-test/range-formatting-has-its-own-capability ()
  (with-temp-buffer
    (cl-letf (((symbol-function 'eglot-managed-p) (lambda () t))
              ((symbol-function 'eglot-server-capable)
               (lambda (cap) (eq cap :documentRangeFormattingProvider))))
      (should (format/eglot-owns-p t))
      (should-not (format/eglot-owns-p)))))

(ert-deftest config-test/ignored-formatting-capability-falls-back ()
  (with-temp-buffer
    (let ((eglot-ignored-server-capabilities '(:documentFormattingProvider)))
      (cl-letf (((symbol-function 'eglot-managed-p) (lambda () t))
                ((symbol-function 'eglot--current-server-or-lose)
                 (lambda () 'server))
                ((symbol-function 'eglot--capabilities)
                 (lambda (_server) '(:documentFormattingProvider t))))
        (should-not (format/eglot-owns-p))))))

(ert-deftest config-test/literate-haskell-inherits-formatting-and-lsp ()
  (config-test/with-directory
    (with-temp-buffer
      (let (started)
        (cl-letf (((symbol-function 'eglot-ensure)
                   (lambda () (setq started t))))
          (haskell-literate-mode)
          (should (eq major-mode 'haskell-literate-mode))
          (should started)
          (should format/apheleia-owns)
          (should apheleia-mode)
          (should (equal (car (funcall (alist-get major-mode eglot-server-programs)))
                         "haskell-language-server-wrapper"))
          (should (eq (alist-get major-mode apheleia-mode-alist) 'ormolu)))))))

(ert-deftest config-test/save-formatting-honors-apheleia-owner ()
  (with-temp-buffer
    (setq-local format/apheleia-owns t
                before-save-hook (list #'eglot-format))
    (let (fallback)
      (cl-letf (((symbol-function 'eglot-managed-p) (lambda () t))
                ((symbol-function 'format/mode-maybe)
                 (lambda () (setq fallback t))))
        (lsp/format-on-save)
        (should fallback)
        (should-not (memq #'eglot-format before-save-hook))))))

(ert-deftest config-test/save-formatting-checks-server-capability ()
  (with-temp-buffer
    (setq-local before-save-hook nil)
    (let (fallback)
      (cl-letf (((symbol-function 'eglot-managed-p) (lambda () t))
                ((symbol-function 'eglot-server-capable) (lambda (&rest _) nil))
                ((symbol-function 'format/mode-maybe)
                 (lambda () (setq fallback t))))
        (lsp/format-on-save)
        (should fallback)
        (should-not (memq #'eglot-format before-save-hook))))))

(ert-deftest config-test/save-formatting-enables-only-one-owner ()
  (with-temp-buffer
    (setq-local before-save-hook nil)
    (apheleia-mode 1)
    (cl-letf (((symbol-function 'eglot-managed-p) (lambda () t))
              ((symbol-function 'eglot-server-capable) (lambda (&rest _) t)))
      (lsp/format-on-save)
      (should (memq #'eglot-format before-save-hook))
      (should-not apheleia-mode)
      (should-not (memq #'apheleia-format-after-save after-save-hook)))))

(ert-deftest config-test/disconnecting-eglot-restores-apheleia ()
  (with-temp-buffer
    (setq-local before-save-hook (list #'eglot-format))
    (cl-letf (((symbol-function 'eglot-managed-p) (lambda () nil)))
      (lsp/format-on-save)
      (should-not (memq #'eglot-format before-save-hook))
      (should apheleia-mode))))

(ert-deftest config-test/project-finder-preserves-git-and-ignores ()
  (config-test/with-directory
    (should (zerop (call-process "git" nil nil nil "init" "--quiet" root)))
    (config-test/file root "package.json" "{}")
    (config-test/file root ".gitignore" "ignored.txt\n")
    (config-test/file root "kept.txt")
    (config-test/file root "ignored.txt")
    (let ((project (project-current nil root)))
      (should (eq (car project) 'vc))
      (should (eq (cadr project) 'Git))
      (should (member (expand-file-name "kept.txt" root) (project-files project)))
      (should-not (member (expand-file-name "ignored.txt" root)
                          (project-files project))))))

(ert-deftest config-test/project-finder-prefers-nearer-haskell-cradle ()
  (config-test/with-directory
    (config-test/file root "package.json" "{}")
    (config-test/file root "haskell/hie.yaml" "cradle: {}")
    (make-directory (expand-file-name "haskell/src/" root))
    (let ((project (project-current nil (expand-file-name "haskell/src/" root))))
      (should (equal (project-root project) (expand-file-name "haskell/" root)))
      (should (eq (car project) 'vc)))))

(ert-deftest config-test/project-finder-prefers-nearer-javascript-manifest ()
  (config-test/with-directory
    (config-test/file root "stack.yaml")
    (config-test/file root "web/package.json" "{}")
    (make-directory (expand-file-name "web/src/" root))
    (should (equal
             (project-root (project-current nil (expand-file-name "web/src/" root)))
             (expand-file-name "web/" root)))))

(ert-deftest config-test/nested-manifest-keeps-git-backend ()
  (config-test/with-directory
    (should (zerop (call-process "git" nil nil nil "init" "--quiet" root)))
    (config-test/file root "web/package.json" "{}")
    (let ((project (project-current nil (expand-file-name "web/" root))))
      (should (equal (project-root project) (expand-file-name "web/" root)))
      (should (eq (cadr project) 'Git)))))

(ert-deftest config-test/project-finder-matches-dotted-cabal-file ()
  (config-test/with-directory
    (config-test/file root "example.test.cabal")
    (make-directory (expand-file-name "src/" root))
    (should (equal (project-root
                    (project-current nil (expand-file-name "src/" root)))
                   root))))

(ert-deftest config-test/javascript-selects-nearest-manifest ()
  (config-test/with-directory
    (config-test/file root "deno.json" "{}")
    (config-test/file root "inner/package.json" "{}")
    (make-directory (expand-file-name "inner/src/" root))
    (should (equal
             (javascript--marker-root (expand-file-name "inner/src/" root))
             (expand-file-name "inner/" root)))))

(ert-deftest config-test/lockfiles-do-not-create-projects ()
  (config-test/with-directory
    (config-test/file root "bun.lock")
    (let ((locate-dominating-stop-dir-regexp
           (concat "\\`" (regexp-quote root) "\\'")))
      (should-not (javascript--marker-root root))
      (should-not (project-current nil root)))))

(ert-deftest config-test/javascript-tools-use-javascript-manifest ()
  (config-test/with-directory
    (config-test/file root "package.json" "{}")
    (config-test/file root "haskell/hie.yaml")
    (let ((default-directory (expand-file-name "haskell/" root)))
      (should (equal (javascript/project-root) root)))))

(ert-deftest config-test/navigation-bindings-are-reachable ()
  (should (eq (key-binding (kbd "C-c i")) 'consult-info))
  (should (eq (key-binding (kbd "M-g i")) 'consult-imenu))
  (should-not (key-binding (kbd "C-c i m"))))

(ert-deftest config-test/stale-check-includes-local-packages ()
  (config-test/with-directory
    (let* ((user-emacs-directory root)
           (custom-file (expand-file-name "custom.el" root))
           (old (seconds-to-time 1000000000))
           (new (seconds-to-time 1100000000)))
      (set-file-times (config-test/file root "init.el") old)
      (set-file-times (config-test/file root "pkgs/example.el") new)
      (set-file-times (config-test/file root "custom.el") (current-time))
      (set-file-times (config-test/file root "tests/fixture.el") (current-time))
      (should (equal (emc/config-newest-mtime) new)))))

(ert-deftest config-test/stale-check-includes-modules-without-custom-file ()
  (config-test/with-directory
    (let* ((user-emacs-directory root)
           (custom-file nil)
           (old (seconds-to-time 1000000000))
           (new (seconds-to-time 1100000000)))
      (set-file-times (config-test/file root "init.el") old)
      (set-file-times (config-test/file root "modules/example.el") new)
      (should (equal (emc/config-newest-mtime) new)))))

(ert-deftest config-test/trust-excludes-shared-tmp-and-downloads ()
  (dolist (file (list (expand-file-name "config-test.el" temporary-file-directory)
                      (expand-file-name "Downloads/config-test.el" "~/")))
    (with-temp-buffer
      (setq buffer-file-name file
            buffer-file-truename file)
      (should-not (trusted-content-p)))))

(ert-deftest config-test/trust-includes-development-and-config ()
  (dolist (file (list (expand-file-name "git/config-test.el" "~/")
                      (expand-file-name "init.el" user-emacs-directory)))
    (with-temp-buffer
      (setq buffer-file-name file
            buffer-file-truename file)
      (should (trusted-content-p)))))

(provide 'configuration-tests)
;;; configuration-tests.el ends here
