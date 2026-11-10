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

(defconst config-test/codewars-kata-response
  "HTTP/1.1 200 OK\n\n{\"id\":\"5277c8a221e209d3f6000b56\",\"name\":\"Valid Braces\",\"slug\":\"valid-braces\",\"rank\":{\"name\":\"6 kyu\"},\"languages\":[\"javascript\",\"haskell\",\"python\",\"rust\"],\"description\":\"Write `validBraces`.\"}"
  "Raw API response for `valid-braces', as `url-retrieve' hands it over.")

(defvar config-test/codewars-held nil
  "The (BUFFER CALLBACK CBARGS) of the request `url-retrieve' was asked to make.")

(defun config-test/codewars-hold-request (_url callback cbargs &rest _)
  "Stand in for `url-retrieve', keeping CALLBACK until the test delivers."
  (setq config-test/codewars-held
        (list (generate-new-buffer " *codewars-held*") callback cbargs)))

(defun config-test/codewars-deliver (text &optional status)
  "Deliver TEXT and STATUS to the held request, as `url-retrieve' would."
  (pcase-let ((`(,buffer ,callback ,cbargs) config-test/codewars-held))
    (with-current-buffer buffer
      (insert text)
      (apply callback status cbargs))))

(defun config-test/codewars-fetch (text &optional status)
  "Return the (KATA ERROR) that `codewars/fetch-kata' reports for TEXT."
  (let ((outcome 'pending))
    (cl-letf (((symbol-function 'url-retrieve) #'config-test/codewars-hold-request))
      (codewars/fetch-kata "valid-braces"
                           (lambda (kata error) (setq outcome (list kata error))))
      (should (eq outcome 'pending))
      (config-test/codewars-deliver text status))
    outcome))

(ert-deftest config-test/codewars-fetch-reports-each-failure-kind ()
  (should (equal (config-test/codewars-fetch
                  "" '(:error (error connection-failed "failed with code 111")))
                 '(nil "Could not reach Codewars for valid-braces")))
  (should (equal (config-test/codewars-fetch
                  "HTTP/1.1 404 Not Found\n\n{}" '(:error (error http 404)))
                 '(nil "Codewars returned an error for valid-braces: HTTP/1.1 404 Not Found")))
  (should (equal (config-test/codewars-fetch "HTTP/1.1 200 OK\n\n{\"id\":")
                 '(nil "Codewars sent unreadable data for valid-braces"))))

(ert-deftest config-test/codewars-fetch-delivers-the-kata ()
  (let ((outcome (config-test/codewars-fetch config-test/codewars-kata-response)))
    (should-not (cadr outcome))
    (should (equal (alist-get 'slug (car outcome)) "valid-braces"))))

(ert-deftest config-test/codewars-fetch-reports-once-even-if-url-calls-back-twice ()
  (let ((calls 0))
    (cl-letf (((symbol-function 'url-retrieve) #'config-test/codewars-hold-request))
      (codewars/fetch-kata "valid-braces"
                           (lambda (&rest _) (setq calls (1+ calls))))
      (pcase-let ((`(,_buffer ,callback ,cbargs) config-test/codewars-held))
        ;; A connection failure reaches url's callback twice.
        (dotimes (_ 2)
          (with-temp-buffer
            (apply callback '(:error (error connection-failed)) cbargs)))))
    (should (= calls 1))))

(ert-deftest config-test/codewars-fetch-gives-up-after-the-timeout ()
  (let ((codewars--request-timeout 0.05)
        (outcome 'pending))
    (cl-letf (((symbol-function 'url-retrieve) #'config-test/codewars-hold-request))
      (codewars/fetch-kata "valid-braces"
                           (lambda (kata error) (setq outcome (list kata error))))
      (with-timeout (5 (ert-fail "fetch never gave up"))
        (while (eq outcome 'pending)
          (sit-for 0.01))))
    (should-not (car outcome))
    (should (string-match-p "did not answer for valid-braces" (cadr outcome)))))

(ert-deftest config-test/codewars-pull-creates-project-when-the-kata-arrives ()
  (config-test/codewars-with-root
    (let ((opened nil))
      (cl-letf (((symbol-function 'url-retrieve) #'config-test/codewars-hold-request)
                ((symbol-function 'completing-read) (lambda (&rest _) "rust"))
                ((symbol-function 'find-file) (lambda (file) (setq opened file))))
        (codewars/pull "valid-braces")
        (should-not (file-exists-p (expand-file-name "valid-braces" root)))
        (config-test/codewars-deliver config-test/codewars-kata-response)
        (should (file-exists-p (expand-file-name "valid-braces/solution.rs" root)))
        (should (equal opened (expand-file-name "valid-braces/solution.rs" root)))))))

(ert-deftest config-test/codewars-pull-reports-failure-and-creates-nothing ()
  (config-test/codewars-with-root
    (let ((reported nil))
      (cl-letf (((symbol-function 'url-retrieve) #'config-test/codewars-hold-request)
                ((symbol-function 'message)
                 (lambda (fmt &rest args) (setq reported (apply #'format fmt args)))))
        (codewars/pull "valid-braces")
        (config-test/codewars-deliver "HTTP/1.1 404 Not Found\n\n{}"
                                      '(:error (error http 404))))
      (should (equal reported
                     "Codewars returned an error for valid-braces: HTTP/1.1 404 Not Found"))
      (should-not (file-exists-p (expand-file-name "valid-braces" root))))))

(ert-deftest config-test/codewars-extension-follows-language-table ()
  (should (equal (codewars/extension-for "javascript") "js"))
  (should (equal (codewars/extension-for "cpp") "cpp"))
  (should (equal (codewars/extension-for "elm") "elm")))

(ert-deftest config-test/codewars-pull-creates-project-and-keeps-solution ()
  (config-test/codewars-with-root
    (let ((opened nil))
      (cl-letf (((symbol-function 'codewars/fetch-kata)
                 (lambda (_slug callback)
                   (funcall callback config-test/codewars-kata nil)))
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
                 (lambda (_slug callback)
                   (funcall callback config-test/codewars-kata nil)))
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

(ert-deftest config-test/codewars-haskell-test-default-loads-both-files ()
  (should (equal (cdr (assoc "haskell"
                            (default-value 'codewars/test-commands)))
                 "ghc -ignore-dot-ghci solution.hs Test.hs -e Main.main")))

(ert-deftest config-test/codewars-haskell-test-supports-named-solution-module ()
  (skip-unless (executable-find "ghc"))
  (config-test/codewars-with-root
    (let ((default-directory root))
      (with-temp-file (expand-file-name "solution.hs" root)
        (insert "module Sums (example) where\nexample :: Int\nexample = 7\n"))
      (with-temp-file (expand-file-name "Test.hs" root)
        (insert "module Main where\nimport Sums (example)\nmain :: IO ()\nmain = if example == 7 then putStrLn \"PASS\" else fail \"wrong result\"\n"))
      (with-temp-buffer
        (should (zerop (call-process "ghc" nil (current-buffer) nil
                                     "-ignore-dot-ghci" "solution.hs" "Test.hs"
                                     "-e" "Main.main")))
        (should (string-match-p "PASS" (buffer-string)))))))

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
  ;; A function-shaped autoload is not enough: the feature module is not
  ;; an installed `codewars' library, so that autoload cannot be resolved.
  (should-not (autoloadp (symbol-function 'hydra-codewars/body)))
  (should (eq (key-binding (kbd "C-x C-h K")) 'hydra-codewars/body))
  (save-window-excursion
    (unwind-protect
        (progn
          (execute-kbd-macro (kbd "C-x C-h K q"))
          (should-not hydra-curr-map))
      (hydra-keyboard-quit))))

(ert-deftest config-test/codewars-menu-dispatches-pull ()
  (let ((called nil))
    (cl-letf (((symbol-function 'codewars/pull)
               (lambda () (interactive) (setq called t))))
      (save-window-excursion
        (unwind-protect
            (progn
              (execute-kbd-macro (kbd "C-x C-h K p"))
              (should called)
              (should-not hydra-curr-map))
          (hydra-keyboard-quit))))))

;;; codewars-tests.el ends here
