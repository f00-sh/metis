;;;; belief.lisp — weighted / probabilistic soft beliefs over facts
(in-package :metis)

(defstruct (belief-store (:conc-name bs-))
  (weights (make-hash-table :test #'equal)) ; fact -> probability 0..1
  (lock (bt:make-lock "metis-belief")))

(defun make-empty-beliefs ()
  (make-belief-store))

(defun belief-get (bs fact &optional (default 0.0))
  (gethash fact (bs-weights bs) default))

(defun belief-set (bs fact p)
  (bt:with-lock-held ((bs-lock bs))
    (setf (gethash fact (bs-weights bs))
          (max 0.0 (min 1.0 (float p 1.0d0))))))

(defun belief-boost (bs fact &optional (delta 0.1))
  (belief-set bs fact (+ (belief-get bs fact 0.5) delta)))

(defun belief-decay-all (bs &optional (factor 0.99))
  (bt:with-lock-held ((bs-lock bs))
    (maphash (lambda (k v)
               (setf (gethash k (bs-weights bs)) (* v factor)))
             (bs-weights bs))))

(defun belief-and (ps)
  "Noisy-and of probabilities."
  (reduce #'* ps :initial-value 1.0))

(defun belief-or (ps)
  (- 1.0 (reduce #'* (mapcar (lambda (p) (- 1.0 p)) ps) :initial-value 1.0)))

(defun belief-query (bs pattern kb)
  "Return (fact . p) pairs for facts matching pattern, using KB candidates."
  (let ((out nil))
    (dolist (f (kb-candidates kb pattern))
      (unless (unify-fail-p (unify pattern f))
        (push (cons f (belief-get bs f 1.0)) out)))
    (sort out #'> :key #'cdr)))

(defun belief-snapshot (bs)
  (loop for k being the hash-keys of (bs-weights bs) using (hash-value v)
        collect (list k v)))
