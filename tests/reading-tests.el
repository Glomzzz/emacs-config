;;; reading-tests.el --- Terminal EPUB reading regressions -*- lexical-binding: t; -*-

(require 'ert)
(require 'cl-lib)

(defconst config-test/reading-startup-features
  (mapcar (lambda (feature) (cons feature (featurep feature)))
          '(nov visual-fill-column))
  "Reading libraries loaded by an ordinary batch startup.")

(defconst config-test/reading-fixture-directory
  (expand-file-name "fixtures/reading-epub/"
                    (file-name-directory load-file-name)))

(defun config-test/reading-enter ()
  "Open the unpacked test EPUB in the current buffer without extracting it."
  (require 'nov)
  (setq-local nov-initialize-work-dir-p nil
              nov-remove-work-dir-on-exit-p nil
              nov-work-dir config-test/reading-fixture-directory)
  (nov-mode))

(defmacro config-test/with-epub (&rest body)
  "Run BODY in a real Nov buffer without touching user state or the fixture."
  (declare (indent 0) (debug t))
  `(let ((nov-save-place-file nil))
     (with-temp-buffer
       (config-test/reading-enter)
       ,@body)))

(ert-deftest config-test/reading-startup-stays-lazy ()
  (dolist (entry config-test/reading-startup-features)
    (should-not (cdr entry)))
  (dolist (package '(nov visual-fill-column))
    (should (memq package packages/declared)))
  (should (eq nov-render-html-function #'reading/render-html)))

(ert-deftest config-test/reading-layout-is-buffer-local ()
  (require 'visual-fill-column)
  (let ((width (default-value 'visual-fill-column-width))
        (center (default-value 'visual-fill-column-center-text))
        (modeline (default-value 'mode-line-format)))
    (config-test/with-epub
      (should visual-line-mode)
      (should visual-fill-column-mode)
      (should visual-fill-column-center-text)
      (should (= visual-fill-column-width reading/nov-text-width))
      (should-not display-line-numbers-mode)
      (should-not hl-line-mode)
      (should-not show-trailing-whitespace)
      (should buffer-read-only)
      (should (eq nov-text-width t))
      (should (= next-screen-context-lines 2))
      (should (equal (eval (cadr (nth 1 mode-line-format))) "Part 1/3"))
      (nov-next-document)
      (should (equal (eval (cadr (nth 1 mode-line-format))) "Part 2/3")))
    (should (equal (default-value 'visual-fill-column-width) width))
    (should (eq (default-value 'visual-fill-column-center-text) center))
    (with-temp-buffer
      (text-mode)
      (should-not visual-fill-column-mode)
      (should (equal mode-line-format modeline)))))

(ert-deftest config-test/reading-colors-apply-on-first-and-later-renders ()
  (require 'nov)
  (let ((shr-use-colors t)
        (render (symbol-function 'nov-render-html))
        seen)
    (cl-letf (((symbol-function 'nov-render-html)
               (lambda ()
                 (push shr-use-colors seen)
                 (funcall render))))
      (config-test/with-epub
        (should (equal seen '(nil)))
        (nov-next-document)
        (should (equal seen '(nil nil)))
        (goto-char (point-min))
        (search-forward "Publisher-colored text")
        (should-not
         (string-match-p "#ff0000"
                         (prin1-to-string
                          (buffer-substring (match-beginning 0) (match-end 0)))))
        (should shr-use-colors)))))

(ert-deftest config-test/reading-width-preserves-text-links-and-position ()
  (config-test/with-epub
    (nov-next-document)
    (goto-char (point-min))
    (search-forward "中文阅读")
    (let ((text (buffer-string))
          (position (point))
          (history (copy-tree nov-history)))
      (reading/set-width 60)
      (should (= visual-fill-column-width 60))
      (reading/widen 2)
      (should (= visual-fill-column-width 68))
      (reading/narrow 3)
      (should (= visual-fill-column-width 56))
      (reading/reset-width)
      (should (= visual-fill-column-width reading/nov-text-width))
      (should (= (point) position))
      (should (= nov-documents-index 1))
      (should (equal nov-history history))
      (should (equal-including-properties (buffer-string) text))
      (should-not (buffer-modified-p))
      (should-error (reading/set-width 0) :type 'user-error)
      (should-error (reading/set-width 19) :type 'user-error)
      (should-error (reading/set-width 60.5) :type 'user-error)
      (should (= visual-fill-column-width reading/nov-text-width))))
  (with-temp-buffer
    (should-error (reading/set-width 60) :type 'user-error)))

(ert-deftest config-test/reading-width-updates-all-visible-windows ()
  (save-window-excursion
    (config-test/with-epub
      (switch-to-buffer (current-buffer))
      (delete-other-windows)
      (nov-next-document)
      (goto-char (point-min))
      (search-forward "中文阅读")
      (let ((other (split-window-below))
            (position (point))
            visited)
        (set-window-buffer other (current-buffer))
        (set-window-point other (point-min))
        (let ((adjust (symbol-function 'visual-fill-column-adjust)))
          (cl-letf (((symbol-function 'visual-fill-column-adjust)
                     (lambda (&rest args)
                       (push (selected-window) visited)
                       (apply adjust args))))
            (reading/set-width 40)))
        (should (= (point) position))
        (should (= (window-point other) (point-min)))
        (should (= (length visited) 2))
        (dolist (window (list (selected-window) other))
          (should (memq window visited))
          (should (<= (abs (- (window-body-width window) 40)) 1)))
        ;; A measure wider than a window should remove margins, not truncate.
        (reading/set-width 200)
        (should-not truncate-lines)
        (should (equal (window-margins) '(nil . nil)))))))

(ert-deftest config-test/reading-keys-work-on-prose-and-links ()
  (save-window-excursion
    (config-test/with-epub
      (switch-to-buffer (current-buffer))
      (nov-next-document)
      (dolist (map (list nov-mode-map nov-button-map))
        (dolist (binding '(("j" . next-line)
                           ("k" . previous-line)
                           ("<next>" . nov-scroll-up)
                           ("<prior>" . nov-scroll-down)
                           ("C-v" . nov-scroll-up)
                           ("M-v" . nov-scroll-down)
                           ("i" . consult-imenu)
                           ("w" . reading/set-width)
                           ("+" . reading/widen)
                           ("-" . reading/narrow)
                           ("=" . reading/reset-width)
                           ("?" . describe-mode)))
          (should (eq (lookup-key map (kbd (car binding))) (cdr binding)))))
      (goto-char (point-min))
      (shr-next-link)
      (should (get-text-property (point) 'shr-url))
      (should (eq (key-binding (kbd "j")) #'next-line))
      (should (eq (key-binding (kbd "+")) #'reading/widen))
      (should (eq (key-binding (kbd "SPC")) #'nov-scroll-up))
      (nov-browse-url ?\r)
      (should (= nov-documents-index 2))
      (nov-history-back)
      (should (= nov-documents-index 1))
      (nov-goto-toc)
      (should (= nov-documents-index 0))
      (let ((index (funcall imenu-create-index-function)))
        (should (equal (caar index) "First chapter / 第一章"))
        (apply (nth 2 (cadr index)) (car (cadr index))
               (nth 1 (cadr index)) (nthcdr 3 (cadr index)))
        (should (= nov-documents-index 2))
        ;; Contents paths must work from a chapter in a different directory.
        (apply (nth 2 (car index)) (caar index)
               (nth 1 (car index)) (nthcdr 3 (car index)))
        (should (= nov-documents-index 1))
        (should (string-match-p "First chapter" (buffer-string)))
        (nov-history-back)
        (should (= nov-documents-index 2))
        ;; An empty filename in a contents entry denotes the TOC itself.
        (reading/visit-content "Contents" "" nil)
        (should (= nov-documents-index 0))))))

(ert-deftest config-test/reading-width-does-not-break-saved-places ()
  (let* ((root (make-temp-file "reading-places-test-" t))
         (nov-save-place-file (expand-file-name "places" root)))
    (unwind-protect
        (with-temp-buffer
          (config-test/reading-enter)
          (nov-next-document)
          (goto-char (point-min))
          (search-forward "中文阅读")
          (reading/set-width 40)
          (let ((position (point)))
            (nov-save-place (alist-get 'identifier nov-metadata)
                            nov-documents-index position)
            (with-temp-buffer
              (config-test/reading-enter)
              (should (= nov-documents-index 1))
              (should (= (point) position))
              (should (= visual-fill-column-width reading/nov-text-width)))))
      (delete-directory root t))))

(ert-deftest config-test/reading-setup-does-not-stack-font-remaps ()
  (config-test/with-epub
    (let ((remaps (copy-tree face-remapping-alist)))
      (reading/setup-nov)
      (should (equal face-remapping-alist remaps))
      (should (equal (plist-get (cadr (assq 'variable-pitch
                                           face-remapping-alist)) :family)
                     reading/nov-body-family)))))

(provide 'reading-tests)
;;; reading-tests.el ends here
