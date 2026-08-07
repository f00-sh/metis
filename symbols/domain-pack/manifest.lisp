;;;; domain-pack — extra domain knowledge pack for the mind KB
(in-package :cl-user)

(let* ((path (or (and (boundp '*symbol-load-path*)
                      (symbol-value '*symbol-load-path*))
                 (uiop:pathname-directory-pathname *load-truename*)))
       (pack (merge-pathnames "pack.lisp" path)))
  (metis.symbols:register-symbol!
   :id "domain-pack"
   :name "Domain Pack"
   :version "1.0.0"
   :description "Load the bundled domain knowledge pack into the live mind."
   :capabilities '(:domain :tool :domain-pack)
   :priority 50
   :path path
   :hooks (metis.symbols:define-symbol-hooks
            :activate (lambda (rec)
                        (when (and (find-package :metis) metis:*mind*)
                          (metis::domain-pack-load metis:*mind* pack)
                          (when (fboundp 'metis::register-tool)
                            (metis::register-tool
                             metis:*mind* 'domain-pack-load
                             (lambda ()
                               (metis::domain-pack-load metis:*mind* pack))
                             :doc "Reload domain-pack knowledge"
                             :safe t)))
                        (setf (getf (metis.symbols:sr-meta rec) :activated) t)
                        t)
            :deactivate (lambda (rec) (declare (ignore rec)) t))
   :meta (list :kind :category :category :domain-pack :pack (namestring pack))))
