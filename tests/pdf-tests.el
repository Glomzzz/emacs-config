;;; pdf-tests.el --- PDF reader routing regressions -*- lexical-binding: t; -*-

(require 'ert)
(require 'cl-lib)

(ert-deftest config-test/pdf-reader-stays-lazy ()
  (should-not (featurep 'reader))
  (should-not (featurep 'render-core))
  (should (memq 'reader packages/declared))
  (should (equal (plist-get (alist-get 'reader packages/vc-sources) :url)
                 "https://codeberg.org/MonadicSheep/emacs-reader")))

(ert-deftest config-test/pdf-plain-file-visits-keep-reader-unloaded ()
  (let ((file (make-temp-file "pdf-tests-" nil ".txt")))
    (unwind-protect
        (progn
          (kill-buffer (find-file-noselect file))
          (should-not (featurep 'reader))
          (should-not (memq #'reader--saveplace-find-file
                            (and (boundp 'save-place-after-find-file-hook)
                                 save-place-after-find-file-hook))))
      (delete-file file))))

(ert-deftest config-test/pdf-routes-only-pdf-to-dispatcher ()
  (should (eq (assoc-default "/tmp/paper.pdf" auto-mode-alist #'string-match)
              #'pdf/mode-maybe))
  (should-not (rassq 'reader-mode auto-mode-alist))
  (should (eq (assoc-default "/tmp/book.epub" auto-mode-alist #'string-match)
              'nov-mode)))

(ert-deftest config-test/pdf-terminal-frames-use-doc-view ()
  (let (chosen)
    (cl-letf (((symbol-function 'display-graphic-p) (lambda (&rest _) nil))
              ((symbol-function 'doc-view-mode-maybe)
               (lambda () (setq chosen 'doc-view)))
              ((symbol-function 'reader-mode)
               (lambda () (setq chosen 'reader))))
      (with-temp-buffer
        (pdf/mode-maybe)))
    (should (eq chosen 'doc-view))))

(ert-deftest config-test/pdf-graphical-frames-open-reader-without-file-bytes ()
  (let (chosen contents)
    (cl-letf (((symbol-function 'pdf--reader-ready-p) (lambda () t))
              ((symbol-function 'reader-mode)
               (lambda ()
                 (setq chosen 'reader
                       contents (buffer-string))))
              ((symbol-function 'doc-view-mode-maybe)
               (lambda () (setq chosen 'doc-view))))
      (with-temp-buffer
        (insert "%PDF-1.7\n%binary bytes")
        (pdf/mode-maybe)))
    (should (eq chosen 'reader))
    (should (equal contents "\n"))))

(ert-deftest config-test/pdf-build-environment-targets-mupdf ()
  (let ((env (pdf--build-environment "/store/dev" "/store/out")))
    (should (member "CPATH=/store/dev/include" env))
    (should (member "LIBRARY_PATH=/store/out/lib" env))
    (should (member (format "CFLAGS=%s" pdf/build-cflags) env))))

(ert-deftest config-test/pdf-large-pdf-skips-size-prompt-in-reader ()
  (let* ((file (make-temp-file "pdf-large-" nil ".pdf"))
         (large-file-warning-threshold 1000))
    (unwind-protect
        (progn
          (with-temp-file file (insert (make-string 5000 ?x)))
          (cl-letf (((symbol-function 'pdf--reader-ready-p) (lambda () t))
                    ((symbol-function 'files--ask-user-about-large-file)
                     (lambda (&rest _) (ert-fail "size prompt shown"))))
            (should-not (abort-if-file-too-large 5000 "open" file))))
      (delete-file file))))

(ert-deftest config-test/pdf-large-pdf-keeps-size-prompt-without-reader ()
  (let* ((file (make-temp-file "pdf-large-" nil ".pdf"))
         (large-file-warning-threshold 1000)
         asked)
    (unwind-protect
        (progn
          (with-temp-file file (insert (make-string 5000 ?x)))
          (cl-letf (((symbol-function 'pdf--reader-ready-p) (lambda () nil))
                    ((symbol-function 'files--ask-user-about-large-file)
                     (lambda (&rest _) (setq asked t) 'abort)))
            (should-error (abort-if-file-too-large 5000 "open" file)))
          (should asked))
      (delete-file file))))

(ert-deftest config-test/pdf-large-text-keeps-size-prompt ()
  (let* ((file (make-temp-file "pdf-large-" nil ".txt"))
         (large-file-warning-threshold 1000))
    (unwind-protect
        (progn
          (with-temp-file file (insert (make-string 5000 ?x)))
          (cl-letf (((symbol-function 'pdf--reader-ready-p) (lambda () t))
                    ((symbol-function 'files--ask-user-about-large-file)
                     (lambda (&rest _) 'abort)))
            (should-error (abort-if-file-too-large 5000 "open" file))))
      (delete-file file))))

;;; pdf-tests.el ends here
