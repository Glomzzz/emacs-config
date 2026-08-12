;;; flix.el --- Flix projects, commands, and Eglot integration -*- lexical-binding: t; -*-

(require 'project)
(require 'seq)

(defvar eglot-server-programs)
(declare-function eglot-ensure "eglot" ())
(declare-function eglot-uri-to-path "eglot" (uri))
(declare-function eglot-workspace-folders "eglot" (server))
(defvar treesit-auto-langs)
(defvar treesit-auto-recipe-list)
(defvar global-treesit-auto-modes)
(declare-function make-treesit-auto-recipe "treesit-auto" (&rest slots))
(declare-function treesit-auto-add-to-auto-mode-alist "treesit-auto"
                  (&optional langs))
(declare-function treesit-auto-recipe-lang "treesit-auto" (recipe))

(defconst my/flix-project-markers
  '("flix.toml" "flix.jar" ".git" ".hg")
  "Files and directories that identify a Flix project root.")

(defun my/flix-source-mode-p ()
  "Return non-nil when the current buffer contains Flix source code."
  (derived-mode-p 'flix-mode))

(defun my/flix-project-root (dir)
  "Find the nearest Flix project root above DIR, or return DIR."
  (file-name-as-directory
   (expand-file-name
    (or (locate-dominating-file
         dir
         (lambda (candidate)
           (seq-some
            (lambda (marker)
              (file-exists-p (expand-file-name marker candidate)))
            my/flix-project-markers)))
        dir))))

(defun my/flix-project (dir)
  "Return a transient Flix project rooted above DIR."
  (when (my/flix-source-mode-p)
    (cons 'transient (my/flix-project-root dir))))

(defun my/flix-local-jar (&optional dir)
  "Return the nearest project-local flix.jar above DIR."
  (when-let* ((root (locate-dominating-file
                     (or dir default-directory) "flix.jar")))
    (expand-file-name "flix.jar" root)))

(defun my/flix-command-prefix (&optional dir)
  "Return the preferred Flix command prefix for DIR."
  (let ((java (executable-find "java"))
        (jar (my/flix-local-jar dir))
        (flix (executable-find "flix")))
    (cond
     ((and java jar) (list java "-jar" jar))
     (flix (list flix)))))

(defun my/flix-eglot-contact (_interactive project)
  "Return a Flix LSP contact for PROJECT, or nil when unavailable."
  (when-let* ((root (and project (project-root project)))
              (prefix (my/flix-command-prefix root)))
    (cons 'my/flix-eglot-server (append prefix '("lsp")))))

(defun my/flix-maybe-eglot-ensure ()
  "Start Eglot when the Flix compiler is available."
  (when (my/flix-command-prefix)
    (eglot-ensure)))

(defun my/flix-shell-command (arguments)
  "Quote and join Flix command ARGUMENTS for the shell."
  (mapconcat #'shell-quote-argument arguments " "))

(defun my/flix-buffer-setup ()
  "Set Flix indentation and compilation defaults."
  (setq-local indent-tabs-mode nil)
  (when (boundp 'flix-indent-offset)
    (setq-local flix-indent-offset 4))
  (when-let* ((prefix (my/flix-command-prefix)))
    (let* ((root (my/flix-project-root default-directory))
           (project-p (file-exists-p (expand-file-name "flix.toml" root)))
           (arguments (append prefix
                              (if project-p
                                  '("check")
                                (and buffer-file-name
                                     (list buffer-file-name))))))
      (when (> (length arguments) (length prefix))
        (setq-local compile-command
                    (my/command-in-directory
                     root (my/flix-shell-command arguments)))))))

(defun my/flix-absolute-workspace-folders (folders)
  "Replace display names in FOLDERS with absolute filesystem paths."
  (vconcat
   (mapcar
    (lambda (folder)
      (let ((copy (copy-sequence folder)))
        (plist-put copy :name
                   (file-local-name
                    (expand-file-name
                     (eglot-uri-to-path (plist-get copy :uri)))))))
    folders)))

(add-to-list 'auto-mode-alist '("\\.flix\\'" . flix-mode))
(add-hook 'project-find-functions #'my/flix-project)
(add-hook 'flix-mode-hook #'my/flix-buffer-setup)
(add-hook 'flix-mode-hook #'my/flix-maybe-eglot-ensure)

(with-eval-after-load 'treesit-auto
  (unless (seq-some
           (lambda (recipe)
             (eq (treesit-auto-recipe-lang recipe) 'flix))
           treesit-auto-recipe-list)
    (add-to-list
     'treesit-auto-recipe-list
     (make-treesit-auto-recipe
      :lang 'flix
      :ts-mode 'flix-ts-mode
      :remap 'flix-mode
      :url "https://github.com/wstein/tree-sitter-flix"
      :revision "v0.1.1"
      :ext "\\.flix\\'")))
  (add-to-list 'treesit-auto-langs 'flix)
  (add-to-list 'global-treesit-auto-modes 'flix-mode)
  (add-to-list 'global-treesit-auto-modes 'flix-ts-mode)
  (treesit-auto-add-to-auto-mode-alist))

(with-eval-after-load 'eglot
  (defclass my/flix-eglot-server (eglot-lsp-server) ()
    :documentation "Eglot connection for the Flix language server.")

  ;; Flix 0.75.1 reads WorkspaceFolder.name as a path.  Eglot normally uses
  ;; an abbreviated display name there, so provide the absolute path instead.
  (cl-defmethod eglot-workspace-folders ((_server my/flix-eglot-server))
    (my/flix-absolute-workspace-folders (cl-call-next-method)))

  (add-to-list
   'eglot-server-programs
   '(((flix-mode :language-id "flix")
      (flix-ts-mode :language-id "flix"))
     . my/flix-eglot-contact)))

;;; flix.el ends here
