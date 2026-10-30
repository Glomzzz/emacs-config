;;; menus.el --- Hydra menus for built-in editing commands -*- lexical-binding: t; -*-

(require 'packages)

;; Rectangle menu adapted from the hydra wiki's "Rectangle 2" example.  The
;; wiki's `rectangle-*' movement commands are not in Emacs 31, so the menu uses
;; the ordinary movement commands, which extend the rectangle in mark mode.
;; `C-x SPC' keeps its built-in meaning, `rectangle-mark-mode'.
(use-package rect
  :ensure nil
  :after hydra
  :bind (("C-x C-h r" . hydra-rectangle/body))
  :hydra (hydra-rectangle
          (:body-pre (rectangle-mark-mode 1)
           :color pink
           :hint nil
           :post (deactivate-mark))
          "
 ^_k_^       _w_ copy      _o_pen       _N_umber lines
_h_   _l_     _y_ank        _t_ype       _e_xchange point
 ^_j_^       _d_ kill      _c_lear      _r_eset region mark
 ^^          _u_ undo      _q_uit"
          ("k" previous-line)
          ("j" next-line)
          ("h" backward-char)
          ("l" forward-char)
          ("d" kill-rectangle)
          ("y" yank-rectangle)
          ("w" copy-rectangle-as-kill)
          ("o" open-rectangle)
          ("t" string-rectangle)
          ("c" clear-rectangle)
          ("e" exchange-point-and-mark)
          ("N" rectangle-number-lines)
          ("r" (if (region-active-p)
                   (deactivate-mark)
                 (rectangle-mark-mode 1)))
          ("u" undo)
          ("q" nil :color blue)))

;; Keyboard macro menu adapted from the hydra wiki's "Macro" example.  Opening
;; the menu ends a macro that is still being recorded.
(use-package kmacro
  :ensure nil
  :after hydra
  :bind (("C-x C-h k" . hydra-macro/body))
  :hydra (hydra-macro
          (:hint nil
           :color pink
           :pre (when defining-kbd-macro
                  (kmacro-end-macro 1)))
          "
 Cycle: _i_ previous  _k_ next  _j_ start  _l_ end or call   Basic: _e_ execute  _d_ delete  _o_ edit  _m_ step
 Insert: _n_ counter  _t_ set counter  _a_ add counter  _f_ format   Edit: _'_ last  _,_ kbd-macro  _s_ swap
 Save: _b_ name  _K_ bind key  _B_ insert defun  _x_ register  _r_ apply to region lines  _q_ quit"
          ("j" kmacro-start-macro :color blue)
          ("l" kmacro-end-or-call-macro-repeat)
          ("i" kmacro-cycle-ring-previous)
          ("k" kmacro-cycle-ring-next)
          ("r" apply-macro-to-region-lines)
          ("d" kmacro-delete-ring-head)
          ("e" kmacro-end-or-call-macro-repeat)
          ("o" kmacro-edit-macro-repeat)
          ("m" kmacro-step-edit-macro)
          ("s" kmacro-swap-ring)
          ("n" kmacro-insert-counter)
          ("t" kmacro-set-counter)
          ("a" kmacro-add-counter)
          ("f" kmacro-set-format)
          ("b" kmacro-name-last-macro)
          ("K" kmacro-bind-to-key)
          ("B" insert-kbd-macro)
          ("x" kmacro-to-register)
          ("'" kmacro-edit-macro)
          ("," edit-kbd-macro)
          ("q" nil :color blue)))

;;; menus.el ends here
