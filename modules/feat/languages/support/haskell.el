;;; haskell.el --- Haskell language support -*- lexical-binding: t; -*-

(require 'packages)
(require 'project)

(defvar eglot-server-programs)
(defvar eglot-sync-connect)
(defvar apheleia-formatters)
(defvar apheleia-mode-alist)
(defvar format/apheleia-owns)
(defgroup haskell-tools nil
  "Haskell server and formatter integration."
  :group 'tools)

(defcustom haskell/server-threads 2
  "HLS worker limit, or nil to use the server's own default."
  :type '(choice (const nil) (integer :tag "Workers"))
  :group 'haskell-tools)

(defcustom haskell/max-completions 1000
  "Maximum completions requested from HLS."
  :type 'integer
  :group 'haskell-tools)

(put 'haskell/server-threads 'safe-local-variable
     (lambda (value) (or (null value) (and (integerp value) (> value 0)))))
(put 'haskell/max-completions 'safe-local-variable
     (lambda (value) (and (integerp value) (> value 0))))

(defun haskell/server-command (&rest _ignored)
  "Return the HLS command using the current project's worker limit."
  (append '("haskell-language-server-wrapper" "--lsp")
          (when haskell/server-threads
            (list "-j" (number-to-string haskell/server-threads)))))

;; Haskell does not have a built-in Tree-sitter mode in this Emacs build;
;; `haskell-mode' provides the editing mode and project integration.
(packages/declare 'haskell-mode)

(defconst haskell--project-markers
  '("hie.yaml" "hie.yml" "stack.yaml" "cabal.project" "cabal.project.local"
    "package.yaml" "*.cabal")
  "Cradle files and patterns that mark the root of a Haskell project.")

;; The built-in finder chooses the nearest marker across languages and keeps
;; Git file listing/ignores when a cradle is nested inside a repository.
;; It also recognizes these roots without VCS metadata.
(remove-hook 'project-find-functions 'haskell/project-try)
(dolist (marker haskell--project-markers)
  (add-to-list 'project-vc-extra-root-markers marker t))

(defun haskell/setup-formatting ()
  "Let Apheleia/Ormolu own save-time formatting for Haskell buffers.
HLS formatting is a synchronous request, so a save waits for the server.
While HLS loads a Stack or Nix cradle that wait can last minutes, so
Haskell always formats through the asynchronous Apheleia path instead."
  (setq-local format/apheleia-owns t))

(defun haskell/eglot-ensure ()
  "Start HLS for the current Haskell buffer.
HLS selects the project cradle when the file belongs to one and
otherwise falls back to its default plain-GHC session, so standalone
files such as `~/git/haskell/boot/boot.hs' still get completion and
diagnostics.  The connection is asynchronous because waiting for the
handshake inside a mode hook freezes every Emacs frame."
  (haskell/setup-formatting)
  (require 'eglot)
  (setq-local eglot-sync-connect nil)
  (eglot-ensure))

(defun haskell/eglot-workspace-configuration (_server)
  "Ask HLS for enough completions to include unimported names.
HLS orders in-scope completions before package exports and truncates
the list to `maxCompletions' (40 by default), which hides the exports
that carry its `extend import' command."
  (list :haskell (list :maxCompletions haskell/max-completions)))

(with-eval-after-load 'eglot
  ;; HLS selects the GHC version and project component from the current
  ;; Cabal or Stack project.  Cap its worker threads so indexing cannot
  ;; saturate the machine, and replace Eglot's bundled `static-ls' candidate
  ;; so the server choice is deterministic.
  (dolist (mode '(haskell-mode haskell-literate-mode))
    (setf (alist-get mode eglot-server-programs)
          #'haskell/server-command))
  (lsp/register-workspace-configuration
   '(haskell-mode haskell-literate-mode)
   #'haskell/eglot-workspace-configuration))

;; Corfu already honors Eglot's display-sort-function and HLS's sortText.
;; Do not parse human-readable labels or server-private resolve payloads.
(remove-hook 'haskell-mode-hook 'haskell/setup-completion)

(defun haskell/configure-apheleia ()
  "Use Ormolu for Haskell buffers when Eglot is not formatting them."
  (setf (alist-get 'ormolu apheleia-formatters)
        '("ormolu" "-m" "stdout" "--stdin-input-file" filepath))
  (setf (alist-get 'haskell-mode apheleia-mode-alist) 'ormolu)
  (setf (alist-get 'haskell-literate-mode apheleia-mode-alist) 'ormolu))

;; Haskell uses Apheleia/Ormolu for asynchronous save-time formatting.

(with-eval-after-load 'apheleia
  (haskell/configure-apheleia))

;; Define helpers before `use-package' so its hooks need no stub autoloads.
;; Literate Haskell derives from `haskell-mode' and runs these hooks too.
(use-package haskell-mode
  :ensure nil
  :mode (("\\.hs\\'" . haskell-mode)
         ("\\.lhs\\'" . haskell-literate-mode)
         ("\\.hsc\\'" . haskell-mode))
  :hook ((haskell-mode . haskell/eglot-ensure)
         (haskell-mode . format/mode-maybe)))

;;; haskell.el ends here
