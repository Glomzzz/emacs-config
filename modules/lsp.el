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
  :custom
  (eglot-autoshutdown t)
  :config
  (add-to-list 'eglot-server-programs '(scheme-mode . ("scheme-langserver")))
  (add-to-list 'eglot-server-programs '(nix-ts-mode . ("nixd"))))

(use-package treesit-auto
  :hook (after-init . global-treesit-auto-mode)
  :custom
  (treesit-auto-install 'prompt)
  :init
  (setq treesit-language-source-alist
        '((java "https://github.com/tree-sitter/tree-sitter-java")
          (python "https://github.com/tree-sitter/tree-sitter-python")
          (rust "https://github.com/tree-sitter/tree-sitter-rust")
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
