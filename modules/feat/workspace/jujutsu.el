;;; jujutsu.el --- Jujutsu integration -*- lexical-binding: t; -*-

(require 'packages)

(packages/declare-vc 'majutsu
                     '(:url "https://github.com/0WD0/majutsu"
                       :vc-backend Git))
(use-package majutsu
  :ensure nil
  :commands (majutsu majutsu-log majutsu-dispatch)
  :bind (("C-x g" . majutsu-log)
         ("C-x M-g" . majutsu-dispatch)
         ("C-x j" . majutsu-log)
         ("C-x M-j" . majutsu-dispatch)))

;;; jujutsu.el ends here
