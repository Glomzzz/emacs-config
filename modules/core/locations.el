;;; locations.el --- Machine-specific directories and mount policy -*- lexical-binding: t; -*-

(require 'seq)

(defgroup locations nil
  "Machine-specific paths shared by configuration features."
  :group 'environment)

(defcustom locations/projects-directory "~/git/"
  "Default project directory for navigation."
  :type 'directory :group 'locations)
(defcustom locations/desktop-directory "~/Desktop/"
  "Desktop directory for file navigation."
  :type 'directory :group 'locations)
(defcustom mounts/android-mount-directory "~/mnt/android/"
  "Mount point for the Android phone."
  :type 'directory :group 'locations)
(defcustom mounts/mac-mini-mount-directory "~/mnt/mac-mini/"
  "Mount point for the Mac-mini share."
  :type 'directory :group 'locations)
(defcustom mounts/mac-mini-host "mac-mini"
  "SSH host alias for Mac-mini."
  :type 'string :group 'locations)
(defcustom mounts/mac-mini-remote-home-directory "~/"
  "Remote home corresponding to the mounted Mac-mini share.
Keep this as a remote path; never expand it against the local user's home."
  :type 'string :group 'locations)
(defcustom locations/additional-unreliable-directories nil
  "Other local mounts that must not be probed by periodic editor features."
  :type '(repeat directory) :group 'locations)

(defun locations/unreliable-directories ()
  "Return expanded unreliable mount paths using current settings."
  (mapcar (lambda (path) (file-name-as-directory (expand-file-name path)))
          (append (list mounts/android-mount-directory
                        mounts/mac-mini-mount-directory)
                  locations/additional-unreliable-directories)))

(defun locations/unreliable-path-p (path)
  "Return non-nil if PATH is on an unreliable mount, without filesystem I/O."
  (when path
    (let ((expanded (expand-file-name path)))
      (seq-some (lambda (prefix)
                  (or (equal (directory-file-name prefix)
                             (directory-file-name expanded))
                      (string-prefix-p prefix expanded)))
                (locations/unreliable-directories)))))

(provide 'locations)
;;; locations.el ends here
