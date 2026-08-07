;;;; cpu-nn — built-in pure Common Lisp neural compute symbol
(in-package :cl-user)

(let* ((path (or (and (boundp '*symbol-load-path*)
                      (symbol-value '*symbol-load-path*))
                 (uiop:pathname-directory-pathname *load-truename*)))
       (be (metis.symbols:make-cpu-nn-backend)))
  (metis.symbols:register-symbol!
   :id "cpu-nn"
   :name "CPU Neural Backend"
   :version "1.0.0"
   :description "Pure Common Lisp dense tensor train/infer (always available)."
   :capabilities '(:nn-backend :train :generate)
   :priority 10
   :path path
   :backend be
   :hooks (metis.symbols:define-symbol-hooks
            :activate (lambda (rec)
                        (declare (ignore rec))
                        (metis.symbols:set-nn-backend! be)
                        t)
            :deactivate (lambda (rec)
                          (declare (ignore rec))
                          t)
            :backend (lambda (rec)
                       (declare (ignore rec))
                       be)
            :status (lambda (rec)
                      (declare (ignore rec))
                      (metis.symbols:nn-backend-status be)))
   :meta (list :kind :builtin :provider :metis)))
