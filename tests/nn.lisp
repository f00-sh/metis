;;;; nn.lisp — pure-CL neural training / inference tests
(in-package :metis/tests)

(def-suite :metis-nn
  :description "Pure Common Lisp autograd, training, LM, Metis bridge")
(in-suite :metis-nn)

(test nn-autograd-matmul-bias
  "Linear path: y = xW^T+b has non-zero grads after backward."
  (let* ((x (metis.nn:tensor-from-list '((1d0 2d0) (3d0 4d0)) :requires-grad t))
         (w (metis.nn:tensor-from-list '((0.5d0 0.0d0) (0.0d0 0.5d0))
                                       :requires-grad t))
         (y (metis.nn:t-matmul x (metis.nn:t-transpose w)))
         (loss (metis.nn:t-sum y)))
    (metis.nn:backward loss)
    (is (every #'plusp (coerce (metis.nn:tensor-grad x) 'list)))
    (is (plusp (reduce #'+ (metis.nn:tensor-grad w))))))

(test nn-xor-learns
  "MLP learns XOR — proves optimizer + autograd on nonlinear task."
  (let* ((r (metis:nn-train-mlp-xor :epochs 500 :name "xor-test"))
         (preds (getf r :predictions)))
    (is (= 4 (length preds)))
    ;; thresholds: near 0,1,1,0
    (is (< (first preds) 0.35d0))
    (is (> (second preds) 0.65d0))
    (is (> (third preds) 0.65d0))
    (is (< (fourth preds) 0.35d0))))

(test nn-lm-train-and-generate
  "Char LM trains on corpus and generates text (pure CL, no Python)."
  (let* ((corpus
          (format nil "~{~A~%~}"
                  (loop repeat 40
                        collect "the quick brown fox jumps over the lazy dog")))
         (r (metis:nn-train-language-model
             corpus
             :name "fox-lm"
             :epochs 2
             :hidden 64
             :seq-len 16
             :max-batches 40
             :lr 5d-3))
         (gen (metis:nn-generate "fox-lm" :prompt "the " :length 40)))
    (is (getf r :history))
    (is (plusp (getf r :vocab-size)))
    (is (stringp gen))
    (is (>= (length gen) 5))
    (is (member "fox-lm" (metis.nn:nn-registry-list) :test #'string=))))

(test nn-checkpoint-roundtrip
  (let* ((corpus "aaaa bbbb aaaa bbbb aaaa bbbb ")
         (_ (metis:nn-train-language-model corpus :name "ckpt-lm"
                                           :epochs 1 :hidden 32
                                           :seq-len 8 :max-batches 10))
         (entry (metis.nn:nn-registry-get "ckpt-lm"))
         (model (getf entry :model))
         (path (merge-pathnames "ckpt-lm-test.ckpt"
                                (uiop:temporary-directory))))
    (declare (ignore _))
    (metis.nn:save-checkpoint model path)
    (let ((w0 (copy-seq (metis.nn:tensor-data
                         (first (metis.nn:module-parameters model))))))
      ;; mutate
      (fill (metis.nn:tensor-data (first (metis.nn:module-parameters model))) 0d0)
      (metis.nn:load-checkpoint model path)
      (is (equalp w0 (metis.nn:tensor-data
                      (first (metis.nn:module-parameters model))))))))

(test nn-tools-installed-on-boot
  (metis:boot :bootstrap t :reset t)
  (let ((tools (metis:list-tools metis:*mind*)))
    (is (find 'metis::nn-train-text tools
              :key (lambda (x) (getf x :name))))
    (is (find 'metis::nn-generate tools
              :key (lambda (x) (getf x :name))))))
