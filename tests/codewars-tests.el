;;; codewars-tests.el --- Codewars project regressions -*- lexical-binding: t; -*-

(require 'ert)
(require 'cl-lib)

(defconst config-test/codewars-kata
  '((id . "5277c8a221e209d3f6000b56")
    (name . "Valid Braces")
    (slug . "valid-braces")
    (rank . ((name . "6 kyu")))
    (languages . ("javascript" "haskell" "python" "rust"))
    (description . "Write `validBraces`."))
  "Fixture shaped like a record from the public code-challenges API.")

(defmacro config-test/codewars-with-root (&rest body)
  "Run BODY with `codewars/directory' in a fresh temporary directory."
  (declare (indent 0))
  `(let* ((root (make-temp-file "codewars-test-" t))
          (codewars/directory (file-name-as-directory root))
          (trusted-content trusted-content))
     (unwind-protect
         (progn ,@body)
       (delete-directory root t))))

(ert-deftest config-test/codewars-slug-accepts-slug-id-and-url ()
  (should (equal (codewars/slug-from-input "valid-braces") "valid-braces"))
  (should (equal (codewars/slug-from-input
                  "https://www.codewars.com/kata/valid-braces?x=1")
                 "valid-braces"))
  (should (equal (codewars/slug-from-input
                  " https://www.codewars.com/kata/5277c8a221e209d3f6000b56/train/rust ")
                 "5277c8a221e209d3f6000b56"))
  (should-error (codewars/slug-from-input "not a slug!") :type 'user-error))

(ert-deftest config-test/codewars-extension-follows-language-table ()
  (should (equal (codewars/extension-for "javascript") "js"))
  (should (equal (codewars/extension-for "cpp") "cpp"))
  (should (equal (codewars/extension-for "elm") "elm")))

(ert-deftest config-test/codewars-pull-creates-project-and-keeps-solution ()
  (config-test/codewars-with-root
    (let ((opened nil))
      (cl-letf (((symbol-function 'codewars/fetch-kata)
                 (lambda (_slug) config-test/codewars-kata))
                ((symbol-function 'completing-read)
                 (lambda (&rest _) "rust"))
                ((symbol-function 'find-file)
                 (lambda (file) (setq opened file))))
        (codewars/pull "valid-braces")
        (let* ((dir (file-name-as-directory
                     (expand-file-name "valid-braces" root)))
               (solution (expand-file-name "solution.rs" dir)))
          (should (file-exists-p solution))
          (should (equal opened solution))
          (should (string-match-p
                   "Write `validBraces`\\."
                   (with-temp-buffer
                     (insert-file-contents (expand-file-name "README.md" dir))
                     (buffer-string))))
          (should (equal (let ((default-directory dir))
                           (plist-get (codewars/read-metadata) :language))
                         "rust"))
          ;; Pulling again must not overwrite code already written.
          (with-temp-file solution (insert "fn validBraces() {}\n"))
          (codewars/pull "valid-braces")
          (should (equal (with-temp-buffer
                           (insert-file-contents solution)
                           (buffer-string))
                         "fn validBraces() {}\n")))))))

(ert-deftest config-test/codewars-pull-preselects-haskell ()
  (should (equal (default-value 'codewars/default-language) "haskell"))
  (config-test/codewars-with-root
    (let ((chosen nil))
      (cl-letf (((symbol-function 'codewars/fetch-kata)
                 (lambda (_slug) config-test/codewars-kata))
                ((symbol-function 'completing-read)
                 (lambda (_prompt _coll _pred _req _init _hist default)
                   (setq chosen default)
                   default))
                ((symbol-function 'find-file) #'ignore))
        (codewars/pull "valid-braces")
        (should (equal chosen "haskell"))
        (should (file-exists-p
                 (expand-file-name "valid-braces/solution.hs" root)))))))

(ert-deftest config-test/codewars-projects-are-trusted-content ()
  (config-test/codewars-with-root
    (let ((trusted-content trusted-content))
      (codewars--trust-directory)
      (with-temp-buffer
        (let ((file (expand-file-name "valid-braces/solution.hs" root)))
          (setq buffer-file-name file
                buffer-file-truename file)
          (should (trusted-content-p)))))))

(ert-deftest config-test/codewars-metadata-found-from-nested-directory ()
  (config-test/codewars-with-root
    (let* ((dir (file-name-as-directory (expand-file-name "kata" root)))
           (nested (expand-file-name "src/" dir)))
      (make-directory nested t)
      (codewars--write-metadata '(:id "abc" :slug "kata" :language "python") dir)
      (let ((default-directory nested))
        (let ((meta (codewars/read-metadata)))
          (should (equal (plist-get meta :id) "abc"))
          (should (equal (file-name-as-directory (plist-get meta :directory))
                         dir)))))
    (let ((default-directory root))
      (should-error (codewars/read-metadata) :type 'user-error))))

(ert-deftest config-test/codewars-trainer-url-uses-id-and-language ()
  (should (equal (codewars/trainer-url
                  '(:id "5277c8a221e209d3f6000b56" :language "cpp"))
                 "https://www.codewars.com/kata/5277c8a221e209d3f6000b56/train/cpp")))

(ert-deftest config-test/codewars-test-runs-configured-command-in-project ()
  (config-test/codewars-with-root
    (let* ((dir (file-name-as-directory (expand-file-name "kata" root)))
           (captured nil)
           (codewars/test-commands '(("rust" . "cargo test"))))
      (make-directory dir t)
      (codewars--write-metadata '(:id "abc" :slug "kata" :language "rust") dir)
      (let ((default-directory dir))
        (cl-letf (((symbol-function 'compile)
                   (lambda (command &rest _)
                     (setq captured (cons command default-directory)))))
          (codewars/test)))
      (should (equal (car captured) "cargo test"))
      (should (equal (file-name-as-directory (cdr captured)) dir)))))

(ert-deftest config-test/codewars-keymap-opens-menu ()
  (should (fboundp 'hydra-codewars/body))
  (should (eq (key-binding (kbd "C-x C-h K")) 'hydra-codewars/body)))

;;; codewars-tests.el ends here
