;;; cpp.el --- C++ language support -*- lexical-binding: t; -*-

(require 'packages)

;; c++-mode and c++-ts-mode are built into Emacs, so no package is declared.
;; treesit-auto knows the `cpp' grammar source and remaps c++-mode to
;; c++-ts-mode when the grammar is installed.
(treesit/register-language 'cpp)

;; Eglot is enabled by the language, not by a global prog-mode hook.
(add-hook 'c++-mode-hook #'eglot-ensure)
(add-hook 'c++-ts-mode-hook #'eglot-ensure)

(with-eval-after-load 'eglot
  ;; Keep the server choice deterministic: clangd for both modes.
  (add-to-list 'eglot-server-programs '(c++-mode . ("clangd")))
  (add-to-list 'eglot-server-programs '(c++-ts-mode . ("clangd"))))

(defun cpp/configure-apheleia ()
  "Use clang-format for C++ buffers when Eglot is not formatting them."
  (setf (alist-get 'clang-format apheleia-formatters)
        '("clang-format" "--style=file"))
  (setf (alist-get 'c++-mode apheleia-mode-alist) 'clang-format)
  (setf (alist-get 'c++-ts-mode apheleia-mode-alist) 'clang-format))

(with-eval-after-load 'apheleia
  (cpp/configure-apheleia))

;; Dape already ships a mode-scoped `gdb' configuration for the C++ modes
;; (gdb >= 14.1 is required), so no adapter registration is needed here.

;;; cpp.el ends here
