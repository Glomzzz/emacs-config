;;; javascript.el --- JavaScript and TypeScript language support -*- lexical-binding: t; -*-

(require 'compile)
(require 'project)
(require 'packages)

(declare-function dape-ensure-command "dape" (config))
(declare-function sp-local-pair "smartparens" (modes open close &rest arguments))
(defvar eglot-server-programs)
(defvar apheleia-formatters)
(defvar apheleia-mode-alist)

(defgroup javascript-tools nil
  "JavaScript project tools and debugger settings."
  :group 'tools)

(defcustom javascript/runtime 'auto
  "Runtime for the current project: auto, node, bun, or deno.
Auto honors Deno manifests and Bun lockfiles, then prefers Node."
  :type '(choice (const auto) (const node) (const bun) (const deno))
  :group 'javascript-tools)
(make-variable-buffer-local 'javascript/runtime)
(put 'javascript/runtime 'safe-local-variable
     (lambda (value) (memq value '(auto node bun deno))))

(defcustom javascript/run-command nil
  "Optional project-local shell command for `javascript/run'.
Nil runs the current file with `javascript/runtime'.  Shell commands
are intentionally not marked safe directory-local values."
  :type '(choice (const nil) string)
  :group 'javascript-tools)
(make-variable-buffer-local 'javascript/run-command)

(defcustom javascript/build-command nil
  "Optional project-local shell command for `javascript/compile'."
  :type '(choice (const nil) string)
  :group 'javascript-tools)
(make-variable-buffer-local 'javascript/build-command)

(defcustom javascript/check-command nil
  "Optional project-local shell command for `javascript/check'."
  :type '(choice (const nil) string)
  :group 'javascript-tools)
(make-variable-buffer-local 'javascript/check-command)

;; `treesit-auto' supplies the grammar sources and remaps the fallback modes
;; when the JavaScript, TypeScript, and TSX grammars are installed.
(treesit/register-language 'javascript)
(treesit/register-language 'typescript)
(treesit/register-language 'tsx)

(defun javascript/eglot-ensure ()
  "Start Eglot for JavaScript and TypeScript buffers."
  (eglot-ensure))

;; `js-mode' is built into Emacs.  The TypeScript fallback comes from MELPA;
;; the Tree-sitter modes are built into current Emacs releases.
(packages/declare 'typescript-mode)
(use-package typescript-mode
  :ensure nil
  :mode "\\.tsx?\\'"
  :hook (typescript-mode . javascript/eglot-ensure))

(add-hook 'js-mode-hook #'javascript/eglot-ensure)
(add-hook 'js-ts-mode-hook #'javascript/eglot-ensure)
(add-hook 'typescript-ts-mode-hook #'javascript/eglot-ensure)
(add-hook 'tsx-ts-mode-hook #'javascript/eglot-ensure)

(defun javascript/eglot-workspace-configuration (_server)
  "Configure TypeScript Language Server for useful project-wide completion."
  '(:typescript (:inlayHints (:includeInlayParameterNameHints "all"
                            :includeInlayParameterNameHintsWhenArgumentMatches t
                            :includeInlayFunctionParameterTypeHints t
                            :includeInlayVariableTypeHints t
                            :includeInlayPropertyDeclarationTypeHints t
                            :includeInlayFunctionLikeReturnTypeHints t
                            :includeInlayEnumMemberValueHints t)
                :preferences (:includeCompletionsForModuleExports t
                              :includeCompletionsForImportStatements t
                              :includeAutomaticOptionalChainCompletions t
                              :includeAutomaticSuggest t))
    :javascript (:preferences (:includeCompletionsForModuleExports t
                               :includeCompletionsForImportStatements t
                               :includeAutomaticOptionalChainCompletions t
                               :includeAutomaticSuggest t))))

(with-eval-after-load 'eglot
  ;; TypeScript Language Server handles JavaScript as well as TypeScript and
  ;; keeps the server choice consistent across fallback and Tree-sitter modes.
  (dolist (mode '(js-mode js-ts-mode
                  typescript-mode typescript-ts-mode tsx-ts-mode))
    (setf (alist-get mode eglot-server-programs)
          '("typescript-language-server" "--stdio")))
  (lsp/register-workspace-configuration
   '(js-mode js-ts-mode typescript-mode typescript-ts-mode tsx-ts-mode)
   #'javascript/eglot-workspace-configuration))

(with-eval-after-load 'smartparens-config
  (require 'smartparens-javascript)
  ;; `<` and `>` are also comparisons, shifts, and arrows.  Do not guess:
  ;; keep angle brackets for explicit wrapping via `C-c p <` only.
  (sp-local-pair '(js-mode js-ts-mode typescript-mode
                   typescript-ts-mode tsx-ts-mode)
                 "<" ">" :actions '(wrap)))

(defconst javascript--project-markers
  '("deno.json" "deno.jsonc" "tsconfig.json" "package.json")
  "Manifest files that identify a JavaScript project root.")

(defun javascript--marker-root (directory)
  "Return the nearest JavaScript project root found above DIRECTORY.
Only manifests count as markers, and the nearest one wins.  A bare
lockfile such as `bun.lock' in the home directory must not claim every
file below it and shadow more specific projects."
  (let ((roots
         (delq nil
               (mapcar (lambda (marker)
                         (locate-dominating-file directory marker))
                       javascript--project-markers))))
    (car (sort roots (lambda (a b) (> (length a) (length b)))))))

;; Share marker selection with Haskell and Git instead of competing global
;; finders.  The VC-aware backend also handles manifest-only projects.
(remove-hook 'project-find-functions 'javascript/project-try)
(dolist (marker javascript--project-markers)
  (add-to-list 'project-vc-extra-root-markers marker t))

(defun javascript/project-root ()
  "Return the nearest JavaScript manifest root, then the current project.
Runtime and compiler commands use the manifest even in mixed-language
repositories whose general project root belongs to another toolchain."
  (or (javascript--marker-root default-directory)
      (when-let* ((project (project-current)))
        (project-root project))
      default-directory))

(defun javascript--typescript-p ()
  "Return non-nil when the current buffer contains TypeScript."
  (derived-mode-p 'typescript-mode 'typescript-ts-mode 'tsx-ts-mode))

(defun javascript--tsx-p ()
  "Return non-nil when the current buffer contains TSX."
  (or (derived-mode-p 'tsx-ts-mode)
      (and buffer-file-name
           (string-match-p "\\.tsx\\'" buffer-file-name))))

(defun javascript--deno-project-p (root)
  "Return non-nil when ROOT has a Deno project file."
  (or (file-exists-p (expand-file-name "deno.json" root))
      (file-exists-p (expand-file-name "deno.jsonc" root))))

(defun javascript--bun-project-p (root)
  "Return non-nil when ROOT has a Bun lockfile."
  (or (file-exists-p (expand-file-name "bun.lock" root))
      (file-exists-p (expand-file-name "bun.lockb" root))))

(defun javascript--runtime (root)
  "Return the runtime executable appropriate for ROOT and the current buffer."
  (cond
   ((not (eq javascript/runtime 'auto))
    (or (executable-find (symbol-name javascript/runtime))
        (user-error "Requested runtime `%s' is not installed" javascript/runtime)))
   ((javascript--deno-project-p root)
    (or (executable-find "deno")
        (user-error "Deno project detected but `deno' is not installed")))
   ((javascript--bun-project-p root)
    (or (executable-find "bun")
        (user-error "Bun project detected but `bun' is not installed")))
   ((executable-find "node")
    (executable-find "node"))
   ((executable-find "bun")
    (executable-find "bun"))
   ((executable-find "deno")
    (executable-find "deno"))
   (t
    (user-error "No JavaScript runtime found; install Node, Bun, or Deno"))))

(defun javascript/runtime-command ()
  "Return a shell command that runs the current JavaScript buffer."
  (let* ((file (or buffer-file-name
                   (user-error "Current buffer does not visit a file")))
         (root (javascript/project-root))
         (runtime (javascript--runtime root))
         (runtime-name (file-name-nondirectory runtime))
         (quoted-file (shell-quote-argument file)))
    (cond
     ((equal runtime-name "deno")
      (format "%s run %s" (shell-quote-argument runtime) quoted-file))
     ((and (javascript--typescript-p)
           (equal runtime-name "node"))
      (if (javascript--tsx-p)
          (user-error "TSX requires Bun or Deno; Node cannot execute TSX")
        ;; Node's type stripping covers simple TypeScript files without adding
        ;; a project-local transpiler.  `tsc' remains available for full builds.
        (format "%s --experimental-strip-types %s"
                (shell-quote-argument runtime) quoted-file)))
     ((equal runtime-name "bun")
      (format "%s run %s" (shell-quote-argument runtime) quoted-file))
     (t
      (format "%s %s" (shell-quote-argument runtime) quoted-file)))))

(defun javascript--compile-command (&optional check-only)
  "Return the TypeScript compiler or JavaScript syntax-check command.
When CHECK-ONLY is non-nil, TypeScript does not emit files."
  (let* ((file (or buffer-file-name
                   (user-error "Current buffer does not visit a file")))
         (root (javascript/project-root))
         (tsconfig (expand-file-name "tsconfig.json" root)))
    (if (javascript--typescript-p)
        (if (file-exists-p tsconfig)
            (format "tsc --pretty false --project %s%s"
                    (shell-quote-argument tsconfig)
                    (if check-only " --noEmit" ""))
          (format "tsc --pretty false%s %s"
                  (if check-only " --noEmit" "")
                  (shell-quote-argument file)))
      (format "node --check %s" (shell-quote-argument file)))))

(defun javascript/run ()
  "Run the current JavaScript or TypeScript file in a compilation buffer."
  (interactive)
  (let ((default-directory (javascript/project-root)))
    (compile (or javascript/run-command (javascript/runtime-command)))))

(defun javascript/compile ()
  "Compile the current TypeScript project or check JavaScript syntax."
  (interactive)
  (let ((default-directory (javascript/project-root)))
    (compile (or javascript/build-command (javascript--compile-command)))))

(defun javascript/check ()
  "Type-check TypeScript without emitting files, or check JavaScript syntax."
  (interactive)
  (let ((default-directory (javascript/project-root)))
    (compile (or javascript/check-command (javascript--compile-command t)))))

(defun javascript/configure-apheleia ()
  "Use Prettier for JavaScript and TypeScript fallback formatting."
  ;; Let Prettier infer JavaScript, JSX, TypeScript, and TSX from the
  ;; stdin filepath.  This preserves project-specific syntax choices.
  (setf (alist-get 'javascript-prettier apheleia-formatters)
        '("apheleia-npx" "prettier" "--stdin-filepath" filepath))
  (setf (alist-get 'typescript-prettier apheleia-formatters)
        '("apheleia-npx" "prettier" "--stdin-filepath" filepath))
  (dolist (mode '(js-mode js-ts-mode))
    (setf (alist-get mode apheleia-mode-alist) 'javascript-prettier))
  (dolist (mode '(typescript-mode typescript-ts-mode tsx-ts-mode))
    (setf (alist-get mode apheleia-mode-alist) 'typescript-prettier)))

(with-eval-after-load 'apheleia
  (javascript/configure-apheleia))

(defun javascript/ensure-bun (config)
  "Ensure CONFIG's adapter and Bun runtime are available."
  (dape-ensure-command config)
  (unless (executable-find "bun")
    (user-error "Bun is required for the TypeScript debugger configuration")))

(defun javascript/ensure-deno (config)
  "Ensure CONFIG's adapter and Deno runtime are available."
  (dape-ensure-command config)
  (unless (executable-find "deno")
    (user-error "Deno is required for the Deno debugger configuration")))

;; Dape's bundled JavaScript configurations expect an adapter downloaded into
;; its cache.  These configurations use the Nix-provided `js-debug' launcher,
;; which wraps the same DAP server and needs no mutable adapter installation.
(debug/register-config
 'javascript-node
 '(modes (js-mode js-ts-mode)
   ensure dape-ensure-command
   command "js-debug"
   command-args (:autoport)
   port :autoport
   :type "pwa-node"
   :request "launch"
   :cwd dape-cwd
   :program dape-buffer-default
   :console "internalConsole"))

(debug/register-config
 'typescript-node
 '(modes (typescript-mode typescript-ts-mode)
   ensure dape-ensure-command
   command "js-debug"
   command-args (:autoport)
   port :autoport
   :type "pwa-node"
   :request "launch"
   :runtimeExecutable "node"
   :runtimeArgs ("--experimental-strip-types")
   :cwd dape-cwd
   :program dape-buffer-default
   :console "internalConsole"))

(debug/register-config
 'typescript-bun
 '(modes (typescript-mode typescript-ts-mode tsx-ts-mode)
   ensure javascript/ensure-bun
   command "js-debug"
   command-args (:autoport)
   port :autoport
   :type "pwa-node"
   :request "launch"
   :runtimeExecutable "bun"
   :runtimeArgs ("run")
   :cwd dape-cwd
   :program dape-buffer-default
   :console "internalConsole"))

(debug/register-config
 'typescript-deno
 '(modes (js-mode js-ts-mode typescript-mode typescript-ts-mode tsx-ts-mode)
   ensure javascript/ensure-deno
   command "js-debug"
   command-args (:autoport)
   port :autoport
   :type "pwa-node"
   :request "launch"
   :runtimeExecutable "deno"
   :runtimeArgs ("run" "--inspect-wait" "--allow-all")
   :attachSimplePort 9229
   :cwd dape-cwd
   :program dape-buffer-default
   :console "internalConsole"))

(debug/register-config
 'javascript-node-attach
 '(modes (js-mode js-ts-mode typescript-mode typescript-ts-mode tsx-ts-mode)
   ensure dape-ensure-command
   command "js-debug"
   command-args (:autoport)
   port :autoport
   :type "pwa-node"
   :request "attach"
   :port 9229))

(debug/register-config
 'javascript-chrome
 '(modes (js-mode js-ts-mode typescript-mode typescript-ts-mode tsx-ts-mode)
   ensure dape-ensure-command
   command "js-debug"
   command-args (:autoport)
   port :autoport
   :type "pwa-chrome"
   :request "launch"
   :url "http://localhost:3000"
   :webRoot dape-cwd))

;;; javascript.el ends here
