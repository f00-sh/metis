;;;; tensor.lisp — dense tensors + reverse-mode autograd
(in-package :metis.nn)

(defstruct (tensor (:constructor %make-tensor)
                   (:conc-name tns-))
  data
  shape
  (grad nil)
  (requires-grad nil)
  (grad-fn nil)
  (children nil)
  (name nil))

(defun tensor-data (x) (tns-data x))
(defun tensor-shape (x) (tns-shape x))
(defun tensor-grad (x) (tns-grad x))
(defun tensor-requires-grad (x) (tns-requires-grad x))
(defun (setf tensor-requires-grad) (v x)
  (setf (tns-requires-grad x) v)
  (when (and v (null (tns-grad x)))
    (setf (tns-grad x) (%make-storage (length (tns-data x)))))
  v)

(defun tensor-numel (shape-or-tensor)
  (let ((shape (if (tensor-p shape-or-tensor)
                   (tns-shape shape-or-tensor)
                   shape-or-tensor)))
    (if (null shape) 1 (reduce #'* shape :initial-value 1))))

(defun %make-storage (n &optional (fill 0d0))
  (make-array n :element-type 'double-float
              :initial-element (coerce fill 'double-float)))

(defun make-tensor (shape &key (requires-grad nil) (init 0d0) name data)
  (let* ((shape (copy-list shape))
         (n (tensor-numel shape))
         (data (or data (%make-storage n init))))
    (assert (= (length data) n) () "data length ~A != numel ~A" (length data) n)
    (%make-tensor :data data
                  :shape shape
                  :requires-grad requires-grad
                  :grad (when requires-grad (%make-storage n 0d0))
                  :name name)))

(defun tensor-zeros (shape &key (requires-grad nil) name)
  (make-tensor shape :requires-grad requires-grad :init 0d0 :name name))

(defun tensor-randn (shape &key (requires-grad nil) (scale 0.02d0) name)
  (let* ((n (tensor-numel shape))
         (data (%make-storage n 0d0)))
    (dotimes (i n)
      (let* ((u1 (max 1d-12 (random 1d0)))
             (u2 (random 1d0))
             (z (* (sqrt (* -2d0 (log u1))) (cos (* 2d0 pi u2)))))
        (setf (aref data i) (* scale z))))
    (make-tensor shape :requires-grad requires-grad :data data :name name)))

(defun tensor-from-list (list &key (requires-grad nil) name)
  (labels ((shape-of (x)
             (if (and (listp x) x (listp (first x)))
                 (cons (length x) (shape-of (first x)))
                 (if (listp x) (list (length x)) nil)))
           (flatten-nested (x acc)
             (cond
               ((and (listp x) x (listp (first x)))
                (dolist (e x acc) (setf acc (flatten-nested e acc)))
                acc)
               ((listp x)
                (dolist (e x acc)
                  (push (coerce e 'double-float) acc))
                acc)
               (t (cons (coerce x 'double-float) acc)))))
    (let* ((shape (shape-of list))
           (flat (nreverse (flatten-nested list nil))))
      (make-tensor shape
                   :requires-grad requires-grad
                   :data (make-array (length flat)
                                     :element-type 'double-float
                                     :initial-contents flat)
                   :name name))))

(defun tensor-copy (x &key (requires-grad nil))
  (make-tensor (tns-shape x)
               :requires-grad requires-grad
               :data (copy-seq (tns-data x))))

(defun tensor-no-grad (x)
  (let ((y (tensor-copy x :requires-grad nil)))
    (setf (tns-grad-fn y) nil (tns-children y) nil)
    y))

(defun %offset (shape indices)
  (let ((o 0) (stride 1))
    (loop for dim in (reverse shape)
          for idx in (reverse indices)
          do (incf o (* idx stride))
             (setf stride (* stride dim)))
    o))

(defun tensor-ref (x &rest indices)
  (aref (tns-data x) (%offset (tns-shape x) indices)))

(defun tensor-set (x value &rest indices)
  (setf (aref (tns-data x) (%offset (tns-shape x) indices))
        (coerce value 'double-float)))

(defun zero-grad (x)
  (when (tns-grad x)
    (fill (tns-grad x) 0d0))
  x)

(defun %ensure-grad (x)
  (unless (tns-grad x)
    (setf (tns-grad x) (%make-storage (length (tns-data x)))))
  (tns-grad x))

(defun backward (loss &optional (grad-out 1d0))
  (assert (tensor-p loss))
  (let ((visited (make-hash-table :test #'eq))
        (order nil))
    (labels ((topo (v)
               (unless (gethash v visited)
                 (setf (gethash v visited) t)
                 (dolist (c (tns-children v)) (topo c))
                 (push v order))))
      (topo loss))
    (let ((g (%ensure-grad loss)))
      (if (= (length g) 1)
          (setf (aref g 0) (coerce grad-out 'double-float))
          (fill g (coerce grad-out 'double-float))))
    (dolist (v order)
      (when (tns-grad-fn v)
        (funcall (tns-grad-fn v) v)))
    loss))

(defun %as-tensor (x)
  (cond ((tensor-p x) x)
        ((numberp x) (make-tensor '(1) :init x))
        (t (error "not a tensor: ~S" x))))

(defun %binary-needs-grad (a b)
  (and *grad-enabled*
       (or (and (tensor-p a) (tns-requires-grad a))
           (and (tensor-p b) (tns-requires-grad b)))))

(defun %unary-needs-grad (a)
  (and *grad-enabled* (tensor-p a) (tns-requires-grad a)))
