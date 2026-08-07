;;;; symbols — Metis plugin system (homage to Symbolics)
(defpackage :metis.symbols
  (:use :cl :alexandria)
  (:export
   #:*symbol-registry*
   #:*symbols-roots*
   #:*active-nn-backend*
   #:symbol-record
   #:symbol-record-p
   #:sr-id #:sr-name #:sr-version #:sr-description
   #:sr-capabilities #:sr-priority #:sr-path #:sr-enabled
   #:sr-state #:sr-hooks #:sr-meta #:sr-backend #:sr-error
   #:make-gpu-nn-backend
   #:cuda-init! #:cuda-shutdown! #:cuda-available-p
   #:define-symbol-hooks
   #:register-symbol!
   #:symbol-get
   #:symbol-list
   #:symbol-list-records
   #:symbols-roots
   #:discover-symbols!
   #:load-symbol!
   #:enable-symbol!
   #:disable-symbol!
   #:install-symbol!
   #:symbol-info
   #:symbols-boot!
   #:capability-providers
   #:active-nn-backend
   #:set-nn-backend!
   #:nn-backend-matmul
   #:nn-backend-axpy
   #:nn-backend-relu
   #:nn-backend-op-counts
   #:nn-backend-reset-op-counts!
   #:nn-backend-id
   #:nn-backend-device
   #:nn-backend-status
   #:make-cpu-nn-backend
   #:sign-symbol-package!
   #:verify-symbol-package
   #:ensure-default-trust-key!
   #:load-trust-keys!
   #:+cpu-nn-id+
   #:+gpu-nn-id+))

(in-package :metis.symbols)

(defparameter *symbol-registry* (make-hash-table :test #'equal)
  "id → symbol-record")

(defparameter *symbols-roots* nil
  "Directories searched for symbols/<id>/manifest.lisp")

(defparameter *active-nn-backend* nil
  "Currently active NN compute backend object.")

(defparameter +cpu-nn-id+ "cpu-nn")
(defparameter +gpu-nn-id+ "gpu-nn")
