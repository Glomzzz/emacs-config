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

(use-package cns
  :ensure nil
  :commands (cns-mode)
  :custom
  ;; One segmenter process per Emacs session; no server to keep running.
  (cns-process-type 'shell)
  ;; Debug output would otherwise accumulate in the process buffer.
  (cns-debug nil))

(provide 'chinese-words)

;;; chinese-words.el ends here
