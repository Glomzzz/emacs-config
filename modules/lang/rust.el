;;; rust.el --- Rust mode detection, project roots, and Eglot integration -*- lexical-binding: t; -*-

(defun my/rust-project (dir)
  "Treat the nearest directory containing Cargo.toml as a Rust project root."
  (when (derived-mode-p 'rust-mode 'rust-ts-mode)
    (when-let ((root (locate-dominating-file dir "Cargo.toml")))
      (cons 'transient
            (file-name-as-directory (expand-file-name root))))))

(defun my/rust-use-ts-mode-p ()
  "Return non-nil when `rust-ts-mode' is ready for use."
  (and (require 'treesit nil t)
       (fboundp 'rust-ts-mode)
       (treesit-language-available-p 'rust)))

(defun my/rust-major-mode ()
  "Open Rust files in `rust-mode', deriving from `rust-ts-mode' when ready."
  (interactive)
  (require 'rust-mode)
  (when (my/rust-use-ts-mode-p)
    (require 'rust-mode-treesitter nil t))
  (rust-mode))

(defun my/rust-rustup-stable-analyzer ()
  "Return the stable-toolchain `rust-analyzer' binary when available."
  (when-let ((rustup (executable-find "rustup"))
             (binary (car-safe
                      (ignore-errors
                        (process-lines rustup
                                       "which"
                                       "--toolchain"
                                       "stable"
                                       "rust-analyzer")))))
    (and (file-executable-p binary) binary)))

(defun my/rust-analyzer-proxy-p (path)
  "Return non-nil when PATH resolves to a rustup proxy."
  (when-let ((truename (ignore-errors (file-truename path))))
    (string-match-p "/rustup[^/]*/bin/rust-analyzer\\'" truename)))

(defun my/rust-direct-analyzer ()
  "Return the first non-proxy `rust-analyzer' found on `exec-path'."
  (cl-loop for dir in exec-path
           for candidate = (expand-file-name "rust-analyzer" dir)
           when (and (file-executable-p candidate)
                     (not (my/rust-analyzer-proxy-p candidate)))
           return candidate))

(defun my/rust-eglot-command (&optional _interactive _project)
  "Return a working `rust-analyzer' command for Eglot."
  ;; Prefer a real analyzer binary over the rustup proxy so project-local
  ;; toolchain overrides (such as `channel = \"esp\"`) do not recurse forever.
  (when-let ((binary (or (my/rust-rustup-stable-analyzer)
                         (my/rust-direct-analyzer)
                         (executable-find "rust-analyzer"))))
    (list binary)))

(defun my/rust-lsp-server-available-p ()
  "Return non-nil when a supported Rust language server is installed."
  (my/rust-eglot-command))

(defun my/rust-maybe-eglot-ensure ()
  "Start Eglot only when `rust-analyzer' is available."
  (when (my/rust-lsp-server-available-p)
    (eglot-ensure)))

(defun my/register-rust-auto-mode ()
  "Ensure `.rs` files always open in `rust-mode'."
  (setq auto-mode-alist
        (cl-remove-if
         (lambda (entry)
           (and (stringp (car entry))
                (string= (car entry) "\\.rs\\'")))
         auto-mode-alist))
  (add-to-list 'auto-mode-alist '("\\.rs\\'" . my/rust-major-mode)))

(my/register-rust-auto-mode)
(add-hook 'project-find-functions #'my/rust-project)
(add-hook 'rust-mode-hook #'my/rust-maybe-eglot-ensure)
(add-hook 'rust-ts-mode-hook #'my/rust-maybe-eglot-ensure)

(with-eval-after-load 'rust-mode
  (my/register-rust-auto-mode))

(with-eval-after-load 'rust-ts-mode
  (my/register-rust-auto-mode))

(with-eval-after-load 'eglot
  (add-to-list 'eglot-server-programs
               (cons 'rust-mode #'my/rust-eglot-command))
  (add-to-list 'eglot-server-programs
               (cons 'rust-ts-mode #'my/rust-eglot-command)))
