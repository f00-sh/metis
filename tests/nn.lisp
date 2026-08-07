;;;; nn.lisp — pure-CL neural training / continuous train / TMS gate tests
(in-package :metis/tests)

(def-suite :metis-nn
  :description "Pure Common Lisp autograd, multi-layer LM, continuous train, TMS gate")
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
             :depth 2
             :max-batches 40
             :lr 5d-3))
         (gen (metis:nn-generate "fox-lm" :prompt "the " :length 40)))
    (is (getf r :history))
    (is (plusp (getf r :vocab-size)))
    (is (= 2 (getf r :depth)))
    (is (stringp gen))
    (is (>= (length gen) 5))
    (is (member "fox-lm" (metis.nn:nn-registry-list) :test #'string=))))

(test nn-deeper-wider-lm
  "Multi-layer depth + context window larger than legacy single-hidden smoke path.
   Drives shipped nn-train-language-model / nn-generate entry points."
  (let* ((corpus
          (format nil "~{~A ~}"
                  (loop repeat 80
                        collect "alpha beta gamma delta epsilon zeta eta theta")))
         ;; pre-goal default was single hidden + seq-len often 16/32 smoke.
         ;; Require depth ≥ 2 and seq-len ≥ 48 (above legacy minimal smoke).
         (depth 3)
         (seq-len 48)
         (r (metis:nn-train-language-model
             corpus
             :name "deep-lm"
             :epochs 1
             :hidden 48
             :seq-len seq-len
             :depth depth
             :max-batches 12
             :lr 3d-3))
         (entry (metis.nn:nn-registry-get "deep-lm"))
         (model (getf entry :model))
         (gen (metis:nn-generate "deep-lm" :prompt "alpha " :length 24)))
    (is (getf r :history))
    (is (= depth (getf r :depth)))
    (is (= seq-len (getf r :seq-len)))
    (is (= depth (metis.nn:lm-depth model)))
    (is (= seq-len (metis.nn:lm-seq-len model)))
    (is (= depth (length (metis.nn:lm-hidden-layers model))))
    (is (stringp gen))
    (is (>= (length gen) 5))
    ;; history records architecture actually used
    (is (= depth (getf (first (getf r :history)) :depth)))
    (is (= seq-len (getf (first (getf r :history)) :seq-len)))))

(test nn-checkpoint-roundtrip
  (let* ((corpus "aaaa bbbb aaaa bbbb aaaa bbbb ")
         (_ (metis:nn-train-language-model corpus :name "ckpt-lm"
                                           :epochs 1 :hidden 32
                                           :seq-len 8 :depth 2
                                           :max-batches 10))
         (entry (metis.nn:nn-registry-get "ckpt-lm"))
         (model (getf entry :model))
         (path (merge-pathnames "ckpt-lm-test.ckpt"
                                (uiop:temporary-directory))))
    (declare (ignore _))
    (metis.nn:save-checkpoint model path)
    (let ((w0 (copy-seq (metis.nn:tensor-data
                         (first (metis.nn:module-parameters model))))))
      (fill (metis.nn:tensor-data (first (metis.nn:module-parameters model))) 0d0)
      (metis.nn:load-checkpoint model path)
      (is (equalp w0 (metis.nn:tensor-data
                      (first (metis.nn:module-parameters model))))))))

(test nn-attachment-continuous-train
  "Session attachments → corpus → continuous train twice on same model name.
   Second intake continues weights (history/steps + weight change evidence)."
  (metis:boot :bootstrap t :reset t)
  (let* ((scratch (uiop:ensure-directory-pathname
                   "/tmp/grok-goal-739c257e0109/implementer/fixtures/"))
         (_ (ensure-directories-exist scratch))
         (f1 (merge-pathnames "corpus-a.txt" scratch))
         (f2 (merge-pathnames "corpus-b.txt" scratch)))
    (declare (ignore _))
    (with-open-file (out f1 :direction :output :if-exists :supersede)
      (dotimes (i 30)
        (format out "first corpus stream of tokens for metis continuous train.~%")))
    (with-open-file (out f2 :direction :output :if-exists :supersede)
      (dotimes (i 30)
        (format out "second intake corpus continues the same registered model.~%")))
    (let* ((s (metis:session-create :id "nn-attach-ct" :boot nil))
           (a1 (metis:session-attach-file s (namestring f1)))
           (_ctx (metis:session-attach-context
                  s "extra freeform context material for the pipeline."))
           (corpus1 (metis:session-corpus s))
           (r1 (metis:nn-train-from-session
                s :name "attach-lm"
                  :epochs 1 :hidden 32 :seq-len 24 :depth 2
                  :max-batches 8 :lr 5d-3))
           (entry1 (metis.nn:nn-registry-get "attach-lm"))
           (model (getf entry1 :model))
           (w1 (copy-seq (metis.nn:tensor-data
                          (first (metis.nn:module-parameters model)))))
           (a2 (metis:session-attach-file s (namestring f2)))
           (corpus2 (metis:session-corpus s))
           (r2 (metis:nn-train-from-session
                s :name "attach-lm"
                  :epochs 1 :hidden 32 :seq-len 24 :depth 2
                  :max-batches 8 :lr 5d-3))
           (w2 (metis.nn:tensor-data
                (first (metis.nn:module-parameters model))))
           (gen (metis:nn-generate "attach-lm" :prompt "second " :length 20
                                   :mind metis:*mind*)))
      (declare (ignore a1 a2 _ctx))
      (is (plusp (length corpus1)))
      (is (> (length corpus2) (length corpus1)))
      (is (not (getf r1 :continued)))
      (is (getf r2 :continued))
      (is (= 2 (getf r2 :continuous-steps)))
      (is (equal "attach-lm" (getf r1 :name)))
      (is (equal "attach-lm" (getf r2 :name)))
      (is (member "attach-lm" (metis.nn:nn-registry-list) :test #'string=))
      ;; weights moved after second continuous step
      (is (not (equalp w1 w2)))
      (is (getf r2 :history))
      (is (stringp gen))
      (is (>= (length gen) 5)))))

(test nn-tms-gate-blocks-and-allows
  "TMS-gated neural fire: IN allows generate; OUT refuses without sampling.
   Uses shipped nn-generate / nn-enable-path / nn-disable-path."
  (metis:boot :bootstrap t :reset t)
  (let* ((corpus "gate gate gate allow block allow block ")
         (_ (metis:nn-train-language-model
             corpus :name "gate-lm"
             :epochs 1 :hidden 24 :seq-len 12 :depth 2
             :max-batches 6))
         (mind metis:*mind*))
    (declare (ignore _))
    ;; boot installs tools which enable path
    (is (metis:nn-path-allowed-p mind))
    (is (metis:tms-in-p (metis::mind-tms mind) metis:*nn-path-fact*))
    (let ((ok (metis:nn-generate "gate-lm" :prompt "gate " :length 12
                                 :mind mind)))
      (is (stringp ok))
      (is (>= (length ok) 4)))
    ;; retract policy → OUT
    (metis:nn-disable-path mind)
    (is (not (metis:nn-path-allowed-p mind)))
    (is (not (metis:tms-in-p (metis::mind-tms mind) metis:*nn-path-fact*)))
    (handler-case
        (progn
          (metis:nn-generate "gate-lm" :prompt "gate " :length 12 :mind mind)
          (fail "nn-generate must not sample when TMS gate is OUT"))
      (metis:metis-error (e)
        (is (search "blocked" (metis:metis-error-message e)
                    :test #'char-equal))))
    ;; reinstate → allow again
    (metis:nn-enable-path mind)
    (is (metis:nn-path-allowed-p mind))
    (let ((ok2 (metis:nn-generate "gate-lm" :prompt "gate " :length 8
                                  :mind mind)))
      (is (stringp ok2)))))

(test nn-tools-installed-on-boot
  (metis:boot :bootstrap t :reset t)
  (let ((tools (metis:list-tools metis:*mind*)))
    (is (find 'metis::nn-train-text tools
              :key (lambda (x) (getf x :name))))
    (is (find 'metis::nn-generate tools
              :key (lambda (x) (getf x :name))))
    (is (find 'metis::nn-train-session tools
              :key (lambda (x) (getf x :name))))
    (is (metis:nn-path-allowed-p metis:*mind*))))
