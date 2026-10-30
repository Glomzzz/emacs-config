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

;;; menus.el ends here
