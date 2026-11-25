;;; rust.el --- Rust language support -*- lexical-binding: t; -*-

(require 'packages)

(declare-function eglot-rename "eglot" ())
(defvar eglot-server-programs)
(declare-function flymake-diagnostic-code "flymake" (diagnostic))
(defvar eglot-ignored-server-capabilities)
(defvar apheleia-formatters)
(defvar apheleia-mode-alist)

;; rust-ts-mode is built into Emacs; rust-mode is the non-Tree-sitter
;; fallback and comes from MELPA.
(treesit/register-language 'rust)

(defun rust/rename ()
  "Rename the identifier at point through Eglot."
  (interactive)
  (call-interactively #'eglot-rename))

(defun rust/eglot-ensure ()
  "Start Rust Analyzer with push-only diagnostics in this buffer.
Keep saved compiler warnings visible while editing.  Rust Analyzer's
pull reports contain only native diagnostics, so an empty pull report
can otherwise clear compiler warnings until the next save."
  (require 'eglot)
  (setq-local eglot-ignored-server-capabilities
              (cons :diagnosticProvider
                    (remq :diagnosticProvider eglot-ignored-server-capabilities)))
  (eglot-ensure))

(packages/declare 'rust-mode)
(use-package rust-mode
  :ensure nil
  :mode "\\.rs\\'"
  :hook (rust-mode . rust/eglot-ensure)
  :bind (:map rust-mode-map
              ("C-c r" . rust/rename)))

(use-package rust-ts-mode
  :ensure nil
  :bind (:map rust-ts-mode-map
              ("C-c r" . rust/rename)))

;; Replace the old direct hooks too when reloading an existing session.
(remove-hook 'rust-mode-hook #'eglot-ensure)
(remove-hook 'rust-ts-mode-hook #'eglot-ensure)
;; rust-ts-mode is built into Emacs, so no package is declared.
(add-hook 'rust-ts-mode-hook #'rust/eglot-ensure)

(defun rust/eglot-workspace-configuration (_server)
  "Limit rust-analyzer's `check' to the crate being edited.
Whole-workspace checks rebuild every member on each save.  With
`check.workspace' disabled, saved diagnostics cover only the current
package."
  '(:rust-analyzer (:check (:workspace :json-false))))

(with-eval-after-load 'eglot
  (defclass rust/eglot-server (eglot-lsp-server) ()
    :documentation "Rust Analyzer using a single push diagnostic stream.")
  (cl-defmethod eglot-client-capabilities ((server rust/eglot-server))
    ;; Ignoring :diagnosticProvider alone is insufficient: Rust Analyzer must
    ;; also know to push its native diagnostics instead of expecting pulls.
    ;; Use Eglot's public server specialization API, not private report advice.
    (let ((capabilities (copy-tree (cl-call-next-method))))
      (cl-remf (plist-get capabilities :textDocument) :diagnostic)
      capabilities))
  ;; Keep the server choice and diagnostic negotiation scoped to both Rust modes.
  (dolist (mode '(rust-mode rust-ts-mode))
    (setf (alist-get mode eglot-server-programs)
          '(rust/eglot-server "rust-analyzer")))
  (lsp/register-workspace-configuration '(rust-mode rust-ts-mode)
                                        #'rust/eglot-workspace-configuration))

;; Flymake's end-of-line summary shows the most severe diagnostic, which for
;; unused code is the rustc or rust-analyzer `unused_*' warning.  Hide only
;; those summaries in Rust buffers; fringe markers and diagnostic lists keep
;; reporting them.
(defun rust/unused-overlay-p (overlay)
  "Return non-nil when OVERLAY holds an unused-code diagnostic in a Rust buffer.
Rustc and rust-analyzer use codes such as `unused_variables'; any code
starting with \"unused\" matches."
  (when-let* ((buffer (overlay-buffer overlay))
              (diagnostic (overlay-get overlay 'flymake-diagnostic)))
    (with-current-buffer buffer
      (and (derived-mode-p 'rust-mode 'rust-ts-mode)
           (let ((code (flymake-diagnostic-code diagnostic)))
             (and (stringp code) (string-prefix-p "unused" code)))))))

(defun rust/eol-summary-without-unused (original source-overlays)
  "Hide unused-code diagnostics from Rust end-of-line summaries.
Around advice for the private `flymake--eol-overlay-summary', whose ORIGINAL
implementation receives SOURCE-OVERLAYS, the diagnostic overlays sharing one
line end.  When every such diagnostic is unused code, return a bare newline
so the line break stays intact."
  (let* ((kept (seq-remove #'rust/unused-overlay-p source-overlays))
         (hidden (- (length source-overlays) (length kept))))
    (cond ((zerop hidden) (funcall original source-overlays))
          (kept (funcall original kept))
          (t (propertize "\n" 'cursor t)))))

(with-eval-after-load 'flymake
  (advice-add 'flymake--eol-overlay-summary :around
              #'rust/eol-summary-without-unused))

(defun rust/configure-apheleia ()
  "Use rustfmt for Rust buffers when Eglot is not formatting them."
  (setf (alist-get 'rustfmt apheleia-formatters)
        '("rustfmt" "--emit" "stdout"))
  (setf (alist-get 'rust-mode apheleia-mode-alist) 'rustfmt)
  (setf (alist-get 'rust-ts-mode apheleia-mode-alist) 'rustfmt))

(with-eval-after-load 'apheleia
  (rust/configure-apheleia))

;; Dape already ships mode-scoped `lldb-dap' and `lldb-vscode'
;; configurations for the Rust modes, so no adapter registration is needed
;; here.  Install LLDB (or an equivalent adapter) to use them.

;;; rust.el ends here
