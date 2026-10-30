;;; pdf-tests.el --- PDF reader routing regressions -*- lexical-binding: t; -*-

(require 'ert)
(require 'cl-lib)

(defconst config-test/pdf-reader-loaded-on-startup (featurep 'reader)
  "Whether Emacs Reader was loaded before any test ran.")

(ert-deftest config-test/pdf-reader-stays-lazy ()
  (should-not config-test/pdf-reader-loaded-on-startup)
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

(defconst config-test/pdf-fixture
  (expand-file-name "fixtures/pdf/two-pages.pdf" (file-name-directory load-file-name))
  "Two-page text PDF: page 1 reads \"Hello reader Select this text\".")

(defvar config-test/pdf-page 1)

(ert-deftest config-test/pdf-text-layer-reads-characters-in-order ()
  (skip-unless (pdf--text-program))
  (let ((layer (pdf/text-page config-test/pdf-fixture 1)))
    (should (= (pdf-text-width layer) 300))
    (should (= (pdf-text-height layer) 200))
    (should (equal (pdf/text-range layer 0 (1- (length (pdf-text-chars layer))))
                   "Hello reader Select this text"))))

(ert-deftest config-test/pdf-search-moves_across_pages_and_wraps ()
  (skip-unless (pdf--text-program))
  (let* ((file config-test/pdf-fixture)
         (first (pdf--search-find file 2 "reader" 1 -1 nil))
         (second (pdf--search-find file 2 "reader" (car first) (cadr first) nil))
         (third (pdf--search-find file 2 "reader" (car second) (cadr second) nil))
         (fourth (pdf--search-find file 2 "reader" (car third) (cadr third) nil)))
    (should (equal (mapcar #'car (list first second third fourth)) '(1 2 2 1)))))

(ert-deftest config-test/pdf-search-highlights-matches-on-the-page ()
  (skip-unless (pdf--text-program))
  (with-temp-buffer
    (setq buffer-file-name config-test/pdf-fixture
          pdf--query "reader")
    (let ((groups (pdf/search-groups 1)))
      (should (= (length groups) 1))
      (should (= (length (car (car groups))) 1)))
    (setq pdf--match (list 1 6 11))
    (let ((groups (pdf/search-groups 1)))
      (should (= (length groups) 1))
      (should (equal (nth 1 (car groups)) pdf/search-current-color)))))

(ert-deftest config-test/pdf-selection-copies-text-in-reading-order ()
  (skip-unless (pdf--text-program))
  (let ((kill-ring nil))
    (with-temp-buffer
      (setq buffer-file-name config-test/pdf-fixture)
      (pdf--select-set (current-buffer) 1 6 11)
      (pdf/select-copy))
    (should (equal (car kill-ring) "reader"))))

(ert-deftest config-test/pdf-word-and-line-ranges-follow-the-text ()
  (skip-unless (pdf--text-program))
  (let* ((layer (pdf/text-page config-test/pdf-fixture 1))
         (chars (pdf-text-chars layer))
         (index (cl-position "S" chars :key (lambda (c) (aref c 0)) :test #'equal))
         (word (pdf--word-range chars index))
         (line (pdf--line-range chars index)))
    (should (equal (pdf/text-range layer (car word) (cdr word)) "Select"))
    (should (equal (pdf/text-range layer (car line) (cdr line))
                   "Select this text"))))

(ert-deftest config-test/pdf-image-blends-highlight-into-the-ppm-in-place ()
  (let* ((data (apply #'unibyte-string
                      (append (string-to-list "P6\n2 2\n255\n")
                              (make-list 12 255))))
         (spec (list 'image :type 'pbm :data data :width 2 :height 2))
         (painted (pdf--composite
                   spec (list (list (list (list 0 0 1 1)) "#000000" 255))))
         (out (plist-get (cdr painted) :data))
         (offset (pdf--ppm-data-start data)))
    (should (equal (substring out offset (+ offset 3))
                   (unibyte-string 0 0 0)))
    (should (equal (substring out (+ offset 3) (+ offset 6))
                   (unibyte-string 255 255 255)))
    (should (equal (substring data offset (+ offset 3))
                   (unibyte-string 255 255 255)))))

(ert-deftest config-test/pdf-page-and-display-points-round-trip ()
  (dolist (angle '(0 1 2 3))
    (dolist (point '((10 . 20) (299 . 0) (0 . 199)))
      (let* ((display (pdf--to-display (car point) (cdr point) angle 300 200))
             (back (pdf--from-display (car display) (cdr display) angle 300 200)))
        (should (equal back point))))))

(ert-deftest config-test/pdf-rect-maps-to-pixels-after-rotation ()
  (should (equal (pdf-rect-to-pixels '(0 0 30 20) 0 300 200 600 400)
                 '(0 0 60 40)))
  (should (equal (pdf-rect-to-pixels '(0 0 30 20) 1 300 200 400 600)
                 '(360 0 400 60))))

(ert-deftest config-test/pdf-history-goes-back-and-forward ()
  (cl-letf (((symbol-function 'derived-mode-p) (lambda (&rest _) t))
            ((symbol-function 'reader-current-doc-pagenumber)
             (lambda (&rest _) config-test/pdf-page))
            ((symbol-function 'reader-goto-page)
             (lambda (page) (setq config-test/pdf-page page))))
    (with-temp-buffer
      (setq config-test/pdf-page 1)
      (pdf/navigate-note-page)
      (setq config-test/pdf-page 2)
      (pdf/navigate-note-page)
      (setq config-test/pdf-page 3)
      (pdf/navigate-note-page)
      (should (equal pdf--back '(2 1)))
      (pdf/history-back)
      (should (= config-test/pdf-page 2))
      (pdf/history-back)
      (should (= config-test/pdf-page 1))
      (pdf/history-forward)
      (should (= config-test/pdf-page 2)))))

(ert-deftest config-test/pdf-fit-is-remembered-per-file ()
  (let ((views (make-temp-file "pdf-views-" nil ".eld"))
        (width-calls 0))
    (unwind-protect
        (cl-letf (((symbol-function 'pdf--views-file) (lambda () views))
                  ((symbol-function 'reader-fit-to-width)
                   (lambda (&rest _) (cl-incf width-calls))))
          (with-temp-buffer
            (setq buffer-file-name config-test/pdf-fixture
                  pdf--fit 'width)
            (pdf--fit-save))
          (with-temp-buffer
            (setq buffer-file-name config-test/pdf-fixture)
            (pdf--fit-restore)
            (should (eq pdf--fit 'width))))
      (delete-file views))
    (should (= width-calls 1))))

(ert-deftest config-test/pdf-reader-buffer-paints-and-clears-selection ()
  (skip-unless (and (pdf--text-program) (pdf--module-file)))
  (cl-letf (((symbol-function 'display-graphic-p) (lambda (&rest _) t))
            ((symbol-function 'imenu-add-menubar-index) (lambda (&rest _) nil))
            ((symbol-function 'image-flush) (lambda (&rest _) nil))
            ((symbol-function 'reader-fit-to-height) (lambda (&rest _) nil))
            ((symbol-function 'reader--center-page) (lambda (&rest _) nil)))
    (let ((buffer (find-file-noselect config-test/pdf-fixture)))
      (unwind-protect
          (with-current-buffer buffer
            (switch-to-buffer buffer)
            (let* ((overlay (reader-current-doc-overlay))
                   (base (overlay-get overlay 'display)))
              (should (overlayp overlay))
              (pdf--select-set buffer 1 0 4)
              (let ((painted (overlay-get overlay 'display)))
                (should (eq painted (overlay-get overlay 'pdf-composite)))
                (should-not (equal (plist-get (cdr painted) :data)
                                   (plist-get (cdr base) :data))))
              (pdf/select-clear)
              (should (eq (overlay-get overlay 'display) base))))
        (kill-buffer buffer)))))

;;; pdf-tests.el ends here
