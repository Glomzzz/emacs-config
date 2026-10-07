;;; buffers.el --- Shared buffer-size policy -*- lexical-binding: t; -*-

(defgroup buffers nil
  "Resource limits shared by configuration features."
  :group 'convenience)

(defcustom buffers/feature-size-limit (* 2 1024 1024)
  "Maximum buffer size for optional editing and display features.
Nil disables the limit.  Size is measured in buffer characters."
  :type '(choice (const :tag "Unlimited" nil) natnum)
  :group 'buffers)

(defcustom buffers/color-preview-size-limit (* 1024 1024)
  "Maximum buffer size for color previews, or nil for no limit."
  :type '(choice (const :tag "Unlimited" nil) natnum)
  :group 'buffers)

(defun buffers/small-p (&optional limit)
  "Return non-nil when the current buffer is smaller than LIMIT.
An omitted LIMIT uses `buffers/feature-size-limit'."
  (let ((limit (or limit buffers/feature-size-limit)))
    (or (null limit) (< (buffer-size) limit))))

(provide 'buffers)
;;; buffers.el ends here
