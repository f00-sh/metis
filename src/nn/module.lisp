;;;; module.lisp — layers, optimizers
(in-package :metis.nn)

(defun parameter (shape &key (scale 0.02d0) name)
  (tensor-randn shape :requires-grad t :scale scale :name name))

(defgeneric module-forward (module &rest inputs))
(defgeneric module-parameters (module))
(defgeneric module-mode (module mode))

(defstruct (linear (:conc-name lin-))
  in-features
  out-features
  weight
  bias
  (training t))

(defun linear (in-features out-features &key (bias t))
  (let* ((scale (sqrt (/ 2d0 in-features)))
         (w (tensor-randn (list out-features in-features)
                          :requires-grad t :scale scale :name 'weight))
         (b (when bias
              (tensor-zeros (list out-features) :requires-grad t :name 'bias))))
    (make-linear :in-features in-features
                 :out-features out-features
                 :weight w
                 :bias b)))

(defmethod module-parameters ((m linear))
  (if (lin-bias m)
      (list (lin-weight m) (lin-bias m))
      (list (lin-weight m))))

(defmethod module-mode ((m linear) mode)
  (setf (lin-training m) (eq mode :train))
  m)

(defmethod module-forward ((m linear) &rest inputs)
  (let* ((x (first inputs))
         (xs (tensor-shape x))
         (x2 (if (= (length xs) 1)
                 (make-tensor (list 1 (first xs))
                              :data (copy-seq (tensor-data x))
                              :requires-grad (tensor-requires-grad x))
                 x))
         (y (t-matmul x2 (t-transpose (lin-weight m))))
         (b (lin-bias m)))
    (if (null b)
        y
        (let* ((ys (tensor-shape y))
               (batch (first ys))
               (out (second ys))
               (data (%make-storage (* batch out)))
               (yd (tensor-data y))
               (bd (tensor-data b))
               (rg (or (tensor-requires-grad y) (tensor-requires-grad b))))
          (dotimes (i batch)
            (dotimes (j out)
              (setf (aref data (+ (* i out) j))
                    (+ (aref yd (+ (* i out) j)) (aref bd j)))))
          (let ((out-t (make-tensor ys :requires-grad rg :data data)))
            (when rg
              (setf (tns-children out-t) (list y b))
              (setf (tns-grad-fn out-t)
                    (lambda (self)
                      (let ((g (tns-grad self)))
                        (when (tensor-requires-grad y)
                          (let ((yg (%ensure-grad y)))
                            (dotimes (i (length g))
                              (incf (aref yg i) (aref g i)))))
                        (when (tensor-requires-grad b)
                          (let ((bg (%ensure-grad b)))
                            (dotimes (i batch)
                              (dotimes (j out)
                                (incf (aref bg j)
                                      (aref g (+ (* i out) j)))))))))))
            out-t)))))

(defstruct (embedding-mod (:conc-name emb-))
  num-embeddings
  embedding-dim
  weight)

(defun embedding (num-embeddings embedding-dim &key (scale 0.02d0))
  (make-embedding-mod
   :num-embeddings num-embeddings
   :embedding-dim embedding-dim
   :weight (tensor-randn (list num-embeddings embedding-dim)
                         :requires-grad t :scale scale :name 'emb-weight)))

(defmethod module-parameters ((m embedding-mod))
  (list (emb-weight m)))

(defmethod module-mode ((m embedding-mod) mode)
  (declare (ignore mode))
  m)

(defmethod module-forward ((m embedding-mod) &rest inputs)
  (t-embedding-lookup (emb-weight m) (first inputs)))

(defstruct (mlp (:conc-name mlp-))
  net)

(defun mlp (sizes)
  "sizes = (in h1 h2 ... out) — fully connected stack with ReLU between."
  (let ((layers nil))
    (loop for i from 0 below (1- (length sizes))
          for a = (nth i sizes)
          for b = (nth (1+ i) sizes)
          do (push (linear a b) layers)
             (unless (= i (- (length sizes) 2))
               (push :relu layers)))
    (make-mlp :net (nreverse layers))))

(defmethod module-parameters ((m mlp))
  (loop for l in (mlp-net m)
        when (linear-p l) append (module-parameters l)))

(defmethod module-mode ((m mlp) mode)
  (dolist (l (mlp-net m))
    (when (linear-p l) (module-mode l mode)))
  m)

(defmethod module-forward ((m mlp) &rest inputs)
  (let ((x (first inputs)))
    (dolist (l (mlp-net m) x)
      (setf x (if (eq l :relu) (t-relu x) (module-forward l x))))))

(defstruct (sgd-opt (:conc-name sgd-))
  params lr momentum velocity)

(defun sgd (params &key (lr 0.01d0) (momentum 0d0))
  (let ((ps (if (listp params) params (module-parameters params))))
    (make-sgd-opt :params ps :lr lr :momentum momentum
                  :velocity (mapcar (lambda (p)
                                      (%make-storage (length (tns-data p))))
                                    ps))))

(defstruct (adam-opt (:conc-name adam-))
  params lr beta1 beta2 eps m v (t-step 0))

(defun adam (params &key (lr 1d-3) (beta1 0.9d0) (beta2 0.999d0) (eps 1d-8))
  (let ((ps (if (listp params) params (module-parameters params))))
    (make-adam-opt
     :params ps :lr lr :beta1 beta1 :beta2 beta2 :eps eps
     :m (mapcar (lambda (p) (%make-storage (length (tns-data p)))) ps)
     :v (mapcar (lambda (p) (%make-storage (length (tns-data p)))) ps))))

(defun optimizer-zero-grad (opt)
  (dolist (p (if (sgd-opt-p opt) (sgd-params opt) (adam-params opt)))
    (zero-grad p)))

(defun optimizer-step (opt)
  (cond
    ((sgd-opt-p opt)
     (mapc (lambda (p v)
             (let ((g (tns-grad p))
                   (d (tns-data p))
                   (lr (sgd-lr opt))
                   (mu (sgd-momentum opt)))
               (when g
                 (dotimes (i (length d))
                   (setf (aref v i) (+ (* mu (aref v i)) (aref g i)))
                   (decf (aref d i) (* lr (aref v i)))))))
           (sgd-params opt) (sgd-velocity opt)))
    ((adam-opt-p opt)
     (incf (adam-t-step opt))
     (let ((tstep (adam-t-step opt))
           (lr (adam-lr opt))
           (b1 (adam-beta1 opt))
           (b2 (adam-beta2 opt))
           (eps (adam-eps opt)))
       (mapc (lambda (p m v)
               (let ((g (tns-grad p)) (d (tns-data p)))
                 (when g
                   (dotimes (i (length d))
                     (setf (aref m i) (+ (* b1 (aref m i))
                                         (* (- 1 b1) (aref g i))))
                     (setf (aref v i) (+ (* b2 (aref v i))
                                         (* (- 1 b2) (expt (aref g i) 2))))
                     (let* ((mhat (/ (aref m i) (- 1d0 (expt b1 tstep))))
                            (vhat (/ (aref v i) (- 1d0 (expt b2 tstep)))))
                       (decf (aref d i)
                             (/ (* lr mhat) (+ (sqrt vhat) eps))))))))
             (adam-params opt) (adam-m opt) (adam-v opt)))))
  opt)
