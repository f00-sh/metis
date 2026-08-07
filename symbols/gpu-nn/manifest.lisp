;;;; gpu-nn — CUDA driver neural compute symbol (optional plugin)
(in-package :cl-user)

(let* ((path (or (and (boundp '*symbol-load-path*)
                      (symbol-value '*symbol-load-path*))
                 (uiop:pathname-directory-pathname *load-truename*))))
  ;; Ensure CUDA substrate is loaded from the Metis symbols module
  (metis.symbols:register-symbol!
   :id "gpu-nn"
   :name "GPU Neural Backend"
   :version "1.0.0"
   :description "CUDA driver (libcuda) PTX GEMM acceleration for Metis neural path."
   :capabilities '(:nn-backend :train :generate :gpu)
   :priority 100
   :path path
   :hooks (metis.symbols:define-symbol-hooks
            :activate (lambda (rec)
                        (let ((be (metis.symbols::make-gpu-nn-backend)))
                          (setf (metis.symbols:sr-backend rec) be)
                          (metis.symbols:set-nn-backend! be)
                          t))
            :deactivate (lambda (rec)
                          (declare (ignore rec))
                          (ignore-errors (metis.symbols::cuda-shutdown!))
                          t)
            :backend (lambda (rec)
                       (or (metis.symbols:sr-backend rec)
                           (metis.symbols::make-gpu-nn-backend)))
            :status (lambda (rec)
                      (if (metis.symbols:sr-backend rec)
                          (metis.symbols:nn-backend-status
                           (metis.symbols:sr-backend rec))
                          (list :id "gpu-nn"
                                :ready nil
                                :note "not activated"))))
   :meta (list :kind :plugin
               :requires "libcuda.so"
               :provider :metis)))
