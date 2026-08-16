;;; ryzenbit.el --- Ryzenbit editing and language-server support -*- lexical-binding: t; -*-

;;; Commentary:

;; Provides a local Ryzenbit major mode and connects it to the `rz lsp'
;; language server (crates/ryzenbit-lsp in the ryzenbit repository).

;;; Code:

(require 'rx)
(require 'project)

;; Cross-module references (lsp.el loads before this module in init.el).
(declare-function my/eglot-ensure-idle "lsp")
(defvar eglot-server-programs)

(defgroup ryzenbit nil
  "Editing support for the Ryzenbit programming language."
  :group 'languages
  :link '(url-link "https://github.com/glom/ryzenbit"))

(defcustom ryzenbit-indent-offset 2
  "Number of spaces used for each Ryzenbit indentation level."
  :type 'integer
  :safe #'integerp
  :group 'ryzenbit)

(defcustom ryzenbit-lsp-command '("rz" "lsp")
  "Command line used to start the Ryzenbit language server."
  :type '(repeat string)
  :safe (lambda (value) (and (listp value) (cl-every #'stringp value)))
  :group 'ryzenbit)

(defvar ryzenbit-mode-syntax-table
  (let ((table (make-syntax-table)))
    (dolist (pair '((?\( . "()") (?\) . ")(")
                    (?\[ . "(]") (?\] . ")[")
                    (?{ . "(}") (?} . "){")))
      (modify-syntax-entry (car pair) (cdr pair) table))
    ;; Punctuation and operators are symbols/punctuation, not word chars.
    (dolist (char '(?$ ?% ?& ?+ ?~ ?! ?^ ?# ?= ?. ?: ?- ?? ?< ?> ?| ?@ ?/ ?*))
      (modify-syntax-entry char "." table))
    ;; `_` is an identifier character; `'` opens char literals.
    (modify-syntax-entry ?_ "_" table)
    (modify-syntax-entry ?\' "\"" table)
    (modify-syntax-entry ?\" "\"" table)
    (modify-syntax-entry ?\\ "\\" table)
    ;; `//` line comments and nested `/* ... */` block comments.
    (modify-syntax-entry ?\n "> b" table)
    table)
  "Syntax table used in `ryzenbit-mode'.")

(defconst ryzenbit--keywords
  '("as" "class" "effect" "else" "export" "fun" "handle" "if" "import"
    "instance" "let" "match" "module" "mut" "op" "perform" "pub" "resume"
    "return" "type" "where")
  "Ryzenbit keywords. All lowercase single words per the language design.")

(defconst ryzenbit--constants
  '("false" "true")
  "Ryzenbit boolean literals.")

(defconst ryzenbit--primitive-types
  '("Bool" "Char" "Float32" "Float64" "ISize" "Int8" "Int16" "Int32"
    "Int64" "Int128" "String" "UInt8" "UInt16" "UInt32" "UInt64"
    "UInt128" "USize" "Unit")
  "Ryzenbit primitive value types.")

(defconst ryzenbit--prelude-effects
  '("Async" "Console" "Env" "Exception" "File" "Network" "Random" "State"
    "Time")
  "Effects built into the Ryzenbit prelude (docs/stdlib.md).")

(defconst ryzenbit--identifier-re
  (rx symbol-start
      (or alpha "_") (* (any alnum "_"))
      symbol-end)
  "Regexp matching an unqualified Ryzenbit identifier.")

(defconst ryzenbit--declaration-re
  (rx symbol-start
      (or "fun" "let")
      symbol-end
      (+ space)
      (group (regexp ryzenbit--identifier-re)))
  "Regexp matching a value declaration and capturing its name.")

(defconst ryzenbit--type-declaration-re
  (rx symbol-start
      (or "class" "effect" "instance" "type")
      symbol-end
      (+ space)
      (group (regexp ryzenbit--identifier-re)))
  "Regexp matching a type-like declaration and capturing its name.")

(defconst ryzenbit--module-re
  (rx symbol-start
      (or "import" "module")
      symbol-end
      (+ space)
      (group (+ (any alnum "_."))))
  "Regexp matching a module path after an import or module declaration.")

(defconst ryzenbit--number-re
  (rx symbol-start
      (or (seq "0" (any "xX") (+ (any xdigit "_")))
          (seq "0" (any "bB") (+ (any "01_")))
          (seq "0" (any "oO") (+ (any "0-7_")))
          (seq (+ digit) (* (any digit "_"))
               (? (seq "." (+ digit) (* (any digit "_"))))
               (? (seq (any "eE") (? (any "+-")) (+ digit)))))
      symbol-end)
  "Regexp matching Ryzenbit integer and float literals.")

(defconst ryzenbit-font-lock-keywords
  `((,ryzenbit--declaration-re 1 font-lock-function-name-face)
    (,ryzenbit--type-declaration-re 1 font-lock-type-face)
    (,ryzenbit--module-re 1 font-lock-constant-face)
    (,(regexp-opt ryzenbit--keywords 'symbols) . font-lock-keyword-face)
    (,(regexp-opt ryzenbit--constants 'symbols) . font-lock-constant-face)
    (,(regexp-opt ryzenbit--primitive-types 'symbols) . font-lock-type-face)
    (,(regexp-opt ryzenbit--prelude-effects 'symbols)
     . font-lock-builtin-face)
    (,(rx symbol-start upper (* (any alnum "_")) symbol-end)
     . font-lock-type-face)
    (,ryzenbit--number-re . font-lock-constant-face)
    (,(rx "'" (or (seq "\\" nonl) (not (any "'\\\n"))) "'")
     . font-lock-string-face))
  "Font-lock rules used in `ryzenbit-mode'.")

(defconst ryzenbit-imenu-generic-expression
  `(("Functions" ,(concat "^[[:space:]]*" ryzenbit--declaration-re) 1)
    ("Types" ,(concat "^[[:space:]]*" ryzenbit--type-declaration-re) 1))
  "Imenu expressions for Ryzenbit declarations.")

(defun ryzenbit--line-opens-block-p ()
  "Return non-nil if the current line ends with an unclosed `{`."
  (let ((line (buffer-substring-no-properties
               (line-beginning-position) (line-end-position))))
    (setq line (replace-regexp-in-string (rx "//" (* nonl) line-end) "" line))
    (string-match-p (rx "{" (* (any " \t")) line-end) line)))

(defun ryzenbit-indent-line ()
  "Indent the current Ryzenbit line using brace-delimited blocks."
  (interactive)
  (let ((column (- (current-column) (current-indentation)))
        (closing (save-excursion
                   (beginning-of-line)
                   (looking-at-p (rx (* blank) (or "}" ")" "]" "else")))))
        (indent 0))
    (save-excursion
      (beginning-of-line)
      (when (and (= (forward-line -1) 0)
                 (not (looking-at-p (rx (* blank) line-end))))
        (setq indent (current-indentation))
        (when (ryzenbit--line-opens-block-p)
          (setq indent (+ indent ryzenbit-indent-offset)))))
    (when closing
      (setq indent (max 0 (- indent ryzenbit-indent-offset))))
    (indent-line-to indent)
    (when (> column 0)
      (move-to-column (+ indent column)))))

(define-derived-mode ryzenbit-mode prog-mode "Ryzenbit"
  "Major mode for editing Ryzenbit source files."
  :group 'ryzenbit
  :syntax-table ryzenbit-mode-syntax-table
  (setq-local comment-start "// ")
  (setq-local comment-end "")
  (setq-local comment-start-skip (rx "/" (+ "/") (* blank)))
  (setq-local font-lock-defaults '(ryzenbit-font-lock-keywords))
  (setq-local imenu-generic-expression ryzenbit-imenu-generic-expression)
  (setq-local indent-line-function #'ryzenbit-indent-line)
  (setq-local indent-tabs-mode nil)
  (when buffer-file-name
    (setq-local compile-command
                (format "rz check %s"
                        (shell-quote-argument buffer-file-name)))))

(defun my/ryzenbit-project (dir)
  "Use the nearest Cargo workspace, or Git root, as a Ryzenbit project."
  (when (derived-mode-p 'ryzenbit-mode)
    (when-let* ((root (or (locate-dominating-file dir "Cargo.toml")
                          (locate-dominating-file dir ".git"))))
      (cons 'transient
            (file-name-as-directory (expand-file-name root))))))

(defun my/ryzenbit-eglot-command (&optional _interactive _project)
  "Return the Ryzenbit language-server command for Eglot."
  (when-let* ((binary (executable-find (car ryzenbit-lsp-command))))
    (list binary "lsp")))

(defun my/ryzenbit-maybe-eglot-ensure ()
  "Start Eglot when the Ryzenbit language server is available."
  (when (my/ryzenbit-eglot-command)
    (my/eglot-ensure-idle)))

(add-to-list 'auto-mode-alist '("\\.rz\\'" . ryzenbit-mode))
(add-hook 'project-find-functions #'my/ryzenbit-project)
(add-hook 'ryzenbit-mode-hook #'my/ryzenbit-maybe-eglot-ensure)

(with-eval-after-load 'eglot
  (add-to-list 'eglot-server-programs
               `(ryzenbit-mode . ,ryzenbit-lsp-command)))

(provide 'ryzenbit)
;;; ryzenbit.el ends here
