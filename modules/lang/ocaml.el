;;; ocaml.el --- OCaml editing, projects, Dune, and Eglot -*- lexical-binding: t; -*-

(require 'project)
(require 'seq)

(defvar eglot-server-programs)
(declare-function dune-root "dune" (&optional directory))
(declare-function eglot-ensure "eglot" ())
(declare-function utop-minor-mode "utop" (&optional arg))

(defconst my/ocaml-vc-markers '(".git" ".hg")
  "Version-control markers used as an OCaml project fallback.")

(use-package tuareg
  :mode (("\\.ml\\'" . tuareg-mode)
         ("\\.mli\\'" . tuareg-interface-mode)
         ("\\.mlp\\'" . tuareg-mode)
         ("\\.mll\\'" . tuareg-mode)
         ("\\.eliom\\'" . tuareg-mode)
         ("\\.eliomi\\'" . tuareg-interface-mode)))

(use-package tuareg-menhir
  :ensure nil
  :mode ("\\.mly\\'" . tuareg-menhir-mode))

(use-package dune
  :commands dune-root)

(use-package utop
  :commands utop
  :hook (tuareg-mode . utop-minor-mode)
  :custom
  (utop-command "utop -emacs")
  (utop-edit-command nil))

(defun my/ocaml-source-mode-p ()
  "Return non-nil when the current buffer contains OCaml source code."
  (derived-mode-p 'tuareg-mode 'tuareg-menhir-mode))

(defun my/ocaml-opam-root (dir)
  "Find the nearest opam project root above DIR."
  (locate-dominating-file
   dir
   (lambda (candidate)
     (or (file-regular-p (expand-file-name "opam" candidate))
         (seq-some
          (lambda (manifest)
            (file-regular-p (expand-file-name manifest candidate)))
          (directory-files candidate nil "\\.opam\\'" t))))))

(defun my/ocaml-vc-root (dir)
  "Find the nearest version-control root above DIR."
  (locate-dominating-file
   dir
   (lambda (candidate)
     (seq-some
      (lambda (marker)
        (file-exists-p (expand-file-name marker candidate)))
      my/ocaml-vc-markers))))

(defun my/ocaml-project-root (dir)
  "Find the OCaml project root above DIR, or return DIR."
  (file-name-as-directory
   (expand-file-name
    (or (dune-root dir)
        (my/ocaml-opam-root dir)
        (my/ocaml-vc-root dir)
        dir))))

(defun my/ocaml-project (dir)
  "Return a transient OCaml project rooted above DIR."
  (when (my/ocaml-source-mode-p)
    (cons 'transient (my/ocaml-project-root dir))))

(defun my/ocaml-lsp-server-available-p ()
  "Return non-nil when the OCaml language server is installed."
  (executable-find "ocamllsp"))

(defun my/ocaml-maybe-eglot-ensure ()
  "Start Eglot when the OCaml language server is available."
  (when (my/ocaml-lsp-server-available-p)
    (eglot-ensure)))

(defun my/ocaml-standalone-command ()
  "Return an `ocamlc' command for the current standalone source file."
  (when-let* ((file buffer-file-name)
              (extension (file-name-extension file))
              ((member extension '("ml" "mli")))
              (compiler (executable-find "ocamlc")))
    (let ((output
           (expand-file-name
            (concat (file-name-base file)
                    (if (string-equal extension "mli") ".cmi" ".cmo"))
            temporary-file-directory)))
      (format "%s -c -o %s %s"
              (shell-quote-argument compiler)
              (shell-quote-argument output)
              (shell-quote-argument file)))))

(defun my/ocaml-project-build-command (root)
  "Return the conventional OCaml build command for ROOT."
  (cond
   ((and (executable-find "dune") (dune-root root)) "dune build")
   ((and (executable-find "make")
         (or (file-exists-p (expand-file-name "Makefile" root))
             (file-exists-p (expand-file-name "makefile" root))))
    "make")))

(defun my/ocaml-buffer-setup ()
  "Set OCaml indentation and compilation defaults."
  (setq-local indent-tabs-mode nil)
  (let* ((root (my/ocaml-project-root default-directory))
         (command (or (my/ocaml-project-build-command root)
                      (my/ocaml-standalone-command))))
    (when command
      (setq-local compile-command
                  (format "cd %s && %s"
                          (shell-quote-argument
                           (directory-file-name root))
                          command)))))

(add-hook 'project-find-functions #'my/ocaml-project)
(add-hook 'tuareg-mode-hook #'my/ocaml-buffer-setup)
(add-hook 'tuareg-mode-hook #'my/ocaml-maybe-eglot-ensure)
(add-hook 'tuareg-menhir-mode-hook #'my/ocaml-buffer-setup)
(add-hook 'tuareg-menhir-mode-hook #'my/ocaml-maybe-eglot-ensure)
(add-hook 'dune-mode-hook #'my/ocaml-buffer-setup)

(with-eval-after-load 'eglot
  (add-to-list
   'eglot-server-programs
   '(((tuareg-menhir-mode :language-id "ocaml")) . ("ocamllsp"))))

;;; ocaml.el ends here
