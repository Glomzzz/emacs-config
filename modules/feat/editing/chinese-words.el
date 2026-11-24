;;; chinese-words.el --- Chinese word motion through Jieba -*- lexical-binding: t; -*-

(require 'packages)
(require 'buffers)

;; `cns.el' is Elisp from upstream Git, declared like the other VC packages.
;; The segmenter is a native helper supplied by NixOS:
;; `pkgs/chinese-word-segmentation.nix' in the system flake installs `cnws'
;; and its Jieba dictionaries.
(packages/declare-vc
 'cns
 '(:url "https://github.com/kanglmf/emacs-chinese-word-segmentation"
   :vc-backend Git))

(declare-function cns-mode "cns" (&optional arg))
(defvar cns-prog)
(defvar cns-dict-directory)
(defvar cns-process)

(defconst chinese-words/program-name "cnws"
  "Executable installed by the `chinese-word-segmentation' Nix package.")

(defun chinese-words/program ()
  "Return the segmenter executable on `exec-path', or nil when absent."
  (executable-find chinese-words/program-name))

(defun chinese-words/dictionary-directory (program)
  "Return the Jieba dictionary directory installed beside PROGRAM.
The Nix package keeps the binary in `bin/' and the dictionaries in
`share/chinese-word-segmentation/dict/'."
  (expand-file-name "../share/chinese-word-segmentation/dict"
                    (file-name-directory (file-truename program))))

(defun chinese-words/configure ()
  "Point `cns' at the installed segmenter and its dictionaries.
Return non-nil when the segmenter was found."
  (when-let* ((program (chinese-words/program)))
    (setq cns-prog program
          cns-dict-directory (chinese-words/dictionary-directory program))
    t))

(defun chinese-words/enable-maybe ()
  "Enable `cns-mode' in small buffers that contain Han characters.
Do nothing until both the segmenter and `cns' are available, so opening
Chinese text on a machine without them behaves as usual."
  (when (and (not (minibufferp))
             (not (derived-mode-p 'special-mode 'comint-mode))
             (buffers/small-p)
             (save-excursion
               (goto-char (point-min))
               (re-search-forward "\\cC" nil t))
             (chinese-words/configure)
             (require 'cns nil t))
    (cns-mode 1)))

(add-hook 'find-file-hook #'chinese-words/enable-maybe)

(defvar-local chinese-words--enable-scheduled nil
  "Non-nil while `chinese-words/enable-pending' is queued for this buffer.")

(defun chinese-words/enable-pending (buffer)
  "Run `chinese-words/enable-maybe' in BUFFER if it is still live."
  (when (buffer-live-p buffer)
    (with-current-buffer buffer
      (setq chinese-words--enable-scheduled nil)
      (chinese-words/enable-maybe))))

(defun chinese-words/note-insertion (beg end _length)
  "Schedule Chinese word motion when inserted text contains Han characters.
A file that opened as Latin text would otherwise keep Emacs' word motion for
Chinese typed into it, which moves across the whole run at once.  The timer
keeps the segmenter start out of the change hook."
  (when (and (< beg end)
             (not chinese-words--enable-scheduled)
             (not (bound-and-true-p cns-mode))
             (buffers/small-p)
             (string-match-p "\\cC" (buffer-substring-no-properties beg end))
             (chinese-words/program))
    (setq chinese-words--enable-scheduled t)
    (run-at-time 0 nil #'chinese-words/enable-pending (current-buffer))))

(add-hook 'after-change-functions #'chinese-words/note-insertion)

(defun chinese-words/discard-stopped-process (&rest _)
  "Delete the segmenter process once `cns-stop-process' has asked it to exit.
Emacs reports a process as live until it has processed the exit.  Without
this, the next Chinese buffer reuses a helper that no longer reads its input
and waits for a reply that never arrives."
  (when (process-live-p cns-process)
    (delete-process cns-process)))

(use-package cns
  :ensure nil
  :commands (cns-mode)
  :custom
  ;; One segmenter process per Emacs session; no server to keep running.
  (cns-process-type 'shell)
  ;; Debug output would otherwise accumulate in the process buffer.
  (cns-debug nil))

(with-eval-after-load 'cns
  (advice-add 'cns-stop-process :after #'chinese-words/discard-stopped-process))

;; `cns' finds word starts with `re-search-backward', which signals
;; `search-failed' when only punctuation or nothing precedes point, so M-b
;; at the start of a buffer errored.  At that boundary, stop at `point-min'
;; as the built-in `backward-word' does.
(defun chinese-words/word-start-before-point ()
  "Return the start of the nearest word before point, or `point-min'."
  (save-excursion
    (if (re-search-backward "\\<" nil t) (point) (point-min))))

(defun chinese-words/get-word-position (direction)
  "Return the position after word movement towards DIRECTION.
Replaces `cns-get-word-position'; see `chinese-words/word-start-before-point'."
  (save-excursion
    (if (eq direction 'forward)
        (progn (forward-word) (point))
      (chinese-words/word-start-before-point))))

(defun chinese-words/backward-word-safe-1 ()
  "Move to the nearer word start found by regexp or by `backward-word'.
Replaces `cns-backward-word-safe-1'; see `chinese-words/word-start-before-point'."
  (let ((pos-by-regex (chinese-words/word-start-before-point))
        (pos-by-word (save-excursion (backward-word) (point))))
    (goto-char (max pos-by-regex pos-by-word))))

(with-eval-after-load 'cns
  (advice-add 'cns-get-word-position :override #'chinese-words/get-word-position)
  (advice-add 'cns-backward-word-safe-1 :override
              #'chinese-words/backward-word-safe-1))

(provide 'chinese-words)

;;; chinese-words.el ends here
