;;; javascript.el --- JavaScript, TypeScript, JSON, and Eglot -*- lexical-binding: t; -*-

(require 'cl-lib)
(require 'json)
(require 'project)
(require 'seq)
(require 'subr-x)

(defvar eglot-server-programs)
(defvar flymake-eslint-executable-name)
(defvar flymake-eslint-project-root)
(declare-function apheleia-format-buffer "apheleia" (formatter &optional callback))
(declare-function eglot-ensure "eglot" ())
(declare-function eglot-format-buffer "eglot" ())
(declare-function eglot-managed-p "eglot" ())
(declare-function flymake-eslint-enable "flymake-eslint" ())

(defconst my/javascript-workspace-markers
  '("deno.json" "deno.jsonc" "pnpm-workspace.yaml" "lerna.json"
    "nx.json" "turbo.json" "package-lock.json" "pnpm-lock.yaml"
    "yarn.lock" "bun.lock" "bun.lockb")
  "Files that identify a JavaScript workspace root.")

(defconst my/javascript-module-markers
  '("package.json" "tsconfig.json" "jsconfig.json" "biome.json"
    "biome.jsonc")
  "Files that identify a JavaScript project or module root.")

(defconst my/javascript-vc-markers '(".git" ".hg")
  "Version-control markers used as a JavaScript project fallback.")

(defconst my/javascript-eslint-markers
  '("eslint.config.js" "eslint.config.mjs" "eslint.config.cjs"
    "eslint.config.ts" "eslint.config.mts" "eslint.config.cts"
    ".eslintrc" ".eslintrc.js" ".eslintrc.cjs" ".eslintrc.json"
    ".eslintrc.yaml" ".eslintrc.yml")
  "Files that identify an ESLint configuration root.")

(defconst my/javascript-auto-mode-entries
  '(("\\.\\(?:[cm]?js\\|jsx\\)\\'" . my/javascript-major-mode)
    ("\\.\\(?:[cm]?ts\\|tsx\\)\\'" . my/typescript-major-mode)
    ("\\.jsonc?\\'" . my/json-major-mode))
  "File patterns handled by the JavaScript module.")

(use-package apheleia
  :commands apheleia-format-buffer)

(use-package flymake-eslint
  :commands flymake-eslint-enable
  :custom
  (flymake-eslint-prefer-json-diagnostics t))

(use-package typescript-mode
  :commands typescript-mode
  :custom
  (typescript-indent-level 2))

(defun my/javascript-code-mode-p ()
  "Return non-nil for a JavaScript or TypeScript source buffer."
  (derived-mode-p 'js-base-mode 'typescript-mode
                  'typescript-ts-base-mode 'typescript-ts-mode 'tsx-ts-mode))

(defun my/javascript-project-mode-p ()
  "Return non-nil when the current mode belongs to the JavaScript ecosystem."
  (or (my/javascript-code-mode-p)
      (derived-mode-p 'js-json-mode 'json-mode 'json-ts-mode)))

(defun my/javascript-root-with-markers (dir markers)
  "Find the nearest directory above DIR containing one of MARKERS."
  (locate-dominating-file
   dir
   (lambda (candidate)
     (seq-some
      (lambda (marker)
        (file-exists-p (expand-file-name marker candidate)))
      markers))))

(defun my/javascript-project-root (dir)
  "Find the JavaScript project root above DIR, or return DIR."
  (file-name-as-directory
   (expand-file-name
    (or (my/javascript-root-with-markers
         dir my/javascript-workspace-markers)
        (my/javascript-root-with-markers dir my/javascript-module-markers)
        (my/javascript-root-with-markers dir my/javascript-vc-markers)
        dir))))

(defun my/javascript-project (dir)
  "Return a transient JavaScript project rooted above DIR."
  (when (my/javascript-project-mode-p)
    (cons 'transient (my/javascript-project-root dir))))

(defun my/javascript-deno-project-p (root)
  "Return non-nil when ROOT is configured as a Deno project."
  (or (file-exists-p (expand-file-name "deno.json" root))
      (file-exists-p (expand-file-name "deno.jsonc" root))))

(defun my/javascript-file-extension ()
  "Return the current buffer's lowercase file extension."
  (downcase
   (or (file-name-extension (or buffer-file-name (buffer-name))) "")))

(defun my/javascript-treesit-ready-p (language mode)
  "Return non-nil when tree-sitter LANGUAGE and MODE are ready."
  (and (require 'treesit nil t)
       (fboundp mode)
       (treesit-ready-p language t)))

(defun my/javascript-major-mode ()
  "Open JavaScript files with the best available major mode."
  (interactive)
  (cond
   ((my/javascript-treesit-ready-p 'javascript 'js-ts-mode)
    (js-ts-mode))
   ((and (string-equal (my/javascript-file-extension) "jsx")
         (fboundp 'js-jsx-mode))
    (js-jsx-mode))
   ((fboundp 'js-mode)
    (js-mode))
   (t
    (fundamental-mode))))

(defun my/typescript-major-mode ()
  "Open TypeScript files with tree-sitter, falling back gracefully."
  (interactive)
  (let ((tsx-p (string-equal (my/javascript-file-extension) "tsx")))
    (cond
     ((and tsx-p (my/javascript-treesit-ready-p 'tsx 'tsx-ts-mode))
      (tsx-ts-mode))
     ((and (not tsx-p)
           (my/javascript-treesit-ready-p
            'typescript 'typescript-ts-mode))
      (typescript-ts-mode))
     ((require 'typescript-mode nil t)
      (typescript-mode))
     ((fboundp 'js-mode)
      (js-mode))
     (t
      (fundamental-mode)))))

(defun my/json-major-mode ()
  "Open JSON and JSONC files with the best available major mode."
  (interactive)
  (cond
   ((my/javascript-treesit-ready-p 'json 'json-ts-mode)
    (json-ts-mode))
   ((fboundp 'js-json-mode)
    (js-json-mode))
   (t
    (fundamental-mode))))

(defun my/register-javascript-auto-modes ()
  "Register modern JavaScript, TypeScript, and JSON file names."
  (let ((patterns (mapcar #'car my/javascript-auto-mode-entries)))
    (setq auto-mode-alist
          (cl-remove-if
           (lambda (entry)
             (and (stringp (car entry))
                  (member (car entry) patterns)))
           auto-mode-alist)))
  (dolist (entry (reverse my/javascript-auto-mode-entries))
    (push entry auto-mode-alist))
  (setq interpreter-mode-alist
        (cl-remove-if
         (lambda (entry)
           (member (car entry) '("node" "nodejs" "bun" "deno")))
         interpreter-mode-alist))
  (dolist (interpreter '("deno" "bun" "nodejs" "node"))
    (push (cons interpreter 'my/javascript-major-mode)
          interpreter-mode-alist)))

(defun my/javascript-local-bin-dir (&optional dir)
  "Find the nearest node_modules/.bin directory above DIR."
  (when-let ((root (locate-dominating-file
                    (or dir default-directory) "node_modules/.bin")))
    (expand-file-name "node_modules/.bin" root)))

(defun my/javascript-local-executable (program &optional dir)
  "Find PROGRAM in a project-local node_modules/.bin above DIR."
  (when-let* ((bin-dir (my/javascript-local-bin-dir dir))
              (candidate (expand-file-name program bin-dir))
              ((file-executable-p candidate)))
    candidate))

(defun my/javascript-find-executable (program &optional dir)
  "Find project-local or global PROGRAM, searching upward from DIR."
  (or (my/javascript-local-executable program dir)
      (executable-find program)))

(defun my/javascript-add-node-modules-path ()
  "Expose the nearest node_modules/.bin to this buffer's subprocesses."
  (when-let ((bin-dir (my/javascript-local-bin-dir)))
    (setq-local exec-path
                (cons bin-dir (delete bin-dir (copy-sequence exec-path))))
    (setq-local process-environment (copy-sequence process-environment))
    (let* ((path (or (getenv "PATH") ""))
           (entries (delete bin-dir
                            (split-string path path-separator t))))
      (setenv "PATH"
              (mapconcat #'identity (cons bin-dir entries)
                         path-separator)))))

(defun my/javascript-read-json-file (file)
  "Parse FILE as JSON into hash tables, returning nil on invalid input."
  (when (file-readable-p file)
    (condition-case nil
        (with-temp-buffer
          (insert-file-contents file)
          (json-parse-buffer :object-type 'hash-table
                             :array-type 'list
                             :null-object nil
                             :false-object nil))
      (error nil))))

(defun my/javascript-package-script (root)
  "Return the preferred package script declared below ROOT."
  (when-let* ((manifest
               (my/javascript-read-json-file
                (expand-file-name "package.json" root)))
              ((hash-table-p manifest))
              (scripts (gethash "scripts" manifest))
              ((hash-table-p scripts)))
    (seq-find
     (lambda (script)
       (stringp (gethash script scripts)))
     '("test" "check" "typecheck" "build"))))

(defun my/javascript-package-manager (root)
  "Return an available package manager appropriate for ROOT."
  (let ((preferred
         (cond
          ((or (file-exists-p (expand-file-name "bun.lock" root))
               (file-exists-p (expand-file-name "bun.lockb" root)))
           "bun")
          ((file-exists-p (expand-file-name "pnpm-lock.yaml" root))
           "pnpm")
          ((file-exists-p (expand-file-name "yarn.lock" root))
           "yarn")
          (t "npm"))))
    (seq-find #'executable-find
              (delete-dups
               (list preferred "npm" "pnpm" "yarn" "bun")))))

(defun my/javascript-project-build-command (root)
  "Return the conventional check or test command for ROOT."
  (cond
   ((and (my/javascript-deno-project-p root)
         (executable-find "deno"))
    "deno test")
   ((when-let ((script (my/javascript-package-script root))
               (manager (my/javascript-package-manager root)))
      (format "%s run %s" manager script)))
   ((and (or (file-exists-p (expand-file-name "tsconfig.json" root))
             (file-exists-p (expand-file-name "jsconfig.json" root)))
         (my/javascript-find-executable "tsc" root))
    "tsc --noEmit --pretty false")))

(defun my/javascript-standalone-command ()
  "Return a syntax or type-check command for the current source file."
  (when buffer-file-name
    (let ((extension (my/javascript-file-extension)))
      (cond
       ((and (member extension '("js" "mjs" "cjs"))
             (executable-find "node"))
        (format "node --check %s"
                (shell-quote-argument buffer-file-name)))
       ((and (member extension '("ts" "mts" "cts"))
             (my/javascript-find-executable "tsc"))
        (format "tsc --noEmit --pretty false %s"
                (shell-quote-argument buffer-file-name)))))))

(defun my/javascript-set-compile-command ()
  "Set a project-aware JavaScript compilation command."
  (let* ((root (my/javascript-project-root default-directory))
         (command (or (my/javascript-project-build-command root)
                      (my/javascript-standalone-command))))
    (when command
      (setq-local compile-command
                  (format "cd %s && %s"
                          (shell-quote-argument
                           (directory-file-name root))
                          command)))))

(defun my/javascript-deno-formatter ()
  "Return the Apheleia Deno formatter for the current file type."
  (pcase (my/javascript-file-extension)
    ((or "js" "mjs" "cjs") 'denofmt-js)
    ("jsx" 'denofmt-jsx)
    ((or "ts" "mts" "cts") 'denofmt-ts)
    ("tsx" 'denofmt-tsx)
    ("json" 'denofmt-json)
    ("jsonc" 'denofmt-jsonc)
    (_ 'denofmt)))

(defun my/javascript-prettier-formatter ()
  "Return the Apheleia Prettier formatter for the current mode."
  (cond
   ((derived-mode-p 'js-json-mode 'json-mode 'json-ts-mode)
    'prettier-json)
   ((derived-mode-p 'typescript-mode 'typescript-ts-base-mode
                    'typescript-ts-mode 'tsx-ts-mode)
    'prettier-typescript)
   (t
    'prettier-javascript)))

(defun my/javascript-formatter ()
  "Return the best available Apheleia formatter for this buffer."
  (let ((root (my/javascript-project-root default-directory)))
    (cond
     ((and (my/javascript-deno-project-p root)
           (executable-find "deno"))
      (my/javascript-deno-formatter))
     ((and (or (file-exists-p (expand-file-name "biome.json" root))
               (file-exists-p (expand-file-name "biome.jsonc" root)))
           (my/javascript-find-executable "biome" root))
      'biome)
     ((my/javascript-find-executable "prettier" root)
      (my/javascript-prettier-formatter))
     ((my/javascript-find-executable "biome" root)
      'biome))))

(defun my/javascript-format-buffer ()
  "Format with Eglot or the nearest Deno, Biome, or Prettier tool."
  (interactive)
  (cond
   ((and (fboundp 'eglot-managed-p) (eglot-managed-p))
    (eglot-format-buffer))
   ((when-let ((formatter (my/javascript-formatter)))
      (unless (require 'apheleia nil t)
        (user-error "Apheleia is unavailable"))
      (apheleia-format-buffer formatter)
      t))
   (t
    (user-error
     "No formatter found; install Deno, Biome, Prettier, or an LSP server"))))

(defun my/javascript-eslint-config-root (&optional dir)
  "Find an ESLint configuration directory above DIR."
  (my/javascript-root-with-markers
   (or dir default-directory) my/javascript-eslint-markers))

(defun my/javascript-maybe-enable-eslint ()
  "Enable Flymake ESLint when a suitable local or configured binary exists."
  (let* ((local (my/javascript-local-executable "eslint"))
         (config-root (my/javascript-eslint-config-root))
         (executable (or local
                         (and config-root (executable-find "eslint")))))
    (when (and executable (require 'flymake-eslint nil t))
      (setq-local flymake-eslint-executable-name executable
                  flymake-eslint-project-root
                  (or config-root
                      (my/javascript-root-with-markers
                       default-directory my/javascript-module-markers)
                      (my/javascript-project-root default-directory)))
      (flymake-eslint-enable))))

(defun my/javascript-eglot-command (&optional _interactive project)
  "Return the best JavaScript language-server command for PROJECT."
  (let* ((root (if project
                   (project-root project)
                 (my/javascript-project-root default-directory)))
         (deno (and (my/javascript-deno-project-p root)
                    (executable-find "deno")))
         (typescript-language-server
          (my/javascript-find-executable "typescript-language-server" root))
         (vtsls (my/javascript-find-executable "vtsls" root)))
    (cond
     (deno (list deno "lsp"))
     (typescript-language-server
      (list typescript-language-server "--stdio"))
     (vtsls (list vtsls "--stdio")))))

(defun my/javascript-json-eglot-command (&optional _interactive project)
  "Return an available JSON language-server command for PROJECT."
  (let ((root (if project
                  (project-root project)
                (my/javascript-project-root default-directory))))
    (seq-some
     (lambda (program)
       (when-let ((executable
                   (my/javascript-find-executable program root)))
         (list executable "--stdio")))
     '("vscode-json-language-server"
       "vscode-json-languageserver"
       "json-languageserver"))))

(defun my/javascript-maybe-eglot-ensure ()
  "Start Eglot when a JavaScript language server is available."
  (when (my/javascript-eglot-command)
    (eglot-ensure)))

(defun my/javascript-maybe-json-eglot-ensure ()
  "Start Eglot when a JSON language server is available."
  (when (my/javascript-json-eglot-command)
    (eglot-ensure)))

(defun my/javascript-buffer-setup ()
  "Set JavaScript indentation, local tools, formatting, and builds."
  (setq-local indent-tabs-mode nil)
  (when (boundp 'js-indent-level)
    (setq-local js-indent-level 2))
  (when (boundp 'typescript-indent-level)
    (setq-local typescript-indent-level 2))
  (when (boundp 'typescript-ts-mode-indent-offset)
    (setq-local typescript-ts-mode-indent-offset 2))
  (when (boundp 'json-ts-mode-indent-offset)
    (setq-local json-ts-mode-indent-offset 2))
  (my/javascript-add-node-modules-path)
  (my/javascript-set-compile-command)
  (local-set-key (kbd "C-c =") #'my/javascript-format-buffer))

(my/register-javascript-auto-modes)
(add-hook 'project-find-functions #'my/javascript-project)

(dolist (hook '(js-base-mode-hook typescript-mode-hook
                typescript-ts-base-mode-hook))
  (add-hook hook #'my/javascript-buffer-setup)
  (add-hook hook #'my/javascript-maybe-enable-eslint t)
  (add-hook hook #'my/javascript-maybe-eglot-ensure t))

(dolist (hook '(js-json-mode-hook json-ts-mode-hook))
  (add-hook hook #'my/javascript-buffer-setup)
  (add-hook hook #'my/javascript-maybe-json-eglot-ensure t))

(dolist (feature '(js json-ts-mode typescript-mode typescript-ts-mode))
  (eval-after-load feature '(my/register-javascript-auto-modes)))

(with-eval-after-load 'eglot
  (add-to-list
   'eglot-server-programs
   '(((js-jsx-mode :language-id "javascriptreact")
      (js-mode :language-id "javascript")
      (js-ts-mode :language-id "javascript")
      (tsx-ts-mode :language-id "typescriptreact")
      (typescript-ts-mode :language-id "typescript")
      (typescript-mode :language-id "typescript"))
     . my/javascript-eglot-command))
  (add-to-list
   'eglot-server-programs
   '((js-json-mode json-ts-mode) . my/javascript-json-eglot-command)))

;;; javascript.el ends here
