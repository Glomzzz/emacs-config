;;; lsp.el --- Shared LSP, diagnostics, and Eldoc behavior -*- lexical-binding: t; -*-

(defun my/treesit-install-dir (out-dir)
  "Normalize tree-sitter grammar install OUT-DIR into the cache directory."
  (let ((default-dir
         (file-name-as-directory
          (expand-file-name "tree-sitter/" user-emacs-directory))))
    (if (or (null out-dir)
            (string-equal (file-name-as-directory (expand-file-name out-dir))
                          default-dir))
        my/emacs-tree-sitter-dir
      out-dir)))

(defun my/treesit-install-language-grammar-to-cache (orig lang &optional out-dir)
  "Install LANG grammar with ORIG into the cache-backed OUT-DIR."
  (funcall orig lang (my/treesit-install-dir out-dir)))

(defun my/treesit-install-language-grammar-async (lang &optional out-dir)
  "Install the LANG grammar in a background Emacs process."
  (interactive
   (list (intern
          (completing-read
           "Language: " (mapcar #'car treesit-language-source-alist)))
         'interactive))
  (require 'async)
  (let* ((destination
          (my/treesit-install-dir
           (unless (eq out-dir 'interactive) out-dir)))
         (recipe (assq lang treesit-language-source-alist)))
    (unless recipe
      (user-error "No tree-sitter recipe for %s" lang))
    (message "Installing the %s grammar in the background..." lang)
    (async-start
     `(lambda ()
        (require 'treesit)
        (setq treesit-language-source-alist ',treesit-language-source-alist)
        (condition-case error-data
            (progn
              (treesit-install-language-grammar ',lang ,destination)
              (list t ',lang))
          (error (list nil ',lang (error-message-string error-data)))))
     (lambda (result)
       (pcase result
         (`(t ,language)
          (message "Installed the %s grammar; reopen its buffers" language))
         (`(nil ,language ,details)
          (message "Could not install the %s grammar: %s" language details)))))))

(defun my/enable-treesit-cache-installs ()
  "Keep tree-sitter grammar installs under `.cache/tree-sitter/'."
  (unless (advice-member-p #'my/treesit-install-language-grammar-to-cache
                           #'treesit-install-language-grammar)
    (advice-add #'treesit-install-language-grammar
                :around
                #'my/treesit-install-language-grammar-to-cache)))

(if (fboundp 'treesit-install-language-grammar)
    (my/enable-treesit-cache-installs)
  (with-eval-after-load 'treesit
    (my/enable-treesit-cache-installs)))

(global-set-key (kbd "C-c T") #'my/treesit-install-language-grammar-async)

(connection-local-set-profile-variables
 'my/tramp-direct-async
 '((tramp-direct-async-process . t)))
(dolist (protocol '("rsync" "scp" "ssh"))
  (connection-local-set-profiles
   `(:application tramp :protocol ,protocol)
   'my/tramp-direct-async))

(defun my/flymake-setup ()
  "Use jump commands instead of inline end-of-line diagnostics."
  (setq-local flymake-show-diagnostics-at-end-of-line nil))

(defun my/lsp-buffer-setup ()
  "Set shared local bindings and diagnostics behavior for LSP buffers."
  (my/flymake-setup)
  (local-set-key (kbd "C-c =") #'eglot-format-buffer)
  (local-set-key (kbd "C-c a") #'eglot-code-actions)
  (local-set-key (kbd "C-c d") #'eldoc-doc-buffer)
  (local-set-key (kbd "M-n") #'flymake-goto-next-error)
  (local-set-key (kbd "M-p") #'flymake-goto-prev-error))

(defun my/eglot-managed-mode-setup ()
  "Apply shared LSP helpers when Eglot starts managing a buffer."
  (my/lsp-buffer-setup))

(defvar-local my/eglot-start-timer nil)

(defun my/eglot-ensure-idle ()
  "Start or join the project Eglot server once Emacs becomes idle."
  (when (timerp my/eglot-start-timer)
    (cancel-timer my/eglot-start-timer))
  (setq my/eglot-start-timer
        (run-with-idle-timer
         0.15 nil
         (lambda (buffer)
           (when (buffer-live-p buffer)
             (with-current-buffer buffer
               (setq my/eglot-start-timer nil)
               (unless (or (minibufferp) (file-remote-p default-directory))
                 (condition-case error-data
                     (eglot-ensure)
                   (error
                    (message "Eglot did not start: %s"
                             (error-message-string error-data))))))))
         (current-buffer))))

(defun my/enable-eldoc-box ()
  "Show ElDoc in an at-point childframe when the display supports it."
  (eldoc-box-hover-at-point-mode
   (if (and eldoc-mode (display-graphic-p)) 1 -1)))

(use-package eglot
  :ensure nil
  :commands (eglot eglot-ensure eglot-rename)
  :bind ("C-c r" . eglot-rename)
  :hook (eglot-managed-mode . my/eglot-managed-mode-setup)
  :init
  (setq eglot-autoshutdown nil
        eglot-sync-connect 0
        eglot-send-changes-idle-time 0.25
        eglot-events-buffer-config '(:size 0 :format short)
        eglot-report-progress nil)
  (setq-default
   eglot-workspace-configuration
   '(:rust-analyzer
     (:inlayHints
      (:typeHints (:enable :json-false)))
     :koka
     (:languageServer
      (:inlayHints
       (:showImplicitArguments t
        :showInferredTypes t
        :showFullQualifiers :json-false)))))
  :config
  (add-to-list 'eglot-server-programs '(scheme-mode . ("scheme-langserver")))
  (add-to-list 'eglot-server-programs '(nix-ts-mode . ("nixd"))))

(use-package treesit-auto
  :hook (after-init . global-treesit-auto-mode)
  :custom
  (treesit-auto-install nil)
  :init
  (setq treesit-language-source-alist
        '((flix "https://github.com/wstein/tree-sitter-flix" "v0.1.1")
          (java "https://github.com/tree-sitter/tree-sitter-java")
          (javascript "https://github.com/tree-sitter/tree-sitter-javascript"
                      nil "src")
          (json "https://github.com/tree-sitter/tree-sitter-json")
          (kotlin "https://github.com/fwcd/tree-sitter-kotlin")
          (python "https://github.com/tree-sitter/tree-sitter-python")
          (rust "https://github.com/tree-sitter/tree-sitter-rust")
          (tsx "https://github.com/tree-sitter/tree-sitter-typescript"
               nil "tsx/src")
          (typescript "https://github.com/tree-sitter/tree-sitter-typescript"
                      nil "typescript/src")
          (typst "https://github.com/uben0/tree-sitter-typst")))
  :config
  (treesit-auto-add-to-auto-mode-alist))

(use-package eldoc
  :ensure nil
  :hook (prog-mode . eldoc-mode)
  :custom
  ;; At-point eldoc-box suppresses popups for 0.5 seconds after point moves.
  (eldoc-idle-delay 0.6)
  (eldoc-echo-area-use-multiline-p nil))

(use-package eldoc-box
  :hook (eldoc-mode . my/enable-eldoc-box)
  :custom
  (eldoc-box-clear-with-C-g t)
  (eldoc-box-max-pixel-width 800)
  (eldoc-box-max-pixel-height 400))
