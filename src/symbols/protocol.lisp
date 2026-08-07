;;;; protocol.lisp — symbol records, hooks, NN backend protocol
(in-package :metis.symbols)

(defstruct (symbol-record (:conc-name sr-))
  id
  name
  (version "0.0.0")
  (description "")
  (capabilities nil)      ; list of keywords e.g. :nn-backend :tool :iface
  (priority 0)            ; higher wins when selecting among providers
  (path nil)              ; filesystem root of the symbol
  (enabled nil)
  (state :discovered)     ; :discovered :loaded :enabled :error
  (hooks nil)             ; plist :activate :deactivate :status ...
  (meta nil)
  (error nil)
  (backend nil))          ; optional nn backend object when enabled

(defun define-symbol-hooks (&rest keys)
  "Build a hooks plist for register-symbol!."
  keys)

(defgeneric nn-backend-id (backend)
  (:documentation "Stable backend id string."))

(defgeneric nn-backend-device (backend)
  (:documentation "Human device description.")
  (:method (backend) "unknown"))

(defgeneric nn-backend-status (backend)
  (:documentation "Plist status for introspection.")
  (:method (backend)
    (list :id (nn-backend-id backend)
          :device (nn-backend-device backend)
          :ready t)))

(defgeneric nn-backend-matmul (backend a-data b-data m k n)
  (:documentation
   "Compute C = A(m×k) · B(k×n). A-DATA/B-DATA are simple-vectors or
    arrays of double-float (row-major). Return a double-float array of m*n."))

;;; ---------- CPU backend (always available) ----------

(defstruct (cpu-nn-backend (:constructor %make-cpu-nn-backend)
                           (:conc-name cpu-be-))
  (id +cpu-nn-id+)
  (device "host-cpu"))

(defun make-cpu-nn-backend ()
  (%make-cpu-nn-backend))

(defmethod nn-backend-id ((b cpu-nn-backend))
  (cpu-be-id b))

(defmethod nn-backend-device ((b cpu-nn-backend))
  (cpu-be-device b))

(defmethod nn-backend-status ((b cpu-nn-backend))
  (list :id (cpu-be-id b)
        :device (cpu-be-device b)
        :kind :cpu
        :ready t
        :provider "metis.nn pure Common Lisp"))

(defmethod nn-backend-matmul ((b cpu-nn-backend) a-data b-data m k n)
  (declare (ignore b))
  (let ((out (make-array (* m n) :element-type 'double-float :initial-element 0d0)))
    (dotimes (i m)
      (dotimes (j n)
        (let ((s 0d0))
          (dotimes (t0 k)
            (incf s (* (aref a-data (+ (* i k) t0))
                       (aref b-data (+ (* t0 n) j)))))
          (setf (aref out (+ (* i n) j)) s))))
    out))

(defun active-nn-backend ()
  (or *active-nn-backend*
      (setf *active-nn-backend* (make-cpu-nn-backend))))

(defun set-nn-backend! (backend)
  (setf *active-nn-backend* backend)
  (nn-backend-status backend))
