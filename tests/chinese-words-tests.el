;;; chinese-words-tests.el --- Chinese word motion contract -*- lexical-binding: t; -*-

(require 'ert)
(require 'cl-lib)

(ert-deftest config-test/chinese-words-declares-cns-from-git ()
  (let ((source (alist-get 'cns packages/vc-sources)))
    (should source)
    (should (equal (plist-get source :url)
                   "https://github.com/kanglmf/emacs-chinese-word-segmentation"))
    (should (eq (plist-get source :vc-backend) 'Git))))

(ert-deftest config-test/chinese-words-dictionary-follows-program ()
  (let* ((root (make-temp-file "cnws-root-" t))
         (program (expand-file-name "bin/cnws" root)))
    (unwind-protect
        (progn
          (make-directory (file-name-directory program) t)
          (with-temp-file program)
          (should (equal (chinese-words/dictionary-directory program)
                         (expand-file-name
                          "share/chinese-word-segmentation/dict"
                          (file-truename root)))))
      (delete-directory root t))))

(ert-deftest config-test/chinese-words-skips-latin-buffers ()
  (with-temp-buffer
    (insert "plain English text")
    (cl-letf (((symbol-function 'chinese-words/configure)
               (lambda () (ert-fail "Latin buffer reached segmenter setup"))))
      (chinese-words/enable-maybe)
      (should-not (bound-and-true-p cns-mode)))))

(ert-deftest config-test/chinese-words-stays-off-without-segmenter ()
  (with-temp-buffer
    (insert "中文分词")
    (cl-letf (((symbol-function 'chinese-words/program) (lambda () nil)))
      (chinese-words/enable-maybe)
      (should-not (bound-and-true-p cns-mode)))))

(ert-deftest config-test/chinese-words-segments-through-cnws ()
  "Round-trip one sentence through the real `cnws' line protocol."
  (skip-unless (and (chinese-words/program)
                    (require 'cns nil t)))
  (chinese-words/configure)
  (with-temp-buffer
    (cns-mode 1)
    (unwind-protect
        (should (equal (cns-segmentation-handler "中文分词") '(2 2)))
      (cns-mode -1))))

(ert-deftest config-test/chinese-words-restarts-segmenter-after-last-buffer ()
  "A Chinese buffer opened after the last one closes gets a fresh segmenter.
The stopped helper must not be reused: it no longer reads its input."
  (skip-unless (and (chinese-words/program)
                    (require 'cns nil t)))
  (chinese-words/configure)
  (let ((cns-recent-segmentation nil)
        stopped)
    (with-temp-buffer
      (cns-mode 1)
      (setq stopped cns-process)
      (cns-mode -1))
    (should-not (process-live-p stopped))
    (with-temp-buffer
      (cns-mode 1)
      (unwind-protect
          (progn
            (should (process-live-p cns-process))
            (should-not (eq cns-process stopped))
            (should (equal (cns-segmentation-handler "中文分词") '(2 2))))
        (cns-mode -1)))))

(ert-deftest config-test/chinese-words-backward-stops-at-buffer-start ()
  "M-b at the start of a Chinese buffer stays at `point-min' without an error."
  (skip-unless (and (chinese-words/program)
                    (require 'cns nil t)))
  (chinese-words/configure)
  (with-temp-buffer
    (insert "中文分词")
    (cns-mode 1)
    (unwind-protect
        (progn
          (goto-char (point-min))
          (should (null (condition-case err (cns-backward-word) (error err))))
          (should (= (point) (point-min))))
      (cns-mode -1))))

(ert-deftest config-test/chinese-words-backward-stops-after-punctuation ()
  "M-b with only punctuation before point moves to `point-min'."
  (skip-unless (and (chinese-words/program)
                    (require 'cns nil t)))
  (chinese-words/configure)
  (with-temp-buffer
    (insert "，中文分词")
    (cns-mode 1)
    (unwind-protect
        (progn
          (goto-char 2)
          (should (null (condition-case err (cns-backward-word) (error err))))
          (should (= (point) (point-min))))
      (cns-mode -1))))

(ert-deftest config-test/chinese-words-typed-han-schedules-enable-once ()
  "Typing Han characters into a Latin buffer schedules `cns-mode' once."
  (skip-unless (chinese-words/program))
  (with-temp-buffer
    (insert "hello")
    (let ((scheduled 0))
      (cl-letf (((symbol-function 'run-at-time)
                 (lambda (&rest _) (setq scheduled (1+ scheduled)))))
        (insert "中文")
        (insert "分词")
        (should (= scheduled 1))))))

(ert-deftest config-test/chinese-words-latin-insertion-does-not-schedule ()
  (skip-unless (chinese-words/program))
  (with-temp-buffer
    (let ((scheduled 0))
      (cl-letf (((symbol-function 'run-at-time)
                 (lambda (&rest _) (setq scheduled (1+ scheduled)))))
        (insert "plain English")
        (should (= scheduled 0))))))

(ert-deftest config-test/chinese-words-typed-han-moves-by-word ()
  "Chinese typed after opening a Latin buffer moves by segmented word."
  (skip-unless (and (chinese-words/program)
                    (require 'cns nil t)))
  (chinese-words/configure)
  (with-temp-buffer
    (insert "hello")
    (cl-letf (((symbol-function 'run-at-time) #'ignore))
      (insert "中文分词"))
    (unwind-protect
        (progn
          (chinese-words/enable-pending (current-buffer))
          (should (bound-and-true-p cns-mode))
          (goto-char (point-max))
          (cns-backward-word)
          ;; "hello" is 5 characters, "中文" starts at 6, "分词" at 8.
          (should (= (point) 8)))
      (cns-mode -1))))

;;; chinese-words-tests.el ends here
