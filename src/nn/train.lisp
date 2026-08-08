;;;; train.lisp — vocab, multi-layer LM, continuous train, checkpoints
(in-package :metis.nn)

(defstruct (char-vocab (:conc-name cv-))
  char->id
  id->char
  size)

(defun build-char-vocab (text)
  (let* ((chars (sort (remove-duplicates (coerce text 'list)) #'char<))
         (c2i (make-hash-table :test #'eql))
         (i2c (make-array (length chars))))
    (loop for c in chars for i from 0
          do (setf (gethash c c2i) i
                   (aref i2c i) c))
    (make-char-vocab :char->id c2i :id->char i2c :size (length chars))))

(defun vocab-size (v) (cv-size v))

(defun vocab-encode (vocab text)
  (map 'vector
       (lambda (c)
         (or (gethash c (cv-char->id vocab)) 0))
       text))

(defun vocab-decode (vocab ids)
  (map 'string
       (lambda (i)
         (aref (cv-id->char vocab)
               (max 0 (min i (1- (cv-size vocab))))))
       ids))

(defun corpus-from-string (text)
  text)

(defun corpus-from-file (path)
  (uiop:read-file-string path))

(defstruct (language-model (:conc-name lm-))
  vocab
  emb
  hidden-layers                 ; list of LINEAR modules, length = depth
  out                           ; linear hidden → vocab
  (hidden 256)
  (seq-len 64)                  ; context window length (used end-to-end)
  (depth 1)                     ; number of hidden layers (≥1)
  (emb-dim 64))

(defun language-model (vocab &key (hidden 256) (seq-len 64) (emb-dim nil)
                              (depth 2))
  "Character language model with multi-layer depth and causal context window.

   DEPTH hidden layers (default 2). SEQ-LEN is the live context window used
   in train batches and generation. Forward path:
     embed → causal-context-mean(window=seq-len) → depth×(Linear+ReLU) → logits."
  (let* ((v (vocab-size vocab))
         (e (or emb-dim (min 64 (max 8 v))))
         (h hidden)
         (d (max 1 (truncate depth)))
         (layers (loop for i from 0 below d
                       collect (linear (if (zerop i) e h) h))))
    (make-language-model
     :vocab vocab
     :emb (embedding v e)
     :hidden-layers layers
     :out (linear h v)
     :hidden h
     :seq-len seq-len
     :depth d
     :emb-dim e)))

(defmethod module-parameters ((m language-model))
  (append (module-parameters (lm-emb m))
          (mapcan #'module-parameters (lm-hidden-layers m))
          (module-parameters (lm-out m))))

(defmethod module-mode ((m language-model) mode)
  (module-mode (lm-emb m) mode)
  (dolist (layer (lm-hidden-layers m))
    (module-mode layer mode))
  (module-mode (lm-out m) mode)
  m)

(defun lm-forward-logits (m indices)
  "indices: vector of token ids length T → logits (T, vocab).

   Uses causal context pooling over the model's seq-len window, then the
   multi-layer hidden stack. Context window and depth both participate."
  (let* ((x (module-forward (lm-emb m) indices)) ; (T, e)
         (ctx (t-causal-context-mean x :window (lm-seq-len m)))
         (h ctx))
    (dolist (layer (lm-hidden-layers m))
      (setf h (t-relu (module-forward layer h))))
    (module-forward (lm-out m) h)))

(defun lm-loss (m input-ids target-ids)
  "Teacher-forced next-token NLL."
  (let ((logits (lm-forward-logits m input-ids)))
    (t-cross-entropy logits target-ids)))

(defun make-lm-batches (encoded &key (seq-len 64) (batch-size 32))
  "Return list of (input-ids . target-ids) as vectors of length ≤ SEQ-LEN.
   Each batch is a contiguous context window from the corpus."
  (declare (ignore batch-size))
  (let* ((n (length encoded))
         (batches nil))
    (when (< n 2) (return-from make-lm-batches nil))
    (let ((i 0)
          (stride (max 1 (floor seq-len 2))))
      (loop while (< i (- n 1))
            do (let* ((win (min seq-len (- n 1 i)))
                      (inputs (make-array win :element-type 'fixnum))
                      (targets (make-array win :element-type 'fixnum)))
                 (dotimes (j win)
                   (setf (aref inputs j) (aref encoded (+ i j))
                         (aref targets j) (aref encoded (+ i j 1))))
                 (push (cons inputs targets) batches)
                 (incf i stride))))
    (nreverse batches)))

(defparameter *nn-train-verbose* nil
  "When T, print per-epoch train progress to *error-output*. Default quiet for chat.")

(defun train-lm! (model text &key (epochs 5) (lr 1d-3) (seq-len nil)
                               (log-every 20) (max-batches nil)
                               (verbose *nn-train-verbose*))
  "Train character language model on TEXT. Pure CL. Returns history of metrics.
   Uses the model's multi-layer stack and context window (seq-len).
   Records active NN backend id and op counts (matmul/relu) so GPU-backed
   train loops are observable when gpu-nn is enabled.
   VERBOSE defaults to *nn-train-verbose* (nil) so chat stays readable."
  (let* ((seq-len (or seq-len (lm-seq-len model)))
         (encoded (vocab-encode (lm-vocab model) text))
         (batches (make-lm-batches encoded :seq-len seq-len))
         (opt (adam (module-parameters model) :lr lr))
         (history nil)
         (step 0)
         (backend-id
          (when (and (find-package :metis.symbols)
                     (fboundp (find-symbol "ACTIVE-NN-BACKEND" :metis.symbols))
                     (fboundp (find-symbol "NN-BACKEND-ID" :metis.symbols)))
            (funcall (symbol-function (find-symbol "NN-BACKEND-ID" :metis.symbols))
                     (funcall (symbol-function
                               (find-symbol "ACTIVE-NN-BACKEND" :metis.symbols))))))
         (ops-before
          (when (and (find-package :metis.symbols)
                     (fboundp (find-symbol "NN-BACKEND-OP-COUNTS" :metis.symbols)))
            (copy-tree
             (funcall (symbol-function
                       (find-symbol "NN-BACKEND-OP-COUNTS" :metis.symbols)))))))
    (when max-batches
      (setf batches (subseq batches 0 (min max-batches (length batches)))))
    (module-mode model :train)
    (dotimes (epoch epochs)
      (let ((epoch-loss 0d0) (nb 0))
        (dolist (batch batches)
          (destructuring-bind (inputs . targets) batch
            (optimizer-zero-grad opt)
            (let* ((loss (lm-loss model inputs targets))
                   (lv (aref (tensor-data loss) 0)))
              (backward loss)
              (optimizer-step opt)
              (incf epoch-loss lv)
              (incf nb)
              (incf step)
              (when (and verbose log-every (zerop (mod step log-every)))
                (format *error-output* "~&[nn] lm step=~A loss=~,4F backend=~A~%"
                        step lv backend-id)))))
        (let ((avg (if (plusp nb) (/ epoch-loss nb) 0d0)))
          (push (list :epoch (1+ epoch)
                      :loss avg
                      :batches nb
                      :depth (lm-depth model)
                      :seq-len seq-len
                      :hidden (lm-hidden model)
                      :backend backend-id)
                history)
          (when verbose
            (format *error-output*
                    "~&[nn] lm epoch ~A avg-loss=~,4F batches=~A depth=~A seq-len=~A backend=~A~%"
                    (1+ epoch) avg nb (lm-depth model) seq-len backend-id)))))
    (let* ((ops-after
            (when (and (find-package :metis.symbols)
                       (fboundp (find-symbol "NN-BACKEND-OP-COUNTS" :metis.symbols)))
              (funcall (symbol-function
                        (find-symbol "NN-BACKEND-OP-COUNTS" :metis.symbols)))))
           (hist (nreverse history)))
      ;; attach backend evidence on first history entry for callers
      (when hist
        (setf (first hist)
              (append (first hist)
                      (list :backend backend-id
                            :ops-before ops-before
                            :ops-after ops-after))))
      hist)))

(defun lm-generate (model &key (prompt "") (length 200) (temperature 1d0))
  "Sample from LM starting from PROMPT, using the model's context window."
  (module-mode model :eval)
  (let* ((vocab (lm-vocab model))
         (ids (coerce (vocab-encode vocab prompt) 'list))
         (temp (coerce temperature 'double-float))
         (window (lm-seq-len model)))
    (when (null ids)
      (push 0 ids))
    (dotimes (k length)
      (let* ((ctx (coerce (last ids window) 'vector))
             (logits (lm-forward-logits model ctx))
             (ls (tensor-shape logits))
             (n (second ls))
             (last-row (* (1- (first ls)) n))
             (ld (tensor-data logits))
             (maxv most-negative-double-float)
             (probs (make-array n :element-type 'double-float)))
        (dotimes (j n)
          (setf maxv (max maxv (/ (aref ld (+ last-row j)) temp))))
        (let ((sum 0d0))
          (dotimes (j n)
            (let ((e (exp (- (/ (aref ld (+ last-row j)) temp) maxv))))
              (setf (aref probs j) e)
              (incf sum e)))
          (dotimes (j n) (setf (aref probs j) (/ (aref probs j) sum))))
        (let ((r (random 1d0)) (acc 0d0) (pick 0))
          (dotimes (j n)
            (incf acc (aref probs j))
            (when (<= r acc) (setf pick j) (return)))
          (setf ids (append ids (list pick))))))
    (vocab-decode vocab (coerce ids 'vector))))

(defun train! (model xs ys &key (epochs 20) (lr 1d-2) (loss-fn #'t-mse) (opt nil))
  "Generic supervised train: xs/ys lists of tensors or numbers for MLP."
  (let* ((params (module-parameters model))
         (opt (or opt (adam params :lr lr)))
         (history nil))
    (module-mode model :train)
    (dotimes (epoch epochs)
      (let ((total 0d0) (n 0))
        (mapc (lambda (x y)
                (optimizer-zero-grad opt)
                (let* ((xt (if (tensor-p x) x (tensor-from-list (if (listp x) x (list x)))))
                       (yt (if (tensor-p y) y (tensor-from-list (if (listp y) y (list y)))))
                       (pred (module-forward model xt))
                       (loss (funcall loss-fn pred yt)))
                  (backward loss)
                  (optimizer-step opt)
                  (incf total (aref (tensor-data loss) 0))
                  (incf n)))
              xs ys)
        (push (list :epoch (1+ epoch) :loss (if (plusp n) (/ total n) 0d0)) history)))
    (nreverse history)))

(defun save-checkpoint (model path &key (meta nil))
  "Serialize model weights + meta to PATH (Lisp readable)."
  (let* ((params (module-parameters model))
         (payload
          (list :metis-nn-checkpoint 1
                :saved (multiple-value-bind (s m h d mo y)
                           (decode-universal-time (get-universal-time) 0)
                         (format nil "~4,'0D-~2,'0D-~2,'0DT~2,'0D:~2,'0D:~2,'0DZ"
                                 y mo d h m s))
                :meta meta
                :arch (list :depth (lm-depth model)
                            :hidden (lm-hidden model)
                            :seq-len (lm-seq-len model)
                            :emb-dim (lm-emb-dim model)
                            :vocab-size (vocab-size (lm-vocab model)))
                :weights
                (mapcar (lambda (p)
                          (list :name (tns-name p)
                                :shape (tensor-shape p)
                                :data (coerce (tensor-data p) 'list)))
                        params))))
    (ensure-directories-exist path)
    (with-open-file (out path :direction :output :if-exists :supersede)
      (with-standard-io-syntax
        (let ((*print-readably* t)
              (*package* (find-package :metis.nn)))
          (prin1 payload out)
          (terpri out))))
    path))

(defun load-checkpoint (model path)
  "Load weights into existing MODEL architecture."
  (with-open-file (in path)
    (let* ((*package* (find-package :metis.nn))
           (payload (read in))
           (weights (getf payload :weights))
           (params (module-parameters model)))
      (assert (eq (first payload) :metis-nn-checkpoint))
      (mapc (lambda (p w)
              (let ((data (getf w :data)))
                (replace (tensor-data p)
                         (map 'vector (lambda (x) (coerce x 'double-float)) data))
                (zero-grad p)))
            params weights)
      (getf payload :meta))))

(defun nn-registry-register (name model &key (meta nil))
  (setf (gethash name *nn-registry*)
        (list :model model :meta meta :name name))
  name)

(defun nn-registry-get (name)
  (gethash name *nn-registry*))

(defun nn-registry-list ()
  (hash-table-keys *nn-registry*))
