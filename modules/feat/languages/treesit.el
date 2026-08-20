;;; treesit.el --- Tree-sitter language-support API -*- lexical-binding: t; -*-

(require 'packages)
(require 'treesit)

(defvar treesit/languages nil
  "Tree-sitter languages registered by language-support modules.")

(add-to-list 'treesit-extra-load-path (cache/tree-sitter))

(defun treesit/register-language (language)
  "Register LANGUAGE for automatic Tree-sitter mode selection.

Language modules call this function after configuring their major mode."
  (unless (symbolp language)
    (signal 'wrong-type-argument (list 'symbolp language)))
  (add-to-list 'treesit/languages language t)
  (when (boundp 'treesit-auto-langs)
    (add-to-list 'treesit-auto-langs language t))
  language)

(defun treesit/enable-auto ()
  "Enable automatic Tree-sitter modes for registered languages."
  (when (boundp 'treesit-auto-langs)
    (setq treesit-auto-langs (copy-sequence treesit/languages)))
  (when (fboundp 'global-treesit-auto-mode)
    (global-treesit-auto-mode 1)))

(defun treesit/install (orig lang &optional out-dir)
  "Install LANG in the Tree-sitter cache unless OUT-DIR is custom."
  (let* ((default-dir
          (file-name-as-directory
           (expand-file-name "tree-sitter" user-emacs-directory)))
         (destination
          (if (or (null out-dir)
                  (and (stringp out-dir)
                       (string-equal
                        (file-name-as-directory (expand-file-name out-dir))
                        default-dir)))
              (cache/tree-sitter)
            out-dir)))
    (funcall orig lang destination)))

(unless (advice-member-p #'treesit/install
                         #'treesit-install-language-grammar)
  (advice-add 'treesit-install-language-grammar
              :around
              #'treesit/install))

(packages/declare 'treesit-auto)
(use-package treesit-auto
  :ensure nil
  :custom
  ;; Ask before downloading a grammar the first time a language is opened.
  (treesit-auto-install 'prompt))

;;; treesit.el ends here
