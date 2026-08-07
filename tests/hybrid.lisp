;;;; hybrid.lisp — CLS on-the-fly learning + cognitive unit tests
(in-package :metis/tests)

(def-suite :metis-hybrid
  :description "Complementary learning + refuse/allow/learn/explain unit")
(in-suite :metis-hybrid)

(test hybrid-demo-refuse-allow-learn-explain
  "Shipped hybrid-demo exercises refuse, allow, learn, explain."
  (metis:hippocampus-clear!)
  (let ((r (metis:hybrid-demo :reset t)))
    (is (eq (getf r :demo) :hybrid))
    (is (getf r :ok))
    (let* ((trace (getf r :trace))
           (phases (mapcar #'first trace))
           (explain (getf r :explain)))
      (is (member :refuse phases))
      (is (member :allow phases))
      (is (member :learn phases))
      (is (getf explain :why))
      (is (getf explain :tms))
      (is (plusp (getf explain :hippocampus)))
      (let ((refuse-u (second (find :refuse trace :key #'first))))
        (is (eq (getf refuse-u :decision) :refuse))
        (is (eq (getf (getf refuse-u :tms) :before) :out)))
      (let ((learn-u (second (find :learn trace :key #'first))))
        (is (getf (getf learn-u :learned) :learned))))))

(test hybrid-cognitive-unit-on-the-fly-train
  "Force-learn consolidates with replay; hippocampus grows."
  (metis:boot :bootstrap t :reset t)
  (metis:hippocampus-clear!)
  (metis:nn-enable-path metis:*mind*)
  (metis:hippocampus-encode! "prior episode about planning with strips"
                             :source :seed)
  (is (= 1 (metis:hippocampus-size)))
  (let ((u (metis:cognitive-unit
            metis:*mind*
            "/learn neocortex consolidates with replay from hippocampus"
            :force-learn t
            :skip-act t)))
    (is (getf (getf u :learned) :learned))
    (is (plusp (getf (getf u :learned) :replay-episodes)))
    (is (getf (getf u :tms) :recheck))
    (is (>= (metis:hippocampus-size) 2))
    (is (member "online-lm" (metis.nn:nn-registry-list) :test #'string=))))

(test hybrid-tms-gates-plasticity
  "When TMS path OUT, consolidate refuses."
  (metis:boot :bootstrap t :reset t)
  (metis:nn-disable-path metis:*mind*)
  (let ((r (metis:neocortex-consolidate! "should not train"
                                         :mind metis:*mind*)))
    (is (null (getf r :learned)))
    (is (getf r :refused))))

(test hybrid-iface-turn-attaches-hybrid
  "iface-turn returns :hybrid payload (on-the-fly unit)."
  (metis:boot :bootstrap t :reset t)
  (let* ((s (metis:session-create :id "hyb-iface" :boot nil))
         (out (metis:iface-turn s "(tell (hybrid-on-the-fly))")))
    (is (getf out :hybrid))
    (is (getf (getf out :hybrid) :episode))))
