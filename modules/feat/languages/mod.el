;;; mod.el --- Shared language-support feature index -*- lexical-binding: t; -*-

;; These modules define the APIs consumed by files in `support/'.
(mod/import
 '("treesit.el"
   "format.el"
   "lsp.el"
   "debug.el"
   "support/"))

(treesit/enable-auto)

;;; mod.el ends here
