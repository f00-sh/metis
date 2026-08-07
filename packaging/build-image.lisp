;;;; build-image.lisp — save a Metis SBCL core
(defpackage :metis.packaging
  (:use :cl)
  (:export #:build-image))

(in-package :metis.packaging)

(defun build-image (output-path)
  "Load Metis and save a core image."
  (let* ((here (uiop:pathname-directory-pathname
                (or *load-pathname* *default-pathname-defaults*)))
         (root (truename (merge-pathnames "../" here))))
    (pushnew root asdf:*central-registry*)
    (asdf:load-system :metis)
    (let ((out (uiop:ensure-pathname output-path
                                     :want-file t
                                     :ensure-directories-exist t))
          (ver (funcall (find-symbol "METIS-VERSION-STRING" :metis))))
      ;; remove broken placeholder if any
      (when (probe-file out)
        (ignore-errors (uiop:delete-file-if-exists out))
        (ignore-errors
          (when (uiop:directory-exists-p out)
            (uiop:delete-directory-tree out :validate t :if-does-not-exist :ignore))))
      (push (lambda ()
              (format t "~&Metis ~A core image ready.~%" ver)
              (format t "Try (metis:boot) or (metis:symbols-boot!).~%"))
            sb-ext:*init-hooks*)
      (sb-ext:save-lisp-and-die
       (namestring out)
       :executable nil
       :toplevel #'sb-impl::toplevel-init
       :save-runtime-options t)
      out)))
