;;; flix-mode.el --- Editing support for the Flix language -*- lexical-binding: t; -*-

;;; Commentary:

;; Provides a dependency-free fallback mode and an optional tree-sitter mode
;; for Flix.  File associations, project discovery, and language-server setup
;; intentionally belong in the surrounding configuration.

;;; Code:

(require 'imenu)
(require 'rx)
(require 'treesit nil t)

(defgroup flix nil
  "Editing support for the Flix programming language."
  :group 'languages
  :link '(url-link "https://flix.dev/"))

(defcustom flix-indent-offset 4
  "Number of spaces used for each Flix indentation level."
  :type 'integer
  :safe #'integerp
  :group 'flix)

(defvar flix-mode-syntax-table
  (let ((table (make-syntax-table)))
    (dolist (pair '((?\( . "()") (?\) . ")(")
                    (?\[ . "(]") (?\] . ")[")
                    (?{ . "(}") (?} . "){")))
      (modify-syntax-entry (car pair) (cdr pair) table))
    (dolist (char '(?+ ?- ?= ?% ?& ?| ?^ ?~ ?< ?> ?@ ?# ?: ?? ?. ?, ?\;))
      (modify-syntax-entry char "." table))
    ;; These characters can occur inside Flix identifiers.
    (modify-syntax-entry ?_ "_" table)
    (modify-syntax-entry ?$ "_" table)
    (modify-syntax-entry ?! "_" table)
    (modify-syntax-entry ?\" "\"" table)
    (modify-syntax-entry ?' "\"" table)
    (modify-syntax-entry ?\\ "\\" table)
    ;; Flix has // comments and arbitrarily nested /* ... */ comments.
    (modify-syntax-entry ?/ ". 124b" table)
    (modify-syntax-entry ?* ". 23n" table)
    (modify-syntax-entry ?\n "> b" table)
    (modify-syntax-entry ?\^m "> b" table)
    table)
  "Syntax table shared by `flix-mode' and `flix-ts-mode'.")

(defconst flix--keywords
  '("alias" "as" "case" "catch" "checked_cast" "checked_ecast"
    "choose" "choose*" "def" "discard" "eff" "else" "ematch" "enum"
    "fix" "forA" "forM" "forall" "force" "foreach" "from" "handler"
    "if" "import" "inject" "instance" "instanceof" "into" "law" "lazy"
    "let" "match" "mod" "new" "not" "open_variant" "open_variant_as"
    "par" "pquery" "project" "psolve" "query" "redef" "region"
    "restrictable" "run" "rvadd" "rvand" "rvnot" "rvsub" "select"
    "solve" "spawn" "struct" "super" "throw" "trait" "try" "type"
    "unchecked_cast" "unsafe" "use" "where" "with" "xor" "xvar"
    "yield" "and" "or"))

(defconst flix--modifiers '("lawful" "mut" "pub" "sealed"))

(defconst flix--builtin-types
  '("Array" "BigDecimal" "BigInt" "Bool" "Char" "Float32" "Float64"
    "Int8" "Int16" "Int32" "Int64" "List" "Map" "Never" "Null"
    "Option" "Result" "Set" "Static" "String" "Unit" "Univ" "Vector"))

(defconst flix--lower-name-re
  "\\(?:\\$[A-Za-z]\\|_?[a-z]\\)[A-Za-z0-9_!$]*"
  "Regexp matching a lower-case Flix name.")

(defconst flix--upper-name-re
  "_?[A-Z][A-Za-z0-9_!$]*"
  "Regexp matching an upper-case Flix name.")

(defconst flix--operator-name-re
  "\\(?:_[+*<>=!&|^$-]+\\|[+*<>=!&|^$-]\\{2,\\}\\)"
  "Regexp matching an ASCII user-defined Flix operator name.")

(defconst flix--function-name-re
  (concat "\\(?:" flix--lower-name-re "\\|" flix--operator-name-re "\\)")
  "Regexp matching an ASCII Flix function name.")

(defconst flix--declaration-prefix-re
  (concat "^[[:space:]]*"
          "\\(?:@[A-Za-z]+[[:space:]]+\\)*"
          "\\(?:" (regexp-opt flix--modifiers) "[[:space:]]+\\)*")
  "Regexp matching indentation, annotations, and declaration modifiers.")

(defconst flix--function-declaration-re
  (concat flix--declaration-prefix-re
          "\\(?:def\\|redef\\|law\\)[[:space:]]+"
          "\\(" flix--function-name-re "\\)")
  "Regexp matching a function-like declaration and capturing its name.")

(defconst flix--type-declaration-re
  (concat flix--declaration-prefix-re
          "\\(?:restrictable[[:space:]]+enum\\|type[[:space:]]+alias"
          "\\|enum\\|struct\\|trait\\|eff\\)[[:space:]]+"
          "\\(" flix--upper-name-re "\\)")
  "Regexp matching a type declaration and capturing its name.")

(defconst flix--module-declaration-re
  (concat flix--declaration-prefix-re "mod[[:space:]]+"
          "\\(" flix--upper-name-re
          "\\(?:\\." flix--upper-name-re "\\)*\\)")
  "Regexp matching a module declaration and capturing its name.")

(defconst flix--instance-declaration-re
  (concat flix--declaration-prefix-re "instance[[:space:]]+"
          "\\(" flix--upper-name-re
          "\\(?:\\." flix--upper-name-re "\\)*\\)")
  "Regexp matching an instance declaration and capturing its trait name.")

(defconst flix--number-re
  (rx symbol-start
      (or (seq "0x" (+ xdigit) (* (seq "_" (+ xdigit)))
               (? (or "i8" "i16" "i32" "i64" "ii")))
          (seq (+ digit) (* (seq "_" (+ digit)))
               (or (seq "." (+ digit) (* (seq "_" (+ digit)))
                        (? (seq "e" (? (any "+-")) (+ digit)
                                (* (seq "_" (+ digit)))
                                (? (seq "." (+ digit)))))
                        (? (or "f32" "f64" "ff")))
                   (seq "e" (? (any "+-")) (+ digit)
                        (* (seq "_" (+ digit)))
                        (? (seq "." (+ digit)))
                        (? (or "f32" "f64" "ff")))
                   (? (or "i8" "i16" "i32" "i64" "ii")))))
      symbol-end)
  "Regexp matching a Flix numeric literal.")

(defconst flix-font-lock-keywords
  `((,flix--module-declaration-re 1 font-lock-constant-face)
    (,flix--function-declaration-re 1 font-lock-function-name-face)
    (,flix--type-declaration-re 1 font-lock-type-face)
    (,flix--instance-declaration-re 1 font-lock-type-face)
    (,(rx symbol-start "case" symbol-end (+ space)
          (group (regexp flix--upper-name-re)))
     1 font-lock-constant-face)
    (,(rx symbol-start "let" symbol-end (+ space)
          (group (regexp flix--lower-name-re)))
     1 font-lock-variable-name-face)
    (,(rx (group "@" (+ alpha))) 1 font-lock-preprocessor-face)
    (,(rx "%%" (* (any "A-Z0-9_")) "%%") . font-lock-builtin-face)
    (,(rx (or "???"
              (seq "?" alpha (* (any alnum "_!$")))
              (seq (? "_") alpha (* (any alnum "_!$")) "?")))
     . font-lock-warning-face)
    (,(regexp-opt flix--modifiers 'symbols) . font-lock-keyword-face)
    (,(regexp-opt flix--keywords 'symbols) . font-lock-keyword-face)
    (,(regexp-opt flix--builtin-types 'symbols) . font-lock-type-face)
    (,(rx symbol-start (or "false" "null" "true") symbol-end)
     . font-lock-constant-face)
    (,flix--number-re 0 'font-lock-number-face)
    (,(rx symbol-start (group (regexp flix--lower-name-re))
          (* blank) "(")
     1 'font-lock-function-call-face)
    (,(rx (or "." "#" "->")
          (group (regexp flix--lower-name-re)) symbol-end)
     1 'font-lock-property-use-face)
    (,(rx (or ":::" "::" "<=>" "<+>" "=>" "->" "<-" ":-"
              "==" "!=" "<=" ">=" "=" "+" "-" "*" "/" "<"
              ">" "~" "\\" "@" "#" "|"))
     0 'font-lock-operator-face))
  "Font-lock rules used by the fallback `flix-mode'.")

(defconst flix-imenu-generic-expression
  `(("Modules" ,flix--module-declaration-re 1)
    ("Functions" ,flix--function-declaration-re 1)
    ("Types" ,flix--type-declaration-re 1)
    ("Instances" ,flix--instance-declaration-re 1))
  "Imenu expressions for Flix declarations.")

(defun flix--syntactic-face (state)
  "Return the appropriate syntactic face for parse STATE."
  (cond
   ((nth 3 state) 'font-lock-string-face)
   ((and (nth 4 state)
         (save-excursion
           (goto-char (nth 8 state))
           (looking-at-p (rx "///" (or line-end (not (any "/")))))))
    'font-lock-doc-face)
   ((nth 4 state) 'font-lock-comment-face)))

(defun flix--line-has-code-p ()
  "Return non-nil when the current line has non-comment code."
  (let ((end (line-end-position))
        found)
    (beginning-of-line)
    (while (and (not found) (< (point) end))
      (skip-chars-forward " \t" end)
      (cond
       ((>= (point) end))
       ((nth 4 (syntax-ppss))
        (condition-case nil
            (forward-comment 1)
          (error (goto-char end))))
       (t (setq found t))))
    found))

(defun flix--previous-code-line ()
  "Move to the previous nonblank line containing code.
Return non-nil if such a line exists."
  (let (found)
    (while (and (not found) (= (forward-line -1) 0))
      (setq found (flix--line-has-code-p)))
    found))

(defun flix--line-code-end ()
  "Return the end position of code on the current line."
  (let ((end (line-end-position)))
    (save-excursion
      (goto-char end)
      (when-let ((start (nth 8 (syntax-ppss))))
        (when (nth 4 (syntax-ppss))
          (setq end start)))
      (goto-char end)
      (skip-chars-backward " \t" (line-beginning-position))
      (point))))

(defun flix--line-opens-continuation-p ()
  "Return non-nil when code on the current line continues on the next."
  (let ((end (flix--line-code-end)))
    (save-excursion
      (goto-char end)
      (or (looking-back (rx (or "=>" "->" "<-" ":-" "=" "," ":"
                                "+" "-" "*" "/" "|" "&"))
                        (line-beginning-position))
          (looking-back (rx symbol-start (or "else" "with" "yield")
                            symbol-end)
                        (line-beginning-position))))))

(defun flix--current-line-kind ()
  "Classify the current line for fallback indentation."
  (save-excursion
    (beginning-of-line)
    (cond
     ((looking-at-p (rx (* blank) (any ")}]"))) 'closing)
     ((looking-at-p (rx (* blank) (or "case" "catch") symbol-end)) 'rule)
     ((looking-at-p
       (concat flix--declaration-prefix-re
               (regexp-opt
                '("def" "eff" "enum" "instance" "law" "mod" "redef"
                  "restrictable" "struct" "trait" "type")
                'symbols)))
      'declaration))))

(defun flix-indent-line ()
  "Indent the current Flix line using delimiters and expression cues."
  (interactive)
  (let* ((distance (max 0 (- (current-column) (current-indentation))))
         (bol (line-beginning-position))
         (state (syntax-ppss bol))
         (open (nth 1 state))
         (kind (flix--current-line-kind))
         (indent (current-indentation))
         previous-indent
         previous-opens)
    (unless (nth 4 state)
      (save-excursion
        (goto-char bol)
        (when (flix--previous-code-line)
          (setq previous-indent (current-indentation)
                previous-opens (flix--line-opens-continuation-p))))
      (setq indent (or previous-indent 0))
      (cond
       ((eq kind 'closing)
        (when open
          (setq indent (save-excursion
                         (goto-char open)
                         (current-indentation)))))
       ((and open (eq kind 'rule))
        (setq indent (+ (save-excursion
                          (goto-char open)
                          (current-indentation))
                        flix-indent-offset)))
       (previous-opens
        (setq indent (+ indent flix-indent-offset)))
       ((and (eq kind 'declaration) (not open))
        (setq indent 0))
       (open
        (setq indent
              (max indent
                   (+ (save-excursion
                        (goto-char open)
                        (current-indentation))
                      flix-indent-offset))))))
    (indent-line-to indent)
    (when (> distance 0)
      (move-to-column (+ indent distance)))))

;;;###autoload
(define-derived-mode flix-mode prog-mode "Flix"
  "Major mode for editing Flix source without tree-sitter."
  :group 'flix
  :syntax-table flix-mode-syntax-table
  (setq-local comment-start "// ")
  (setq-local comment-end "")
  (setq-local comment-start-skip (rx (or (seq "/" (+ "/")) "/*") (* blank)))
  (setq-local comment-end-skip (rx (* blank) (or line-end "*/")))
  (setq-local comment-use-syntax t)
  (setq-local font-lock-defaults '(flix-font-lock-keywords))
  (setq-local font-lock-syntactic-face-function #'flix--syntactic-face)
  (setq-local imenu-generic-expression flix-imenu-generic-expression)
  (setq-local indent-line-function #'flix-indent-line)
  (setq-local indent-tabs-mode nil)
  (setq-local parse-sexp-ignore-comments t)
  (setq-local electric-indent-chars
              (append "{}[]():;," electric-indent-chars)))

(defun flix-treesit-ready-p ()
  "Return non-nil when the Flix tree-sitter grammar can be used."
  (and (featurep 'treesit)
       (treesit-ready-p 'flix t)))

(when (featurep 'treesit)
  (defun flix-ts-mode--fontify-interpolation (node override start end &rest _)
    "Fontify literal portions of interpolated string NODE.
OVERRIDE, START, and END have the meaning documented by
`treesit-font-lock-rules'."
    (let ((cursor (treesit-node-start node)))
      (dotimes (index (treesit-node-child-count node t))
        (let* ((child (treesit-node-child node index t))
               (child-start (treesit-node-start child)))
          (when (< cursor child-start)
            (treesit-fontify-with-override
             cursor child-start 'font-lock-string-face override start end))
          (setq cursor (treesit-node-end child))))
      (when (< cursor (treesit-node-end node))
        (treesit-fontify-with-override
         cursor (treesit-node-end node) 'font-lock-string-face
         override start end))))

  (defvar flix-ts-mode--font-lock-settings
    (treesit-font-lock-rules
     :default-language 'flix
     :feature 'comment
     '((line_comment) @font-lock-comment-face
       (block_comment) @font-lock-comment-face
       (doc_comment) @font-lock-doc-face)

     :feature 'definition
     '((module_declaration name: (_) @font-lock-constant-face)
       (function_declaration name: (_) @font-lock-function-name-face)
       (signature_declaration name: (_) @font-lock-function-name-face)
       (operation_declaration name: (_) @font-lock-function-name-face)
       (law_declaration name: (_) @font-lock-function-name-face)
       (local_def_expression name: (_) @font-lock-function-name-face)
       (jvm_method name: (_) @font-lock-function-name-face)
       (handler_rule name: (_) @font-lock-function-name-face)
       (enum_declaration name: (_) @font-lock-type-face)
       (struct_declaration name: (_) @font-lock-type-face)
       (trait_declaration name: (_) @font-lock-type-face)
       (effect_declaration name: (_) @font-lock-type-face)
       (type_alias_declaration name: (_) @font-lock-type-face)
       (associated_type_signature name: (_) @font-lock-type-face)
       (associated_type_definition name: (_) @font-lock-type-face)
       (instance_declaration name: (_) @font-lock-type-face)
       (enum_case name: (_) @font-lock-constant-face)
       (struct_field name: (_) @font-lock-property-name-face)
       (record_type_field name: (_) @font-lock-property-name-face)
       (parameter name: (_) @font-lock-variable-name-face)
       (type_parameter name: (_) @font-lock-type-face))

     :feature 'string
     '((string) @font-lock-string-face
       (string_interpolation) @flix-ts-mode--fontify-interpolation
       (char) @font-lock-string-face
       (regex) @font-lock-regexp-face)

     :feature 'keyword
     '(["mod" "use" "import" "def" "redef" "law" "lazy" "force"
        "enum" "case" "struct" "trait" "instance" "eff" "type" "alias"
        "restrictable" "forall" "where" "with" "let" "region" "xvar"
        "open_variant" "open_variant_as" "new" "super" "discard" "unsafe"
        "instanceof" "as" "checked_cast" "checked_ecast" "unchecked_cast"
        "if" "else" "match" "ematch" "choose" "choose*" "foreach" "forM"
        "forA" "yield" "try" "catch" "throw" "run" "handler" "spawn"
        "par" "select" "query" "solve" "psolve" "pquery" "inject" "into"
        "project" "from" "fix"] @font-lock-keyword-face
       (modifier) @font-lock-keyword-face)

     :feature 'annotation
     '((annotation) @font-lock-preprocessor-face)

     :feature 'builtin
     '((intrinsic) @font-lock-builtin-face
       ["Array#" "Vector#" "List#" "Set#" "Map#"] @font-lock-builtin-face)

     :feature 'constant
     '([(boolean) (null) (static_expression)] @font-lock-constant-face
       [(hole_anonymous) (hole_named) (hole_variable)] @font-lock-warning-face
       (wildcard) @font-lock-constant-face
       (debug_prefix) @font-lock-preprocessor-face)

     :feature 'number
     '([(integer) (float)] @font-lock-number-face)

     :feature 'type
     '((type_reference (name_upper) @font-lock-type-face)
       (type_variable) @font-lock-type-face
       [(static_type) (type_constant)] @font-lock-type-face
       (kind (name_upper) @font-lock-type-face)
       (tag_pattern
        (qualified_name (name_upper) @font-lock-type-face))
       (ext_tag_expression (name_upper) @font-lock-type-face)
       (trait_constraint (qualified_name (name_upper) @font-lock-type-face))
       (derivations (qualified_name (name_upper) @font-lock-type-face)))

     :feature 'function
     '((apply_expression
        (qualified_name (name_lower) @font-lock-function-call-face))
       (apply_expression
        (qualified_name (name_upper) @font-lock-type-face))
       (invoke_method (name_lower) @font-lock-function-call-face)
       (predicate_head (name_upper) @font-lock-function-call-face)
       (predicate_atom (name_upper) @font-lock-function-call-face)
       (predicate_param (name_upper) @font-lock-function-call-face)
       (schema_term
        (qualified_name (name_upper) @font-lock-function-call-face)))

     :feature 'property
     '((record_operation name: (_) @font-lock-property-name-face)
       (record_pattern_field name: (_) @font-lock-property-name-face)
       (struct_field_init name: (_) @font-lock-property-name-face)
       (record_select (name_lower) @font-lock-property-use-face)
       (struct_get (name_lower) @font-lock-property-use-face)
       (struct_put (name_lower) @font-lock-property-use-face)
       (get_field (name_lower) @font-lock-property-use-face))

     :feature 'operator
     '((generic_operator) @font-lock-operator-face
       (binary_expression operator: _ @font-lock-operator-face)
       (unary_expression operator: _ @font-lock-operator-face)
       (binary_type operator: _ @font-lock-operator-face)
       (unary_type operator: _ @font-lock-operator-face)
       ["=" ":" "::" ":::" "<-" ":-" "@" "\\" "|" "#" "~" "/"]
       @font-lock-operator-face)

     :feature 'bracket
     '(["(" ")" "[" "]" "{" "}" "#{" "#(" "#|" "|#"]
       @font-lock-bracket-face)

     :feature 'delimiter
     '(["," ";"] @font-lock-delimiter-face
       "=>" @font-lock-misc-punctuation-face)

     :feature 'variable
     :override 'keep
     '([(name_lower) (name_math)] @font-lock-variable-use-face)

     :feature 'error
     '((ERROR) @font-lock-warning-face))
    "Tree-sitter font-lock settings for `flix-ts-mode'.")

  (defconst flix-ts-mode--container-node-re
    (rx string-start
        (or "argument_list" "array_literal" "block" "case_body"
            "catch_body" "effect_body" "effect_set_type" "enum_body"
            "ext_match_body" "extensible_type" "fixpoint_constraint_set"
            "for_fragments" "handler_body" "instance_body" "list_literal"
            "map_literal" "match_body" "parameter_list" "par_fragments"
            "paren_expression" "record_expression" "record_pattern"
            "record_row_type" "record_type" "schema_row_type" "schema_type"
            "select_expression" "set_literal" "trait_body"
            "tuple_expression" "tuple_pattern" "tuple_type"
            "type_argument_list" "type_parameter_list" "use_many"
            "vector_literal")
        string-end)
    "Regexp matching Flix nodes whose contents are indented.")

  (defconst flix-ts-mode--rule-node-re
    (rx string-start
        (or "catch_rule" "ext_match_rule" "handler_rule" "match_rule"
            "select_rule")
        string-end)
    "Regexp matching Flix rule-arm nodes.")

  (defvar flix-ts-mode--indent-rules
    `((flix
       ((parent-is "\\`source_file\\'") column-0 0)
       ((node-is ,(rx string-start (or ")" "]" "}" "|#") string-end))
        parent-bol 0)
       ((field-is "\\`body\\'") parent-bol flix-indent-offset)
       ((parent-is "\\`sequence_expression\\'") parent-bol 0)
       ((parent-is ,flix-ts-mode--rule-node-re) parent-bol flix-indent-offset)
       ((parent-is "\\`module_declaration\\'") parent-bol flix-indent-offset)
       ((parent-is ,flix-ts-mode--container-node-re) parent-bol flix-indent-offset)))
    "Tree-sitter indentation rules for `flix-ts-mode'.")

  (defconst flix-ts-mode--defun-node-re
    (rx string-start
        (or "associated_type_definition" "associated_type_signature"
            "effect_declaration" "enum_declaration" "function_declaration"
            "handler_rule" "instance_declaration" "jvm_method"
            "law_declaration" "local_def_expression" "module_declaration"
            "operation_declaration" "signature_declaration"
            "struct_declaration" "trait_declaration" "type_alias_declaration")
        string-end)
    "Regexp matching navigable Flix declaration nodes.")

  (defun flix-ts-mode--defun-name (node)
    "Return the declared name of Flix syntax NODE, or nil."
    (when-let ((name (treesit-node-child-by-field-name node "name")))
      (treesit-node-text name t)))

  (declare-function flix-ts-mode--defun-name "flix-mode" (node))

  ;;;###autoload
  (define-derived-mode flix-ts-mode flix-mode "Flix[TS]"
    "Major mode for editing Flix source with tree-sitter."
    :group 'flix
    :syntax-table flix-mode-syntax-table
    (unless (flix-treesit-ready-p)
      (user-error "The Flix tree-sitter grammar is not available"))
    (treesit-parser-create 'flix)
    (setq-local treesit-font-lock-settings flix-ts-mode--font-lock-settings)
    (setq-local treesit-font-lock-feature-list
                '((comment definition)
                  (keyword string type)
                  (annotation builtin constant function number property)
                  (bracket delimiter error operator variable)))
    (setq-local treesit-simple-indent-rules flix-ts-mode--indent-rules)
    (setq-local treesit-defun-type-regexp flix-ts-mode--defun-node-re)
    (setq-local treesit-defun-name-function #'flix-ts-mode--defun-name)
    (setq-local treesit-simple-imenu-settings
                '(("Modules" "\\`module_declaration\\'" nil nil)
                  ("Functions"
                   "\\`\\(?:function_declaration\\|handler_rule\\|jvm_method\\|law_declaration\\|local_def_expression\\|operation_declaration\\|signature_declaration\\)\\'"
                   nil nil)
                  ("Types"
                   "\\`\\(?:associated_type_definition\\|associated_type_signature\\|effect_declaration\\|enum_declaration\\|struct_declaration\\|trait_declaration\\|type_alias_declaration\\)\\'"
                   nil nil)
                  ("Instances" "\\`instance_declaration\\'" nil nil)))
    (treesit-major-mode-setup)))

(provide 'flix-mode)

;;; flix-mode.el ends here
