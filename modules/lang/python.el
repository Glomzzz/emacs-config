;;; python.el --- Python mode detection, project roots, and Eglot integration -*- lexical-binding: t; -*-

(defun my/python-local-project (dir)
  "Treat Python buffers as transient projects rooted at the nearest marker.
When no project marker exists, fall back to DIR so standalone files still
work with project-aware tools such as Eglot."
  (when (derived-mode-p 'python-base-mode)
    (cons 'transient
          (or (locate-dominating-file dir "pyproject.toml")
              (locate-dominating-file dir "uv.lock")
              (locate-dominating-file dir "setup.py")
              (locate-dominating-file dir "setup.cfg")
              (locate-dominating-file dir "requirements.txt")
              (file-name-as-directory (expand-file-name dir))))))

(defun my/python-eglot-command ()
  "Pick an available Python language server without downloading on startup."
  (eglot-alternatives
   '(("basedpyright-langserver" "--stdio")
     ("pyright-langserver" "--stdio")
     ("pylsp")
     ("jedi-language-server"))))

(defun my/python-use-ts-mode-p ()
  "Return non-nil when `python-ts-mode' is ready for use."
  (and (require 'treesit nil t)
       (fboundp 'python-ts-mode)
       (treesit-ready-p 'python)))

(defun my/python-lsp-server-available-p ()
  "Return non-nil when a supported Python language server is installed."
  (or (executable-find "basedpyright-langserver")
      (executable-find "pyright-langserver")
      (executable-find "pylsp")
      (executable-find "jedi-language-server")))

(defun my/python-maybe-eglot-ensure ()
  "Start Eglot only when a supported Python language server is available."
  (when (my/python-lsp-server-available-p)
    (eglot-ensure)))

(defun my/python-major-mode ()
  "Open Python files with the best available major mode."
  (interactive)
  (cond
   ((my/python-use-ts-mode-p)
    (python-ts-mode))
   ((fboundp 'python-mode)
    (python-mode))
   (t
    (fundamental-mode))))

(defun my/register-python-auto-mode ()
  "Ensure Python files prefer `python-ts-mode' when available."
  (setq auto-mode-alist
        (cl-remove-if
         (lambda (entry)
           (and (stringp (car entry))
                (member (car entry)
                        '("\\.py\\'"
                          "\\.pyi\\'"
                          "\\.pyw\\'"
                          "SConstruct\\'"
                          "SConscript\\'"))))
         auto-mode-alist))
  (let ((mode (if (my/python-use-ts-mode-p)
                  'python-ts-mode
                'my/python-major-mode)))
    (dolist (pattern '("\\.py\\'"
                       "\\.pyi\\'"
                       "\\.pyw\\'"
                       "SConstruct\\'"
                       "SConscript\\'"))
      (add-to-list 'auto-mode-alist `(,pattern . ,mode)))))

(defun my/register-python-mode-remap ()
  "Remap `python-mode' to `python-ts-mode' when tree-sitter is ready."
  (setq major-mode-remap-alist
        (assq-delete-all 'python-mode major-mode-remap-alist))
  (when (my/python-use-ts-mode-p)
    (add-to-list 'major-mode-remap-alist
                 '(python-mode . python-ts-mode))))

(my/register-python-auto-mode)
(my/register-python-mode-remap)
(add-hook 'project-find-functions #'my/python-local-project)
(add-hook 'python-base-mode-hook #'my/python-maybe-eglot-ensure)

(with-eval-after-load 'python
  (my/register-python-auto-mode)
  (my/register-python-mode-remap)
  (setq python-indent-guess-indent-offset nil
        python-indent-guess-indent-offset-verbose nil))

(with-eval-after-load 'eglot
  (add-to-list 'eglot-server-programs
               `(python-mode . ,(my/python-eglot-command)))
  (add-to-list 'eglot-server-programs
               `(python-ts-mode . ,(my/python-eglot-command))))
