;;; Directory Local Variables
;;; For more information see (info "(emacs) Directory Variables")


((nil
  (eval .
        ;; Auto-load the swiftpm project settings.
        (unless (featurep 'swiftpm-project-settings)
          (message "loading 'swiftpm-project-settings")
          ;; Make sure the project's own utils directory is in the load path,
          ;; but don't override any one the user might have set up.
          (add-to-list
           'load-path
           (concat
            (let ((dlff (dir-locals-find-file default-directory)))
              (if (listp dlff) (car dlff) (file-name-directory dlff)))
            "Utilities/Emacs")
           :append)
          (require 'swiftpm-project-settings)))))
