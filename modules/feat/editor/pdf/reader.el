;;; reader.el --- Emacs Reader for PDFs in graphical frames -*- lexical-binding: t; -*-

(require 'packages)
(require 'cl-lib)

;; Emacs Reader renders pages in-process with MuPDF and shows them as Emacs
;; images.  Terminal frames cannot show those images, so they keep DocView,
;; which kitty-graphics can display.  The text layer, selection, search, and
;; history live in the other files of this folder, which load first.

(packages/declare-vc 'reader
                     '(:url "https://codeberg.org/MonadicSheep/emacs-reader"
                       :vc-backend Git))

(defcustom pdf/build-cflags "-O2"
  "Compiler flags for Emacs Reader's dynamic module.
The upstream Makefile sets no optimization level, so this supplies one."
  :type 'string
  :group 'pdf)

(declare-function reader-build "ext:reader")
(declare-function reader-ensure-module "ext:reader")
(declare-function reader-mode "ext:reader")
(declare-function reader--saveplace-find-file "ext:reader")
(declare-function doc-view-mode-maybe "doc-view")

(defun pdf--build-environment (dev lib)
  "Return process environment entries that build the module against MuPDF.
DEV is MuPDF's dev output with the headers; LIB is its library output."
  (list (concat "CPATH=" dev "/include")
        (concat "LIBRARY_PATH=" lib "/lib")
        (format "CFLAGS=%s" pdf/build-cflags)))

(defun pdf--nix-output (output root)
  "Return the store path of nixpkgs' MuPDF OUTPUT, kept alive under ROOT.
Nix suffixes each out-link with its output name, so the path comes from the
output nix prints rather than from a guessed link name."
  (unless (executable-find "nix")
    (user-error "Building Emacs Reader needs nix to provide MuPDF"))
  (let ((errors (make-temp-file "pdf-nix-")))
    (unwind-protect
        (with-temp-buffer
          (unless (zerop (call-process
                          "nix" nil (list (current-buffer) errors) nil
                          "build" "--print-out-paths"
                          "--out-link" (expand-file-name "mupdf" root)
                          (concat "nixpkgs#mupdf." output)))
            (user-error "Nix could not build nixpkgs#mupdf.%s: %s"
                        output
                        (with-temp-buffer
                          (insert-file-contents errors)
                          (string-trim (buffer-string)))))
          (string-trim (buffer-string)))
      (delete-file errors))))

(defun pdf--module-file ()
  "Return the built Emacs Reader module, or nil when it is missing."
  (when-let* ((library (locate-library "reader")))
    (let ((file (expand-file-name (concat "render-core" module-file-suffix)
                                  (file-name-directory library))))
      (and (file-exists-p file) file))))

(defun pdf/build ()
  "Build Emacs Reader's dynamic module against nixpkgs' MuPDF, then load it.
Restart Emacs after a rebuild: a module that is already loaded cannot be
replaced in the same process."
  (interactive)
  (let ((library (locate-library "reader")))
    (unless library
      (user-error "Emacs Reader is not active; run M-x packages/bootstrap, then restart Emacs"))
    (let* ((root (cache/folder "pdf"))
           (dir (file-name-directory library))
           (dev (pdf--nix-output "dev" root))
           (out (pdf--nix-output "out" root)))
      ;; The text layer runs mutool from the same MuPDF build.
      (pdf--nix-output "bin" root)
      ;; Make does not track the MuPDF version or these flags, so drop every
      ;; object and rebuild.
      (dolist (file (cons (expand-file-name "render-core.so" dir)
                          (file-expand-wildcards
                           (expand-file-name "render/*.o" dir))))
        (when (file-exists-p file)
          (delete-file file)))
      (let ((process-environment
             (append (pdf--build-environment dev out) process-environment)))
        (reader-build)))))

(defun pdf--reader-ready-p ()
  "Return non-nil when Emacs Reader can draw pages in the selected frame."
  (and (display-graphic-p)
       (pdf--module-file)
       (condition-case err
           (progn
             (require 'reader)
             (reader-ensure-module)
             (featurep 'render-core))
         (error
          (message "Emacs Reader unavailable, using DocView: %s"
                   (error-message-string err))
          nil))))

(defun pdf--skip-size-prompt-p (op-type filename)
  "Return non-nil when FILENAME is a PDF that Emacs Reader will open.
Only the open of such a file skips the size prompt, since Reader pages it."
  (and (equal op-type "open")
       (stringp filename)
       (string-match-p "\\.pdf\\'" filename)
       (pdf--reader-ready-p)))

(defun pdf--around-abort-if-file-too-large (orig size op-type filename &rest args)
  "Skip the size prompt for large PDFs that Emacs Reader opens.
ORIG is the original function, called with SIZE, OP-TYPE, FILENAME, and ARGS."
  (unless (and large-file-warning-threshold
               size
               (> size large-file-warning-threshold)
               (pdf--skip-size-prompt-p op-type filename))
    (apply orig size op-type filename args)))

(advice-add 'abort-if-file-too-large :around
            #'pdf--around-abort-if-file-too-large)

(defun pdf--doc-view-fallback ()
  "Open the current PDF with DocView, or its next best mode.
DocView's fallback restores the previous mode through `auto-mode-alist', so
hide this dispatcher there; otherwise the fallback would call it again."
  (let ((auto-mode-alist (cl-remove 'pdf/mode-maybe auto-mode-alist
                                    :key #'cdr)))
    (doc-view-mode-maybe)))

(defun pdf/mode-maybe ()
  "Open this PDF with Emacs Reader in graphical frames, else with DocView."
  (if (pdf--reader-ready-p)
      (progn
        ;; `find-file' has already read the PDF bytes into this buffer.  Reader
        ;; reads the file itself, so keep only its page-border newline.  Clearing
        ;; the text first also stops So Long from treating binary data as a
        ;; long-line file, and skips undo bookkeeping for the large deletion.
        (let ((inhibit-read-only t)
              (buffer-undo-list t))
          (erase-buffer)
          (insert "\n")
          (goto-char (point-min)))
        (reader-mode))
    (pdf--doc-view-fallback)))

(defun pdf--claim-auto-mode ()
  "Send PDF files to `pdf/mode-maybe' ahead of other handlers.
Loading Emacs Reader also maps all of its formats to `reader-mode'.  Only PDF
keeps that handler here: EPUB stays with nov, and other formats keep theirs."
  (setq auto-mode-alist
        (cons (cons "\\.pdf\\'" #'pdf/mode-maybe)
              (cl-remove-if (lambda (entry)
                              (or (eq (cdr entry) 'reader-mode)
                                  (equal (car entry) "\\.pdf\\'")))
                            auto-mode-alist))))

(pdf--claim-auto-mode)
(with-eval-after-load 'reader
  ;; Loading reader.el registers its formats again, ahead of this entry.
  (pdf--claim-auto-mode))

(defun pdf--restore-reader-place ()
  "Restore the saved page and fit of the current Emacs Reader buffer."
  (when (derived-mode-p 'reader-mode)
    (reader--saveplace-find-file)
    (pdf--fit-restore)))

(defun pdf--claim-saveplace ()
  "Restore Emacs Reader positions only in Reader buffers.
Upstream runs its restore after every file visit, and that loads the whole
package.  Reader buffers are already loaded, so the guard costs nothing."
  (remove-hook 'save-place-after-find-file-hook #'reader--saveplace-find-file)
  (add-hook 'save-place-after-find-file-hook #'pdf--restore-reader-place))

(pdf--claim-saveplace)
(with-eval-after-load 'reader-saveplace
  ;; Loading reader-saveplace.el adds the global restore hook again.
  (pdf--claim-saveplace))

(defun pdf--after-command ()
  "Track page changes and repaint highlights after a command."
  (pdf/navigate-note-page)
  (pdf/image-refresh (current-buffer)))

(defun pdf--after-queue (&rest _)
  "Repaint after Reader runs a queued page command."
  (when (derived-mode-p 'reader-mode)
    (pdf--after-command)))

(defun pdf--rotated-clockwise (&rest _)
  "Track a clockwise page turn made with Reader's rotate command."
  (pdf--turn 1))

(defun pdf--rotated-counter (&rest _)
  "Track a counter-clockwise page turn made with Reader's rotate command."
  (pdf--turn -1))

(defun pdf--mode-setup ()
  "Attach the PDF features to a Reader buffer."
  (setq-local pdf--rotation 0)
  (add-hook 'post-command-hook #'pdf--after-command nil t)
  (add-hook 'kill-buffer-hook #'pdf--fit-save nil t))

(add-hook 'reader-mode-hook #'pdf--mode-setup)

(with-eval-after-load 'reader
  (advice-add 'reader--process-command-queue :after #'pdf--after-queue)
  (advice-add 'reader-rotate-clockwise :after #'pdf--rotated-clockwise)
  (advice-add 'reader-rotate-counter-clockwise :after #'pdf--rotated-counter))

(use-package reader
  :ensure nil
  :commands (reader-mode reader-open-doc)
  :bind (:map reader-mode-map
              ("/" . pdf/search-new)
              ("C-s" . pdf/search-forward)
              ("C-r" . pdf/search-backward)
              ("C-SPC" . pdf/select-start)
              ("M-w" . pdf/select-copy)
              ("C-g" . pdf/clear)
              ("M-f" . pdf/select-forward-word)
              ("M-b" . pdf/select-backward-word)
              ("M-n" . pdf/select-next-line)
              ("M-p" . pdf/select-previous-line)
              ("M-<left>" . pdf/history-back)
              ("M-<right>" . pdf/history-forward)
              ("<down-mouse-1>" . pdf/select-mouse-start)
              ("<drag-mouse-1>" . pdf/select-mouse-extend)
              ("<mouse-1>" . pdf/select-mouse-end)
              ("<double-mouse-1>" . pdf/select-word)
              ("<triple-mouse-1>" . pdf/select-line)
              ("H" . pdf/fit-height)
              ("W" . pdf/fit-width)
              ("+" . pdf/zoom-in)
              ("=" . pdf/zoom-in)
              ("-" . pdf/zoom-out)
              ("0" . pdf/zoom-reset)))

;;; reader.el ends here
