;;; leetcode.el --- LeetCode preferences -*- lexical-binding: t; -*-

(use-package leetcode
  :commands (leetcode leetcode-daily)
  :preface
  (require 'aio)
  (require 'cl-lib)
  (require 'gnutls)
  (require 'let-alist)
  (require 'sqlite)
  (require 'subr-x)
  (require 'url-cookie)
  (require 'url-http)

  (defvar url-http-end-of-headers)

  (defgroup my/leetcode-cn nil
    "Helpers for restoring LeetCode CN cookies into Emacs."
    :group 'leetcode)

  (defcustom my/leetcode-cn-cookie-db
    (expand-file-name "~/.config/google-chrome-beta/Default/Cookies")
    "Path to the Chromium cookie database that holds LeetCode CN cookies."
    :type 'file
    :group 'my/leetcode-cn)

  (defcustom my/leetcode-cn-cookie-host-pattern "%leetcode.cn"
    "SQLite LIKE pattern used to select LeetCode CN cookies."
    :type 'string
    :group 'my/leetcode-cn)

  (defcustom my/leetcode-cn-wallet "kdewallet"
    "KWallet name used by Chromium to store its safe-storage password."
    :type 'string
    :group 'my/leetcode-cn)

  (defcustom my/leetcode-cn-wallet-folder "Chrome Keys"
    "KWallet folder that contains Chromium's safe-storage password."
    :type 'string
    :group 'my/leetcode-cn)

  (defcustom my/leetcode-cn-wallet-entry "Chrome Safe Storage"
    "KWallet entry that contains Chromium's safe-storage password."
    :type 'string
    :group 'my/leetcode-cn)

  (defun my/leetcode-cn--bytes (value)
    "Encode VALUE into a unibyte string."
    (copy-sequence (encode-coding-string value 'utf-8 t)))

  (defconst my/leetcode-cn--cookie-iv
    (my/leetcode-cn--bytes (make-string 16 ?\s))
    "Fixed IV used by Chromium's legacy Linux cookie encryption.")

  (defconst my/leetcode-cn--pbkdf2-input
    (my/leetcode-cn--bytes (concat "saltysalt" "\0\0\0\1"))
    "Single PBKDF2 block input for Chromium's Linux cookie key derivation.")

  (defconst my/leetcode-cn--windows-epoch-offset 11644473600
    "Seconds between the Windows epoch and the Unix epoch.")

  (defun my/leetcode-cn--call-process-string (program &rest args)
    "Run PROGRAM with ARGS and return its trimmed stdout."
    (when-let* ((executable (executable-find program)))
      (with-temp-buffer
        (when (eq 0 (apply #'call-process executable nil (current-buffer) nil args))
          (string-trim-right (buffer-string))))))

  (defun my/leetcode-cn--wallet-secret ()
    "Return Chromium's KWallet safe-storage password."
    (let ((secret (my/leetcode-cn--call-process-string
                   "kwallet-query"
                   "-f" my/leetcode-cn-wallet-folder
                   "-r" my/leetcode-cn-wallet-entry
                   my/leetcode-cn-wallet)))
      (unless (string-empty-p (or secret ""))
        secret)))

  (defun my/leetcode-cn--linux-cookie-key (password)
    "Derive Chromium's legacy Linux cookie key from PASSWORD."
    (substring
     (gnutls-hash-mac 'SHA1
                      (my/leetcode-cn--bytes (or password ""))
                      my/leetcode-cn--pbkdf2-input)
     0 16))

  (defun my/leetcode-cn--pkcs7-unpad (payload)
    "Remove PKCS#7 padding from PAYLOAD."
    (let* ((length (length payload))
           (padding (and (> length 0) (aref payload (1- length)))))
      (unless (and padding (> padding 0) (<= padding 16) (<= padding length))
        (error "Invalid Chromium cookie padding"))
      (dotimes (index padding)
        (unless (= (aref payload (- length 1 index)) padding)
          (error "Invalid Chromium cookie padding")))
      (substring payload 0 (- length padding))))

  (defun my/leetcode-cn--decrypt-cookie (encrypted-value db-version wallet-secret)
    "Decrypt ENCRYPTED-VALUE from a Chromium cookie database.
DB-VERSION is the schema version from the cookie database metadata.
WALLET-SECRET is Chromium's Linux safe-storage password."
    (let* ((format-tag (substring encrypted-value 0 3))
           (keys
            (pcase format-tag
              ("v10"
               (list (my/leetcode-cn--linux-cookie-key "peanuts")))
              ("v11"
               (delq nil
                     (list (and wallet-secret
                                (my/leetcode-cn--linux-cookie-key wallet-secret))
                           (my/leetcode-cn--linux-cookie-key ""))))
              (_ nil))))
      (catch 'decoded
        (dolist (key keys)
          (let* ((decrypted
                  (car (gnutls-symmetric-decrypt
                        'AES-128-CBC
                        key
                        (copy-sequence my/leetcode-cn--cookie-iv)
                        (substring encrypted-value 3))))
                 (unpadded (and decrypted
                                (ignore-errors
                                  (my/leetcode-cn--pkcs7-unpad decrypted))))
                 (value (and unpadded
                             (if (>= db-version 24)
                                 (and (>= (length unpadded) 32)
                                      (substring unpadded 32))
                               unpadded))))
            (when value
              (throw 'decoded value)))))))

  (defun my/leetcode-cn--expiry-string (expires-utc)
    "Convert Chromium EXPIRES-UTC into a cookie expiry string."
    (when (and (integerp expires-utc) (> expires-utc 0))
      (format-time-string
       "%a %b %d %H:%M:%S %Y GMT"
       (seconds-to-time
        (- (/ expires-utc 1000000) my/leetcode-cn--windows-epoch-offset))
       t)))

  (defun my/leetcode-cn--copy-cookie-db ()
    "Copy Chromium's cookie database to a temporary path and return it."
    (let ((temp-db (make-temp-file "leetcode-cn-cookies-" nil ".sqlite")))
      (copy-file my/leetcode-cn-cookie-db temp-db t)
      (dolist (suffix '("-wal" "-shm"))
        (let ((source (concat my/leetcode-cn-cookie-db suffix))
              (target (concat temp-db suffix)))
          (when (file-exists-p source)
            (copy-file source target t))))
      temp-db))

  (defun my/leetcode-cn--read-browser-cookies ()
    "Return LeetCode CN cookies from Chromium.
Each row is `(NAME VALUE EXPIRES DOMAIN PATH SECURE)`."
    (when (file-readable-p my/leetcode-cn-cookie-db)
      (let ((temp-db (my/leetcode-cn--copy-cookie-db)))
        (unwind-protect
            (let ((db (sqlite-open temp-db)))
              (unwind-protect
                  (let* ((db-version
                          (if-let* ((row (car (sqlite-select
                                               db
                                               "select value from meta where key = ?"
                                               ["version"]))))
                              (string-to-number (car row))
                            0))
                         (wallet-secret (my/leetcode-cn--wallet-secret))
                         (rows (sqlite-select
                                db
                                (concat
                                 "select host_key, name, value, encrypted_value, "
                                 "path, is_secure, expires_utc "
                                 "from cookies "
                                 "where host_key like ? "
                                 "order by length(path) desc, expires_utc desc")
                                (vector my/leetcode-cn-cookie-host-pattern)))
                         (seen (make-hash-table :test #'equal))
                         result)
                    (dolist (row rows)
                      (pcase-let ((`(,domain ,name ,value ,encrypted-value
                                              ,path ,is-secure ,expires-utc) row))
                        (let ((cookie-id (format "%s\0%s\0%s" domain path name)))
                          (unless (gethash cookie-id seen)
                            (let ((decoded
                                   (cond
                                    ((not (string-empty-p value)) value)
                                    ((and encrypted-value (>= (length encrypted-value) 3))
                                     (my/leetcode-cn--decrypt-cookie
                                      encrypted-value db-version wallet-secret)))))
                              (when decoded
                                (puthash cookie-id t seen)
                                (push (list name
                                            decoded
                                            (my/leetcode-cn--expiry-string expires-utc)
                                            domain
                                            path
                                            (not (zerop is-secure)))
                                      result)))))))
                    (nreverse result))
                (sqlite-close db)))
          (dolist (path (list temp-db (concat temp-db "-wal") (concat temp-db "-shm")))
            (when (file-exists-p path)
              (delete-file path)))))))

  (defun my/leetcode-cn-restore-cookies (&optional quiet)
    "Restore LeetCode CN cookies from Chromium into Emacs.
When QUIET is non-nil, suppress interactive status messages."
    (interactive)
    (condition-case err
        (let ((cookies (my/leetcode-cn--read-browser-cookies)))
          (if (null cookies)
              (unless quiet
                (user-error "No LeetCode CN cookies found in %s" my/leetcode-cn-cookie-db))
            (url-cookie-delete-cookies "leetcode\\.cn")
            (dolist (cookie cookies)
              (pcase-let ((`(,name ,value ,expires ,domain ,path ,secure) cookie))
                (url-cookie-store
                 name
                 value
                 expires
                 domain
                 path
                 secure)))
            (unless quiet
              (message "Restored %d LeetCode CN cookies" (length cookies)))
            cookies))
      (error
       (unless quiet
         (user-error "Unable to restore LeetCode CN cookies: %s"
                     (error-message-string err)))
       nil)))

  (defun my/leetcode-cn-refresh-before-command (&rest _)
    "Refresh LeetCode CN cookies before running `leetcode'."
    (my/leetcode-cn-restore-cookies t))

  (defun my/leetcode-cn-check-deps ()
    "Return non-nil when the LeetCode CN browser-backed login can run."
    (and (file-readable-p my/leetcode-cn-cookie-db)
         (executable-find "kwallet-query")
         (fboundp 'sqlite-open)
         (fboundp 'gnutls-hash-mac)
         (fboundp 'gnutls-symmetric-decrypt)))

  (aio-defun my/leetcode-cn-login ()
    "Restore LeetCode CN cookies from the local browser and refresh user data."
    (unless (my/leetcode-cn-restore-cookies t)
      (user-error "Unable to restore LeetCode CN cookies from %s"
                  my/leetcode-cn-cookie-db))
    (message "LeetCode CN fetching user data...")
    (aio-await (leetcode--fetch-user-status)))

  (defun my/leetcode-cn-apply-package-overrides ()
    "Retarget `leetcode.el' at LeetCode CN."
    (setq leetcode--domain "leetcode.cn"
          leetcode--url-base "https://leetcode.cn"
          leetcode--url-login (concat leetcode--url-base "/accounts/login")
          leetcode--url-api (concat leetcode--url-base "/api")
          leetcode--url-graphql (concat leetcode--url-base "/graphql/")
          leetcode--url-all-problems (concat leetcode--url-api "/problems/all/")
          leetcode--url-all-tags (concat leetcode--url-base "/problems/api/tags")
          leetcode--url-daily-challenge
          (concat
           "query questionOfToday { todayRecord { "
           "question { status title qid: questionFrontendId "
           "titleSlug: questionTitleSlug } } }")
          leetcode--url-submit (concat leetcode--url-base "/problems/%s/submit/")
          leetcode--url-problems-submission
          (concat leetcode--url-base "/problems/%s/submissions/")
          leetcode--url-check-submission
          (concat leetcode--url-base "/submissions/detail/%s/check/")
          leetcode--url-try
          (concat leetcode--url-base "/problems/%s/interpret_solution/")
          leetcode--url-problems (concat leetcode--url-base "/problems/%s/")
          leetcode--graphql-global-data
          (concat
           "query globalData { "
           "userStatus { userId: userSlug username isPremium } }")
          leetcode--graphql-console-panel-config
          (concat
           "query consolePanelConfig($titleSlug: String!) { "
           "question(titleSlug: $titleSlug) { "
           "questionId questionFrontendId questionTitle "
           "enableRunCode enableSubmit enableTestMode "
           "exampleTestcaseList metaData } }"))
    (defalias 'leetcode--check-deps #'my/leetcode-cn-check-deps)
    (defalias 'leetcode--login #'my/leetcode-cn-login))

  (aio-defun my/leetcode-cn-daily ()
    "Open the LeetCode CN daily challenge."
    (interactive)
    (aio-await (leetcode--ensure-login))
    (let* ((url-request-method "POST")
           (url-request-extra-headers `(,@(aio-await (leetcode--common-extra-headers))
                                        ,(leetcode--referer leetcode--url-login)))
           (url-request-data
            (json-encode
             `((operationName . "questionOfToday")
               (query . ,leetcode--url-daily-challenge)))))
      (with-current-buffer (url-retrieve-synchronously leetcode--url-graphql)
        (goto-char url-http-end-of-headers)
        (let-alist (json-read)
          (if (and .data.todayRecord (> (length .data.todayRecord) 0))
              (let-alist (aref .data.todayRecord 0)
                (leetcode-show-problem .question.qid))
            (user-error "LeetCode CN daily challenge is unavailable"))))))

  :custom
  (leetcode-prefer-language "python3")
  (leetcode-prefer-sql "mysql")
  (leetcode-save-solutions t)
  (leetcode-directory "~/leetcode")
  :config
  (my/leetcode-cn-apply-package-overrides)
  (defalias 'leetcode-daily #'my/leetcode-cn-daily)
  (advice-add 'leetcode :before #'my/leetcode-cn-refresh-before-command)
  (advice-add 'leetcode-daily :before #'my/leetcode-cn-refresh-before-command)
  (my/leetcode-cn-restore-cookies t))
