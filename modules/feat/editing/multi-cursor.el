;;; multi-cursor.el --- Multiple-cursor editing -*- lexical-binding: t; -*-

(require 'packages)

;; The direct keys stay bound.  `C-x C-h m' opens the same commands as a menu
;; that stays active, so repeated marking does not need the chords each time.
(packages/declare 'multiple-cursors)
(use-package multiple-cursors
  :ensure nil
  :init
  (setq mc/list-file (cache/file "multiple-cursors.el"))
  (unless (file-exists-p (file-name-directory mc/list-file))
    (make-directory (file-name-directory mc/list-file) t))
  :after hydra
  :bind (("C-c C-S-c" . mc/edit-lines)
         ("C->"         . mc/mark-next-like-this)
         ("C-<"         . mc/mark-previous-like-this)
         ("C-c C-<"     . mc/mark-all-like-this)
         ("C-\""        . mc/skip-to-next-like-this)
         ("C-:"         . mc/skip-to-previous-like-this)
         ("C-x C-h m"   . hydra-multiple-cursors/body))
  :hydra (hydra-multiple-cursors (:hint nil)
                                 "
 _n_: next _p_: previous _s_: skip next _S_: skip previous _u_: unmark next _U_: unmark previous  _a_: all  _l_: lines  _q_: quit"
                                 ("n" mc/mark-next-like-this)
                                 ("p" mc/mark-previous-like-this)
                                 ("s" mc/skip-to-next-like-this)
                                 ("S" mc/skip-to-previous-like-this)
                                 ("u" mc/unmark-next-like-this)
                                 ("U" mc/unmark-previous-like-this)
                                 ("a" mc/mark-all-like-this "all" :color blue)
                                 ("l" mc/edit-lines "lines" :color blue)
                                 ("q" nil "quit" :color blue)))


;;; multi-cursor.el ends here
