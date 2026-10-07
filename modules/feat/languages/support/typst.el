;;; typst.el --- Typst language support -*- lexical-binding: t; -*-

(require 'packages)
(require 'project)
(require 'text-mode)

(declare-function cape-file "cape" (&optional interactive))
(declare-function cape-wrap-properties "cape" (capf &rest properties))
(defvar cape-file-directory)
(defvar cape-file-prefix)
(defvar cape-file-directory-must-exist)
(defvar thing-at-point-file-name-chars)
(defvar comint-unquote-function)
(defvar comint-requote-function)

;; Eglot uses project.el's root for Tinymist.  Recognize marker-only projects
;; and nested Typst roots without losing Git file listing and ignore rules.
(add-to-list 'project-vc-extra-root-markers ".typst-root" t)

(defvar eglot-server-programs)
(defvar apheleia-formatters)
(defvar apheleia-mode-alist)

;; Enter a grammar-free mode first so treesit-auto can offer installation
;; after mode selection, rather than typst-ts-mode failing before its hooks.
(defvar typst--fallback-syntax-table
  (let ((table (make-syntax-table text-mode-syntax-table)))
    ;; Let Emacs recognize quoted paths and comments without a grammar.
    (modify-syntax-entry ?\" "\"" table)
    (modify-syntax-entry ?\\ "\\" table)
    (modify-syntax-entry ?/ ". 124bn" table)
    (modify-syntax-entry ?* ". 23n" table)
    (modify-syntax-entry ?\n "> b" table)
    table)
  "Basic string and comment syntax for the grammar-free Typst mode.")

(define-derived-mode typst-mode text-mode "Typst (fallback)"
  "Edit Typst as text when its Tree-sitter grammar is unavailable.
Tinymist and Typstyle remain available.  Install the grammar and reopen
or revert the buffer for syntax-aware `typst-ts-mode'."
  :syntax-table typst--fallback-syntax-table)

(treesit/register-language 'typst)

(packages/declare 'typst-ts-mode)
(use-package typst-ts-mode
  :ensure nil
  :mode ("\\.typ\\'" . typst-mode)
  :hook ((typst-ts-mode . typst/eglot-ensure)
         (typst-mode . typst/eglot-ensure)
         (typst-ts-mode . format/mode-maybe)
         (typst-mode . format/mode-maybe)
         (typst-ts-mode . typst/setup-completion)
         (typst-mode . typst/setup-completion))
  :config
  ;; The package also adds a direct association when loaded.  Keep the safe
  ;; fallback first even if the grammar disappears later in this session.
  (add-to-list 'auto-mode-alist '("\\.typ\\'" . typst-mode)))

(defun typst--path-string-bounds ()
  "Return the content bounds of the Typst string at point, or nil.
Use the parse tree when available, not global quote counting: markup
and raw text can contain unmatched quotes before a real code string.
For unfinished strings, let Emacs parse only the grammar's error node."
  (save-excursion
    (let* ((node (and (derived-mode-p 'typst-ts-mode)
                      (treesit-node-at (max (point-min) (1- (point))) 'typst)))
           (string (and node (treesit-parent-until node "\\`string\\'" t))))
      (if string
          (let ((beg (1+ (treesit-node-start string)))
                (end (1- (treesit-node-end string))))
            (when (<= beg (point) end) (cons beg end)))
        (when (or (not node) (equal (treesit-node-type node) "ERROR"))
          (let* ((position (point))
                 (state (if node
                            (parse-partial-sexp (treesit-node-start node) position)
                          (syntax-ppss)))
                 (quote (nth 8 state)))
            (when (and (nth 3 state) quote (eq (char-after quote) ?\"))
              (cons (1+ quote)
                    (or (when-let* ((end (ignore-errors (scan-sexps quote 1))))
                          (1- end))
                        position)))))))))

(defun typst--path-unquote (path)
  "Decode escaped quotes and backslashes in a Typst PATH."
  (replace-regexp-in-string (rx "\\" (group (any "\\\""))) "\\1" path t))

(defun typst--path-quote (path)
  "Escape quotes and backslashes in a filename for a Typst string."
  (replace-regexp-in-string (rx (any "\\\""))
                            (lambda (char) (concat "\\" char)) path t t))

(defun typst--path-requote (position path)
  "Map unquoted POSITION into PATH and return Typst's quoting function."
  (cons (length (typst--path-quote
                 (substring (typst--path-unquote path) 0 position)))
        #'typst--path-quote))

(defun typst/path-completion-at-point ()
  "Complete path-like Typst strings using Cape's file completion.
Relative paths start at the source file's directory.  A leading slash
is preserved and completes from `.typst-root', then the normal project
root, then the source directory.  Cape owns file listing and metadata."
  (when-let* ((bounds (typst--path-string-bounds))
              (beg (car bounds))
              (path (buffer-substring-no-properties beg (point)))
              ((or (string-prefix-p ".." path)
                   (string-prefix-p "./" path)
                   (string-prefix-p "/" path))))
    (require 'cape)
    (require 'comint)
    (let* ((non-essential t)
           (source-directory (if buffer-file-name
                                 (file-name-directory buffer-file-name)
                               default-directory))
           (rooted (string-prefix-p "/" path))
           (cape-file-directory
            (if rooted
                (or (locate-dominating-file source-directory ".typst-root")
                    (when-let* ((project (project-current nil source-directory)))
                      (project-root project))
                    source-directory)
              source-directory))
           (cape-file-prefix nil)
           ;; Context is already checked; even bare `..' and `/' can complete.
           (cape-file-directory-must-exist nil)
           ;; The string parser supplies exact bounds.  Do not split filenames
           ;; containing spaces or punctuation using unquoted-token heuristics.
           (thing-at-point-file-name-chars "[:ascii:][:nonascii:]")
           (comint-unquote-function #'typst--path-unquote)
           (comint-requote-function #'typst--path-requote))
      (save-restriction
        ;; Exclude the leading slash so Cape treats it as project-relative,
        ;; and exclude the quotes so accepting a filename cannot replace them.
        (narrow-to-region (+ beg (if rooted 1 0)) (cdr bounds))
        (cape-wrap-properties #'cape-file :exclusive t :company-prefix-length t)))))

(defun typst/setup-completion ()
  "Prefer path completion in Typst strings without replacing Eglot.
Run again on Eglot's public lifecycle hook to preserve priority."
  (when (derived-mode-p 'typst-mode 'typst-ts-mode)
    ;; Replace the generic filesystem-root source only in Typst buffers.
    (remove-hook 'completion-at-point-functions #'cape-file t)
    (add-hook 'completion-at-point-functions #'typst/path-completion-at-point -90 t)
    (add-hook 'eglot-managed-mode-hook #'typst/setup-completion nil t)))

(defun typst/eglot-workspace-configuration (_server)
  "Configure Tinymist to use Typstyle for Typst formatting."
  '(:tinymist (:formatterMode "typstyle")))

(defun typst/eglot-ensure ()
  "Start Tinymist for Typst buffers."
  (eglot-ensure))

(with-eval-after-load 'eglot
  ;; Tinymist is the language server for both the fallback and Tree-sitter
  ;; modes.  The explicit `lsp' subcommand is unnecessary; it is the default.
  (add-to-list 'eglot-server-programs '(typst-mode . ("tinymist")))
  (add-to-list 'eglot-server-programs '(typst-ts-mode . ("tinymist")))
  (lsp/register-workspace-configuration '(typst-mode typst-ts-mode)
                                        #'typst/eglot-workspace-configuration))

(defun typst/configure-apheleia ()
  "Use Typstyle for Typst buffers when Eglot is not formatting them."
  (setf (alist-get 'typstyle apheleia-formatters)
        '("typstyle"))
  (setf (alist-get 'typst-mode apheleia-mode-alist) 'typstyle)
  (setf (alist-get 'typst-ts-mode apheleia-mode-alist) 'typstyle))

(with-eval-after-load 'apheleia
  (typst/configure-apheleia))

;;; typst.el ends here
