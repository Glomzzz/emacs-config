;;; haskell.el --- Haskell language support -*- lexical-binding: t; -*-

(require 'packages)

(defvar eglot-server-programs)
(defvar apheleia-formatters)
(defvar apheleia-mode-alist)

;; Haskell does not have a built-in Tree-sitter mode in this Emacs build;
;; `haskell-mode' provides the editing mode and project integration.
(packages/declare 'haskell-mode)
(use-package haskell-mode
  :ensure nil
  :mode (("\\.hs\\'" . haskell-mode)
         ("\\.lhs\\'" . literate-haskell-mode)
         ("\\.hsc\\'" . haskell-mode))
  :hook ((haskell-mode . eglot-ensure)
         (haskell-mode . format/mode-maybe)
         (literate-haskell-mode . eglot-ensure)
         (literate-haskell-mode . format/mode-maybe)))

(with-eval-after-load 'eglot
  ;; HLS selects the GHC version and project component from the current
  ;; Cabal or Stack project.
  (add-to-list 'eglot-server-programs
               '(haskell-mode . ("haskell-language-server-wrapper" "--lsp")))
  (add-to-list 'eglot-server-programs
               '(literate-haskell-mode . ("haskell-language-server-wrapper" "--lsp"))))

(defun haskell/configure-apheleia ()
  "Use Ormolu for Haskell buffers when Eglot is not formatting them."
  (setf (alist-get 'ormolu apheleia-formatters)
        '("ormolu" "-m" "stdout" "--stdin-input-file" filepath))
  (setf (alist-get 'haskell-mode apheleia-mode-alist) 'ormolu)
  (setf (alist-get 'literate-haskell-mode apheleia-mode-alist) 'ormolu))

;; Haskell uses Apheleia/Ormolu for asynchronous save-time formatting.

(with-eval-after-load 'apheleia
  (haskell/configure-apheleia))

;;; haskell.el ends here
