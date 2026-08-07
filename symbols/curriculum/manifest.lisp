;;;; curriculum — training curriculum apply for neural continuous train
(in-package :cl-user)

(let* ((path (or (and (boundp '*symbol-load-path*)
                      (symbol-value '*symbol-load-path*))
                 (uiop:pathname-directory-pathname *load-truename*)))
       (cur (merge-pathnames "curriculum.txt" path)))
  (metis.symbols:register-symbol!
   :id "curriculum"
   :name "Training Curriculum"
   :version "1.0.0"
   :description "Apply a text curriculum to continuous-train a named LM."
   :capabilities '(:train :tool :curriculum)
   :priority 50
   :path path
   :hooks (metis.symbols:define-symbol-hooks
            :activate (lambda (rec)
                        (when (and (find-package :metis) metis:*mind*
                                   (fboundp 'metis::register-tool))
                          (metis::register-tool
                           metis:*mind* 'curriculum-apply
                           (lambda (&optional name)
                             (metis::curriculum-apply
                              cur :name (or name "curriculum-lm")))
                           :doc "Train LM from curriculum.txt"
                           :schema '(&optional name)
                           :safe t))
                        (setf (getf (metis.symbols:sr-meta rec) :activated) t)
                        t)
            :deactivate (lambda (rec) (declare (ignore rec)) t))
   :meta (list :kind :category :category :curriculum
               :file (namestring cur))))
