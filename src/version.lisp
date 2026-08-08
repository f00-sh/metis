;;;; version.lisp
(in-package :metis)

(defparameter *metis-version* "4.5.0"
  "Semantic version of the Metis production cognitive architecture.")

(defparameter *metis-codename* "THEORY"
  "Release codename — install channels (curl/brew/AUR) on dual-facet THEORY base.")

(defparameter *metis-api-version* "v1")

(defun metis-version-string ()
  (format nil "Metis ~A (~A)" *metis-version* *metis-codename*))

(defun metis-build-info ()
  (list :version *metis-version*
        :codename *metis-codename*
        :api *metis-api-version*
        :lisp (lisp-implementation-type)
        :lisp-version (lisp-implementation-version)
        :features (remove-if-not
                   (lambda (f)
                     (member f '(:sbcl :threads :metis-production) :test #'eq))
                   *features*)))
