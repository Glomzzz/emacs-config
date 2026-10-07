;;; haskell.el --- Haskell language support -*- lexical-binding: t; -*-

(require 'packages)
(require 'project)
(require 'seq)

(defvar eglot-server-programs)
(defvar eglot-sync-connect)
(defvar apheleia-formatters)
(defvar apheleia-mode-alist)
(defvar format/apheleia-owns)
(defvar corfu-sort-override-function)
(declare-function corfu-sort-length-alpha "corfu" (list))

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
  '(:haskell (:maxCompletions 1000)))

(with-eval-after-load 'eglot
  ;; HLS selects the GHC version and project component from the current
  ;; Cabal or Stack project.  Cap its worker threads so indexing cannot
  ;; saturate the machine, and replace Eglot's bundled `static-ls' candidate
  ;; so the server choice is deterministic.
  (dolist (mode '(haskell-mode haskell-literate-mode))
    (setf (alist-get mode eglot-server-programs)
          '("haskell-language-server-wrapper" "--lsp" "-j" "2")))
  (lsp/register-workspace-configuration
   '(haskell-mode haskell-literate-mode)
   #'haskell/eglot-workspace-configuration))

;;; completion

(defun haskell--completion-rank (candidate)
  "Return the proximity rank of completion CANDIDATE.
Lower ranks come first: bindings local to the current declaration, then
other definitions, and finally names imported from other modules.  HLS
provides the needed metadata in the completion item: imported names have
a \"from MODULE\" detail, while local bindings have a type detail but no
`:itemFile' in their resolve data."
  (let* ((item (get-text-property 0 'eglot--lsp-item candidate))
         (detail (and item (plist-get item :detail)))
         (file (and item
                    (plist-get (plist-get (plist-get item :data)
                                          :resolveValue)
                               :itemFile))))
    (cond
     ((and (stringp detail) (string-prefix-p "from " detail)) 2)
     ((and (null file)
           (stringp detail)
           (string-prefix-p ":: " detail))
      0)
     (t 1))))

(defun haskell--completion-sort-text (candidate)
  "Return HLS's sort key for CANDIDATE, or an empty string."
  (or (plist-get (get-text-property 0 'eglot--lsp-item candidate) :sortText)
      ""))

(defun haskell--sort-completions (candidates)
  "Sort CANDIDATES with local bindings first, then imported names last.
Falls back to Corfu's default length/alpha sort when no LSP candidates
are present, for example when Cape supplies file names or buffer words."
  (if (seq-some (lambda (candidate)
                  (get-text-property 0 'eglot--lsp-item candidate))
                candidates)
      (sort (copy-sequence candidates)
            (lambda (a b)
              (let ((ra (haskell--completion-rank a))
                    (rb (haskell--completion-rank b)))
                (or (< ra rb)
                    (and (= ra rb)
                         (let ((sa (haskell--completion-sort-text a))
                               (sb (haskell--completion-sort-text b)))
                           (or (string-lessp sa sb)
                               (and (string= sa sb)
                                    (string-lessp (substring-no-properties a)
                                                  (substring-no-properties b))))))))))
    (if (fboundp 'corfu-sort-length-alpha)
        (corfu-sort-length-alpha candidates)
      candidates)))

(defun haskell/setup-completion ()
  "Order Haskell completion candidates by proximity.
Local bindings come first, then other definitions, then imported names."
  (require 'corfu nil t)
  (when (boundp 'corfu-sort-override-function)
    (setq-local corfu-sort-override-function #'haskell--sort-completions)))

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
         (haskell-mode . haskell/setup-completion)
         (haskell-mode . format/mode-maybe)))

;;; haskell.el ends here
