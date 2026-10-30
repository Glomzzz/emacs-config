;;; reading-book-tests.el --- EPUB Chinese font, book search, and highlights -*- lexical-binding: t; -*-

(require 'ert)
(require 'cl-lib)
(require 'nov)

(defun config-test/han-family-at-p (pos)
  "Return non-nil when the text at POS carries the Han font family."
  (let ((face (get-text-property pos 'face)))
    (cond ((keywordp (car-safe face))
           (equal (plist-get face :family) reading/han-family))
          ((consp face)
           (cl-some (lambda (spec)
                      (and (listp spec)
                           (equal (plist-get spec :family) reading/han-family)))
                    face)))))

(ert-deftest config-test/reading-han-runs-use-the-han-family-in-graphical-frames ()
  (config-test/with-epub
    (nov-goto-document 1)
    (cl-letf (((symbol-function 'display-graphic-p) (lambda (&rest _) t)))
      (reading/apply-han-font))
    (goto-char (point-min))
    (should (search-forward "中文阅读" nil t))
    (should (config-test/han-family-at-p (match-beginning 0)))))

(ert-deftest config-test/reading-han-font-is-left-to-terminals ()
  (config-test/with-epub
    (nov-goto-document 1)
    (cl-letf (((symbol-function 'display-graphic-p) (lambda (&rest _) nil)))
      (reading/apply-han-font))
    (goto-char (point-min))
    (should (search-forward "中文阅读" nil t))
    (should-not (config-test/han-family-at-p (match-beginning 0)))))

(ert-deftest config-test/reading-book-search-finds-matches-in-several-sections ()
  (config-test/with-epub
    (setq-local nov-file-name "/tmp/reading-book-test.epub")
    (let* ((matches (reading--book-matches "阅读"))
           (sections (delete-dups (mapcar #'car matches))))
      (should (>= (length sections) 2))
      (should (cl-every (lambda (match) (string-match-p "阅读" (cdr match)))
                        matches)))))

(ert-deftest config-test/reading-highlight-is-saved-and-reapplied ()
  (let ((store (make-temp-file "reading-highlights-" nil ".eld")))
    (unwind-protect
        (cl-letf (((symbol-function 'reading--highlights-file)
                   (lambda () store)))
          (config-test/with-epub
            (setq-local nov-file-name "/tmp/reading-book-test.epub")
            (nov-goto-document 1)
            (goto-char (point-min))
            (should (search-forward "中文阅读" nil t))
            (set-mark (match-beginning 0))
            (goto-char (match-end 0))
            (reading/highlight-region (region-beginning) (region-end))
            (should (cl-some (lambda (ov) (equal (overlay-get ov 'reading-text)
                                                 "中文阅读"))
                             (overlays-in (point-min) (point-max))))
            (should (equal (reading--book-highlights)
                           (list (list nov-documents-index "中文阅读"))))
            ;; Rendering the section again recreates the highlight from the store.
            (mapc #'delete-overlay (overlays-in (point-min) (point-max)))
            (reading--apply-highlights)
            (should (cl-some (lambda (ov) (equal (overlay-get ov 'reading-text)
                                                 "中文阅读"))
                             (overlays-in (point-min) (point-max))))
            (goto-char (point-min))
            (search-forward "中文阅读")
            (goto-char (match-beginning 0))
            (reading/unhighlight)
            (should-not (reading--book-highlights))))
      (delete-file store))))

;;; reading-book-tests.el ends here
