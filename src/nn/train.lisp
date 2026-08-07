;;;; train.lisp — vocab, corpus, language model, training, checkpoints
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
  fc1
  fc2
  (hidden 256)
  (seq-len 64))

(defun language-model (vocab &key (hidden 256) (seq-len 64) (emb-dim nil))
  (let* ((v (vocab-size vocab))
         (e (or emb-dim (min 64 v)))
         (h hidden))
    (make-language-model
     :vocab vocab
     :emb (embedding v e)
     :fc1 (linear e h)
     :fc2 (linear h v)
     :hidden h
     :seq-len seq-len)))

(defmethod module-parameters ((m language-model))
  (append (module-parameters (lm-emb m))
          (module-parameters (lm-fc1 m))
          (module-parameters (lm-fc2 m))))

(defmethod module-mode ((m language-model) mode)
  (module-mode (lm-emb m) mode)
  (module-mode (lm-fc1 m) mode)
  (module-mode (lm-fc2 m) mode)
  m)

(defun lm-forward-logits (m indices)
  "indices: vector of token ids length T → logits (T, vocab) via shared emb+MLP per position."
  (let* ((x (module-forward (lm-emb m) indices)) ; (T, e)
         (h (t-relu (module-forward (lm-fc1 m) x)))
         (logits (module-forward (lm-fc2 m) h)))
    logits))

(defun lm-loss (m input-ids target-ids)
  "Teacher-forced next-token NLL."
  (let ((logits (lm-forward-logits m input-ids)))
    (t-cross-entropy logits target-ids)))

(defun make-lm-batches (encoded &key (seq-len 64) (batch-size 32))
  "Return list of (input-ids . target-ids) as vectors."
  (let* ((n (length encoded))
         (batches nil))
    (when (< n 2) (return-from make-lm-batches nil))
    (let ((i 0))
      (loop while (< i (- n 1))
            do (let ((inputs (make-array (min seq-len (- n 1 i))
                                         :element-type 'fixnum))
                     (targets (make-array (min seq-len (- n 1 i))
                                          :element-type 'fixnum)))
                 (dotimes (j (length inputs))
                   (setf (aref inputs j) (aref encoded (+ i j))
                         (aref targets j) (aref encoded (+ i j 1))))
                 (push (cons inputs targets) batches)
                 (incf i (max 1 (floor seq-len 2))))))
    (nreverse batches)))

(defun train-lm! (model text &key (epochs 5) (lr 1d-3) (seq-len nil)
                               (log-every 20) (max-batches nil))
  "Train character language model on TEXT. Pure CL. Returns alist of metrics."
  (let* ((seq-len (or seq-len (lm-seq-len model)))
         (encoded (vocab-encode (lm-vocab model) text))
         (batches (make-lm-batches encoded :seq-len seq-len))
         (opt (adam (module-parameters model) :lr lr))
         (history nil)
         (step 0))
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
              (when (and log-every (zerop (mod step log-every)))
                (format *error-output* "~&[nn] lm step=~A loss=~,4F~%" step lv)))))
        (let ((avg (if (plusp nb) (/ epoch-loss nb) 0d0)))
          (push (list :epoch (1+ epoch) :loss avg :batches nb) history)
          (format *error-output* "~&[nn] lm epoch ~A avg-loss=~,4F batches=~A~%"
                  (1+ epoch) avg nb))))
    (nreverse history)))

(defun lm-generate (model &key (prompt "") (length 200) (temperature 1d0))
  "Sample from LM starting from PROMPT."
  (module-mode model :eval)
  (let* ((vocab (lm-vocab model))
         (ids (coerce (vocab-encode vocab prompt) 'list))
         (temp (coerce temperature 'double-float)))
    (when (null ids)
      (push 0 ids))
    (dotimes (k length)
      (let* ((ctx (coerce (last ids (lm-seq-len model)) 'vector))
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
        ;; sample
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
