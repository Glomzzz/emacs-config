;;; koka.el --- Koka editing and language-server support -*- lexical-binding: t; -*-

;;; Commentary:

;; Provides a local Koka major mode and connects it to the language server
;; bundled with the Koka compiler.

;;; Code:

(require 'rx)
(require 'project)
(require 'fileloop)

(defgroup koka nil
  "Editing support for the Koka programming language."
  :group 'languages
  :link '(url-link "https://koka-lang.github.io/koka/doc/index.html"))

(defcustom koka-indent-offset 2
  "Number of spaces used for each Koka indentation level."
  :type 'integer
  :safe #'integerp
  :group 'koka)

(defvar koka-mode-syntax-table
  (let ((table (make-syntax-table)))
    (dolist (pair '((?\( . "()") (?\) . ")(")
                    (?\[ . "(]") (?\] . ")[")
                    (?{ . "(}") (?} . "){")))
      (modify-syntax-entry (car pair) (cdr pair) table))
    (dolist (char '(?$ ?% ?& ?+ ?~ ?! ?^ ?# ?= ?. ?: ?- ?? ?< ?> ?| ?@))
      (modify-syntax-entry char "." table))
    ;; Hyphens, apostrophes, and at signs are valid inside Koka identifiers.
    (modify-syntax-entry ?- "_" table)
    (modify-syntax-entry ?' "_" table)
    (modify-syntax-entry ?@ "_" table)
    (modify-syntax-entry ?_ "_" table)
    (modify-syntax-entry ?\" "\"" table)
    (modify-syntax-entry ?\\ "\\" table)
    ;; Koka supports // comments and nested /* ... */ comments.
    (modify-syntax-entry ?/ ". 124b" table)
    (modify-syntax-entry ?* ". 23n" table)
    (modify-syntax-entry ?\n "> b" table)
    table)
  "Syntax table used in `koka-mode'.")

(defconst koka--keywords
  '("abstract" "alias" "ambient" "as" "behind" "break" "co" "con"
    "continue" "ctl" "ctx" "effect" "elif" "else" "exists" "extend"
    "extern" "fbip" "final" "finally" "fip" "fn" "forall" "fun"
    "handle" "handler" "hiding" "hole" "if" "import" "in" "include"
    "infix" "infixl" "infixr" "initially" "inline" "interface" "lazy"
    "linear" "mask" "match" "module" "named" "noinline" "open"
    "override" "pub" "qualified" "raw" "rec" "reference" "ret" "return"
    "scoped" "some" "struct" "tail" "then" "type" "unsafe" "val"
    "value" "var" "when" "where" "with"))

(defconst koka--builtins
  '("resume" "resume-shallow" "rcontext"))

(defconst koka--core-types
  '("any" "bool" "cfield" "char" "ctail" "double" "ediv" "either"
    "float32" "global" "hdiv" "int" "int32" "int64" "local-var" "maybe"
    "optional" "order" "ref" "reuse" "ssize_t" "string" "uint8" "vector"
    "void"))

(defconst koka--identifier-re
  (rx (or (seq (? "@") lower (* (any alnum "_@-")) (* "'"))
          (seq "(" (+ (any "$%&*+@!/\\^~=.:-?|<>")) ")")))
  "Regexp matching an unqualified Koka identifier or named operator.")

(defconst koka--declaration-re
  (rx symbol-start
      (or "fun" "ctl" "ret" "extern" "val" "var")
      symbol-end
      (+ space)
      (? (seq (+ (any alnum "_@-")) "/"))
      (group (regexp koka--identifier-re)))
  "Regexp matching a value declaration and capturing its name.")

(defconst koka--type-declaration-re
  (rx symbol-start
      (or "alias" "effect" "struct" "type")
      symbol-end
      (+ space)
      (? (seq (+ (any alnum "_@-")) "/"))
      (group (? "@") lower (* (any alnum "_@-")) (* "'")))
  "Regexp matching a type declaration and capturing its name.")

(defconst koka--module-re
  (rx symbol-start
      (or "import" "module")
      symbol-end
      (+ space)
      (? (seq "interface" (+ space)))
      (group lower (* (any alnum "_@/-"))))
  "Regexp matching a module name after an import or module declaration.")

(defconst koka-font-lock-keywords
  `((,koka--declaration-re 1 font-lock-function-name-face)
    (,koka--type-declaration-re 1 font-lock-type-face)
    (,koka--module-re 1 font-lock-constant-face)
    (,(regexp-opt koka--keywords 'symbols) . font-lock-keyword-face)
    (,(regexp-opt koka--builtins 'symbols) . font-lock-builtin-face)
    (,(regexp-opt koka--core-types 'symbols) . font-lock-type-face)
    (,(rx symbol-start (or "False" "True") symbol-end)
     . font-lock-constant-face)
    (,(rx symbol-start upper (* (any alnum "_@-")) (* "'") symbol-end)
     . font-lock-type-face)
    (,(rx symbol-start
          (or (seq "0" (any "xX") (+ (any xdigit "_")))
              (seq "0" (any "bB") (+ (any "01_")))
              (seq (+ digit) (* (any digit "_"))
                   (? (seq "." (+ digit) (* (any digit "_"))))
                   (? (seq (any "eE") (? (any "+-")) (+ digit)))))
          symbol-end)
     . font-lock-constant-face)
    (,(rx "'" (or (seq "\\" nonl) (not (any "'\\\n"))) "'")
     . font-lock-string-face)
    (,(rx line-start (* blank) "#" (* nonl)) . font-lock-preprocessor-face))
  "Font-lock rules used in `koka-mode'.")

(defconst koka-imenu-generic-expression
  `(("Functions" ,(concat "^[[:space:]]*" koka--declaration-re) 1)
    ("Types" ,(concat "^[[:space:]]*" koka--type-declaration-re) 1))
  "Imenu expressions for Koka declarations.")

(defun koka--previous-code-line ()
  "Move to the previous nonblank line and return non-nil when one exists."
  (let ((found nil))
    (while (and (not found) (= (forward-line -1) 0))
      (unless (looking-at-p (rx (* blank) line-end))
        (setq found t)))
    found))

(defun koka--line-opens-layout-p ()
  "Return non-nil if the current line opens a nested Koka layout block."
  (let ((line (buffer-substring-no-properties
               (line-beginning-position) (line-end-position))))
    (setq line (replace-regexp-in-string (rx "//" (* nonl) line-end) "" line))
    (or (string-match-p (rx (any "([{") (* blank) string-end) line)
        (string-match-p
         (rx symbol-start
             (or "effect" "handler" "match" "struct" "type")
             symbol-end (* nonl) string-end)
         line)
        (string-match-p
         (rx symbol-start (or "else" "then") symbol-end (* blank) string-end)
         line)
        (string-match-p
         (rx symbol-start (or "ctl" "fun") symbol-end
             (* nonl) ")" (* blank) (? (seq ":" (* nonl))) string-end)
         line)
        (string-match-p
         (rx symbol-start "fn" symbol-end
             (* nonl) ")" (* blank) (? (seq ":" (* nonl))) string-end)
         line))))

(defun koka-indent-line ()
  "Indent the current Koka line using layout and delimiter cues."
  (interactive)
  (let ((column (- (current-column) (current-indentation)))
        (closing (save-excursion
                   (beginning-of-line)
                   (looking-at-p
                    (rx (* blank) (or "else" (any ")}]"))))))
        (indent 0))
    (save-excursion
      (beginning-of-line)
      (when (koka--previous-code-line)
        (setq indent (current-indentation))
        (when (koka--line-opens-layout-p)
          (setq indent (+ indent koka-indent-offset)))))
    (when closing
      (setq indent (max 0 (- indent koka-indent-offset))))
    (indent-line-to indent)
    (when (> column 0)
      (move-to-column (+ indent column)))))

(define-derived-mode koka-mode prog-mode "Koka"
  "Major mode for editing Koka source files."
  :group 'koka
  :syntax-table koka-mode-syntax-table
  (setq-local comment-start "// ")
  (setq-local comment-end "")
  (setq-local comment-start-skip (rx "/" (+ "/") (* blank)))
  (setq-local font-lock-defaults '(koka-font-lock-keywords))
  (setq-local imenu-generic-expression koka-imenu-generic-expression)
  (setq-local indent-line-function #'koka-indent-line)
  (setq-local indent-tabs-mode nil)
  (when buffer-file-name
    (setq-local compile-command
                (format "koka %s"
                        (shell-quote-argument buffer-file-name)))))

(defun my/koka-project (dir)
  "Use the nearest Git root, or DIR, as a transient Koka project."
  (when (derived-mode-p 'koka-mode)
    (cons 'transient
          (file-name-as-directory
           (expand-file-name
            (or (locate-dominating-file dir ".git") dir))))))

(defun my/koka-eglot-command (&optional _interactive _project)
  "Return the installed Koka language-server command for Eglot."
  (when-let ((binary (executable-find "koka")))
    (list binary "--language-server" "--lsstdio")))

(defun my/koka-maybe-eglot-ensure ()
  "Start Eglot when the Koka compiler and language server are available."
  (when (my/koka-eglot-command)
    (eglot-ensure)))

(defconst koka--renameable-identifier-re
  (rx string-start
      (? "@") (or alpha "_") (* (any alnum "_@-")) (* "'")
      string-end)
  "Regexp matching a Koka identifier supported by project rename.")

(defvar koka-rename-history nil
  "Minibuffer history for Koka rename targets.")

(defun my/koka-symbol-at-point ()
  "Return the renameable Koka symbol at point, without text properties."
  (when-let ((symbol (thing-at-point 'symbol t)))
    (and (string-match-p koka--renameable-identifier-re symbol)
         symbol)))

(defun my/koka-project-files (project)
  "Return Koka source files belonging to PROJECT."
  (let (files)
    (dolist (file (project-files project) (nreverse files))
      (when (member (file-name-extension file) '("kk"))
        (push file files)))))

(defun my/koka-project-rename (old-name new-name)
  "Query-replace OLD-NAME with NEW-NAME across the Koka project."
  (interactive
   (let ((old-name (my/koka-symbol-at-point)))
     (unless old-name
       (user-error "No renameable Koka identifier at point"))
     (list old-name
           (read-string (format "Rename `%s' to: " old-name)
                        old-name 'koka-rename-history old-name))))
  (unless (and (stringp old-name)
               (string-match-p koka--renameable-identifier-re old-name))
    (user-error "Invalid Koka identifier: %s" old-name))
  (unless (and (stringp new-name)
               (string-match-p koka--renameable-identifier-re new-name))
    (user-error "Invalid Koka identifier: %s" new-name))
  (when (string-equal old-name new-name)
    (user-error "The new name is unchanged"))
  (let ((project (project-current t)))
    (unless project
      (user-error "No Koka project found"))
    (let ((files (my/koka-project-files project)))
      (unless files
        (user-error "No Koka files found in project %s"
                    (project-root project)))
      (fileloop-initialize-replace
       (concat "\\_<" (regexp-quote old-name) "\\_>")
       new-name files nil)
      (fileloop-continue))))

(defun my/koka-rename ()
  "Rename at point with Eglot, falling back when Koka lacks LSP rename."
  (interactive)
  (if (and (bound-and-true-p eglot-managed-mode)
           (eglot-server-capable :renameProvider))
      (call-interactively #'eglot-rename)
    (call-interactively #'my/koka-project-rename)))

(define-key koka-mode-map [remap eglot-rename] #'my/koka-rename)

(add-to-list 'auto-mode-alist '("\\.kk\\'" . koka-mode))
(add-hook 'project-find-functions #'my/koka-project)
(add-hook 'koka-mode-hook #'my/koka-maybe-eglot-ensure)

(with-eval-after-load 'eglot
  (add-to-list 'eglot-server-programs
               (cons 'koka-mode #'my/koka-eglot-command)))

;;; koka.el ends here
