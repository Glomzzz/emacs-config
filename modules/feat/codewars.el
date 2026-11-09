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

(defcustom codewars/test-commands nil
  "Alist mapping a Codewars language name to the command `codewars/test' runs.
Each command runs in the kata's project directory.  Languages without an
entry are prompted for."
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

(defun codewars/fetch-kata (slug)
  "Return the public API record for kata SLUG as an alist."
  (let* ((url (format "%s/api/v1/code-challenges/%s"
                      codewars/base-url (url-hexify-string slug)))
         (url-request-extra-headers '(("Accept" . "application/json")))
         (buffer (url-retrieve-synchronously url t t 20)))
    (unless buffer
      (user-error "Codewars request timed out: %s" url))
    (unwind-protect
        (with-current-buffer buffer
          (goto-char (point-min))
          (unless (looking-at "HTTP/[0-9.]+ 2")
            (user-error "Codewars returned an error for %s: %s" slug
                        (buffer-substring-no-properties
                         (point) (line-end-position))))
          (re-search-forward "\n\n" nil t)
          (json-parse-buffer :object-type 'alist :array-type 'list
                             :null-object nil :false-object nil))
      (kill-buffer buffer))))

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
Create the project directory, its README, and an empty solution file for
the chosen language, then open the solution."
  (interactive "sKata slug or URL: ")
  (codewars--trust-directory)
  (let* ((kata (codewars/fetch-kata (codewars/slug-from-input input)))
         (languages (alist-get 'languages kata))
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

(use-package codewars
  :ensure nil
  :no-require t
  :after hydra
  :bind (("C-x C-h K" . hydra-codewars/body))
  :hydra (hydra-codewars
          (:color blue)
          "
Codewars: _p_ pull  _t_ test  _d_ description  _o_ open trainer (attempt, submit)  _q_ quit"
          ("p" codewars/pull)
          ("t" codewars/test)
          ("d" codewars/open-description)
          ("o" codewars/open-trainer)
          ("q" nil)))

;;; codewars.el ends here
