;;; codewars.el --- Pull Codewars kata into local projects -*- lexical-binding: t; -*-

;; Pulling uses the public Codewars API, which needs no login.  Test and
;; submission run through the trainer's runner, which needs your browser
;; session, so `codewars/open-trainer' hands those steps to the browser.

(require 'json)
(require 'url)
(require 'subr-x)

(defgroup codewars nil
  "Local Codewars kata projects."
  :group 'tools)

(defcustom codewars/directory (expand-file-name "codewars/" "~")
  "Directory that holds one project directory per pulled kata."
  :type 'directory :group 'codewars)

(defcustom codewars/default-language "haskell"
  "Language preselected when pulling a kata that offers it."
  :type 'string :group 'codewars)

(defcustom codewars/test-commands
  '(("haskell" . "ghc -ignore-dot-ghci solution.hs Test.hs -e Main.main"))
  "Alist mapping a Codewars language name to the command `codewars/test' runs.
Each command runs in the kata's project directory.  The Haskell default
loads solution.hs and a user-written Test.hs containing Main.main; passing
both files explicitly also supports a differently named solution module.
Languages without an entry are prompted for."
  :type '(alist :key-type string :value-type string) :group 'codewars)

(defconst codewars/base-url "https://www.codewars.com"
  "Origin of the Codewars website and its public API.")

(defconst codewars/extensions
  '(("javascript" . "js") ("typescript" . "ts") ("python" . "py")
    ("ruby" . "rb") ("rust" . "rs") ("haskell" . "hs") ("go" . "go")
    ("java" . "java") ("csharp" . "cs") ("cpp" . "cpp") ("c" . "c")
    ("coffeescript" . "coffee") ("elixir" . "ex") ("php" . "php")
    ("swift" . "swift") ("scala" . "scala") ("lua" . "lua")
    ("julia" . "jl") ("dart" . "dart") ("cobol" . "cob"))
  "File extensions for Codewars language names.
Languages not listed here use their own name as the extension.")

(defconst codewars--metadata-file ".codewars"
  "File in each project that records the kata and the chosen language.")

(defun codewars--trust-directory ()
  "Trust `codewars/directory' so Eglot diagnostics run in kata projects.
Pulled solutions are your own code, like the development trees that
`modules/feat/editor/emacs.el' trusts.  Without this, Flymake's Eglot
backend stays off in every kata."
  (add-to-list 'trusted-content
               (abbreviate-file-name
                (file-name-as-directory (expand-file-name codewars/directory)))))

(codewars--trust-directory)

(defun codewars/slug-from-input (input)
  "Return the kata slug or id named by INPUT, which may be a URL."
  (let ((text (string-trim input)))
    (cond
     ((string-match "codewars\\.com/kata/\\([^/?#[:space:]]+\\)" text)
      (match-string 1 text))
     ((string-match-p "\\`[A-Za-z0-9_-]+\\'" text) text)
     (t (user-error "Not a Codewars kata slug or URL: %s" input)))))

(defconst codewars--request-timeout 20
  "Seconds `codewars/fetch-kata' waits for Codewars before giving up.")

(defun codewars--response-kata (slug)
  "Return (KATA . nil) or (nil . MESSAGE) for the response in this buffer.
Decide from the buffer, not from `url-retrieve's status: an HTTP error also
sets an :error status, and a connection failure leaves the buffer empty."
  (goto-char (point-min))
  (cond
   ((looking-at "HTTP/[0-9.]+ 2")
    (re-search-forward "\n\n" nil t)
    (condition-case nil
        (cons (json-parse-buffer :object-type 'alist :array-type 'list
                                 :null-object nil :false-object nil)
              nil)
      (json-error
       (cons nil (format "Codewars sent unreadable data for %s" slug)))))
   ((looking-at "HTTP/")
    (cons nil (format "Codewars returned an error for %s: %s" slug
                      (buffer-substring-no-properties
                       (point) (line-end-position)))))
   ;; No status line: the connection itself failed.
   (t (cons nil (format "Could not reach Codewars for %s" slug)))))

(defun codewars--fetch-kata-finish (request buffer callback kata error)
  "Finish REQUEST once: cancel its timer, discard BUFFER, call CALLBACK.
REQUEST is (DONE . TIMER).  Later calls for the same REQUEST do nothing, so a
request reports exactly once even if `url-retrieve' calls back twice."
  (unless (car request)
    (setcar request t)
    (when (timerp (cdr request)) (cancel-timer (cdr request)))
    (when (buffer-live-p buffer) (kill-buffer buffer))
    (funcall callback kata error)))

(defun codewars--fetch-kata-done (_status slug callback request)
  "Handle the response for kata SLUG; see `codewars/fetch-kata'."
  (unless (car request)
    (let ((result (codewars--response-kata slug)))
      (codewars--fetch-kata-finish request (current-buffer) callback
                                   (car result) (cdr result)))))

(defun codewars--fetch-kata-timed-out (buffer slug callback request)
  "Give up on the request in BUFFER for kata SLUG and report a timeout."
  (unless (car request)
    (let ((process (and (buffer-live-p buffer) (get-buffer-process buffer))))
      (when process
        ;; Silence the sentinel first so the abandoned request cannot report.
        (set-process-sentinel process #'ignore)
        (delete-process process)))
    (codewars--fetch-kata-finish
     request buffer callback nil
     (format "Codewars did not answer for %s within %s seconds"
             slug codewars--request-timeout))))

(defun codewars/fetch-kata (slug callback)
  "Fetch the public API record for kata SLUG without blocking Emacs.
Call CALLBACK exactly once: with (KATA nil) on success, or with (nil MESSAGE)
when the request fails or takes longer than `codewars--request-timeout'."
  (let* ((url (format "%s/api/v1/code-challenges/%s"
                      codewars/base-url (url-hexify-string slug)))
         (url-request-extra-headers '(("Accept" . "application/json")))
         (request (cons nil nil))
         (buffer (url-retrieve url #'codewars--fetch-kata-done
                               (list slug callback request) t t)))
    (unless (car request)
      (setcdr request (run-at-time codewars--request-timeout nil
                                   #'codewars--fetch-kata-timed-out
                                   buffer slug callback request)))
    buffer))

(defun codewars/extension-for (language)
  "Return the file extension used for LANGUAGE."
  (or (cdr (assoc language codewars/extensions)) language))

(defun codewars/project-directory (kata)
  "Return the project directory for KATA, a record from the API."
  (expand-file-name (alist-get 'slug kata) codewars/directory))

(defun codewars--write-readme (kata directory)
  "Write KATA's title, rank, link, and description into DIRECTORY."
  (with-temp-file (expand-file-name "README.md" directory)
    (insert (format "# %s\n\n" (alist-get 'name kata)))
    (insert (format "- Rank: %s\n" (alist-get 'name (alist-get 'rank kata))))
    (insert (format "- Link: %s/kata/%s\n\n"
                    codewars/base-url (alist-get 'slug kata)))
    (insert (or (alist-get 'description kata) "")
            "\n")))

(defun codewars--write-metadata (meta directory)
  "Write the plist META into DIRECTORY's metadata file."
  (with-temp-file (expand-file-name codewars--metadata-file directory)
    (prin1 meta (current-buffer))
    (insert "\n")))

(defun codewars/read-metadata ()
  "Return the current project's metadata plist, with :directory added."
  (let ((root (locate-dominating-file default-directory
                                      codewars--metadata-file)))
    (unless root
      (user-error "Not inside a Codewars kata project"))
    (with-temp-buffer
      (insert-file-contents (expand-file-name codewars--metadata-file root))
      (append (read (current-buffer)) (list :directory root)))))

(defun codewars/pull (input)
  "Pull the kata named by INPUT (slug, id, or URL) into a local project.
The request runs in the background.  When the kata arrives, ask for the
language, create the project directory, its README, and an empty solution
file, then open the solution."
  (interactive "sKata slug or URL: ")
  (codewars--trust-directory)
  (let ((slug (codewars/slug-from-input input)))
    (message "Fetching Codewars kata %s..." slug)
    (codewars/fetch-kata slug #'codewars--pull-fetched)))

(defun codewars--pull-fetched (kata error)
  "Create the project for KATA, or report ERROR, once the fetch has finished."
  (if error
      (message "%s" error)
    (codewars--create-project kata)))

(defun codewars--create-project (kata)
  "Ask for the language of KATA, then create its project and open the solution."
  (let* ((languages (alist-get 'languages kata))
         (default (if (member codewars/default-language languages)
                      codewars/default-language
                    (car languages)))
         (language (completing-read "Language: " languages nil t nil nil
                                    default))
         (directory (file-name-as-directory
                     (codewars/project-directory kata)))
         (solution (expand-file-name
                    (format "solution.%s" (codewars/extension-for language))
                    directory)))
    (make-directory directory t)
    (codewars--write-readme kata directory)
    (codewars--write-metadata (list :id (alist-get 'id kata)
                                    :slug (alist-get 'slug kata)
                                    :name (alist-get 'name kata)
                                    :language language)
                              directory)
    (unless (file-exists-p solution)
      (write-region "" nil solution))
    (find-file solution)
    (message "Pulled %s (%s) into %s" (alist-get 'name kata) language directory)))

(defun codewars/test ()
  "Run the test command for the current kata's language in its project.
The command comes from `codewars/test-commands', or is prompted for."
  (interactive)
  (let* ((meta (codewars/read-metadata))
         (language (plist-get meta :language))
         (command (or (cdr (assoc language codewars/test-commands))
                      (read-shell-command
                       (format "Test command for %s: " language))))
         (default-directory (plist-get meta :directory)))
    (compile command)))

(defun codewars/open-description ()
  "Open the current kata's README."
  (interactive)
  (let ((meta (codewars/read-metadata)))
    (find-file (expand-file-name "README.md" (plist-get meta :directory)))))

(defun codewars/trainer-url (meta)
  "Return the trainer URL for the kata described by META."
  (format "%s/kata/%s/train/%s"
          codewars/base-url (plist-get meta :id) (plist-get meta :language)))

(defun codewars/open-trainer ()
  "Open the current kata's trainer in the browser.
Use it for Attempt and Submit, which need your logged-in session."
  (interactive)
  (browse-url (codewars/trainer-url (codewars/read-metadata))))

;; This file is loaded by `mod/import', not installed as a package on
;; `load-path'.  Define the menu eagerly through Hydra; deferring it under
;; `codewars' would autoload a library Emacs cannot locate.
(use-package hydra
  :ensure nil
  :demand t
  :hydra (hydra-codewars
          (:color blue)
          "
Codewars: _p_ pull  _t_ test  _d_ description  _o_ open trainer (attempt, submit)  _q_ quit"
          ("p" codewars/pull)
          ("t" codewars/test)
          ("d" codewars/open-description)
          ("o" codewars/open-trainer)
          ("q" nil)))
(keymap-global-set "C-x C-h K" #'hydra-codewars/body)

;;; codewars.el ends here
