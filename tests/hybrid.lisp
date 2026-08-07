;;;; hybrid.lisp — CLS v2 theory items 1–6 tests
(in-package :metis/tests)

(def-suite :metis-hybrid
  :description "Replay v2, separation, meta-cog, explain, coupling, sleep")
(in-suite :metis-hybrid)

(test hybrid-demo-refuse-allow-learn-explain
  (metis:hippocampus-clear!)
  (metis:hybrid-metrics-reset!)
  (let ((r (metis:hybrid-demo :reset t)))
    (is (eq (getf r :demo) :hybrid))
    (is (getf r :ok))
    (let* ((trace (getf r :trace))
           (phases (mapcar #'first trace))
           (explain (getf r :explain)))
      (is (member :refuse phases))
      (is (member :allow phases))
      (is (member :learn phases))
      (is (getf explain :explain))
      (is (eq (getf explain :tms-label) :in)
          "learn phase ends with path IN")
      (is (listp (getf explain :supporters)))
      (is (getf explain :weights-stepped))
      (let ((refuse-u (second (find :refuse trace :key #'first))))
        (is (eq (getf refuse-u :decision) :refuse))
        (is (eq (getf (getf refuse-u :explain) :tms-label) :out))
        (is (getf (getf refuse-u :explain) :explain))))))

(test hybrid-replay-v2-interleaved-prioritized
  "Prioritized sampling + interleaved k-old+1-new composition."
  (metis:boot :bootstrap t :reset t)
  (metis:hippocampus-clear!)
  (metis:nn-enable-path metis:*mind*)
  ;; mix routine + high priority
  (dotimes (i 5)
    (metis:hippocampus-encode! (format nil "routine turn ~A" i)
                               :source :turn :priority 1 :goal 'g1))
  (dotimes (i 5)
    (metis:hippocampus-encode! (format nil "ERROR fail ~A" i)
                               :source :error :priority 10 :goal 'g1
                               :success nil :valence :blocked))
  (let* ((batch (metis:hippocampus-interleaved-batches "new material here"
                                                       :k 3 :steps 4))
         (comp (getf batch :composition)))
    (is (eq (getf batch :mode) :interleaved-k-old-plus-1-new))
    (is (= 4 (length (getf batch :batches))))
    (is (= 4 (length comp)))
    (dolist (c comp)
      (is (= 1 (getf c :new)))
      (is (plusp (getf c :k-old)))
      (is (plusp (getf c :priority-sum))))
    ;; high priority sources should appear often in composition
    (let ((sources (mapcan (lambda (c) (copy-list (getf c :old-sources))) comp)))
      (is (find :error sources)))))

(test hybrid-forget-test-replay-helps
  "Teach A→B; A eval-loss lower with replay than without (shipped forget-test)."
  (let ((r (metis:hybrid-forget-test :name "ft")))
    (is (numberp (getf (getf r :scores) :loss-with)))
    (is (numberp (getf (getf r :scores) :loss-without)))
    (is (getf r :better-with-replay)
        "loss-with ~A should be < loss-without ~A"
        (getf (getf r :scores) :loss-with)
        (getf (getf r :scores) :loss-without))))

(test hybrid-pattern-separation-keys
  (metis:hippocampus-clear!)
  (metis:hippocampus-encode! "alpha domain material AAA"
                             :source :teach :goal 'task-a :context "ca" :priority 6)
  (metis:hippocampus-encode! "beta domain material BBB"
                             :source :teach :goal 'task-b :context "cb" :priority 6)
  (let ((a (metis:hippocampus-episodes :goal 'task-a))
        (b (metis:hippocampus-episodes :goal 'task-b)))
    (is (= 1 (length a)))
    (is (= 1 (length b)))
    (is (search "AAA" (getf (first a) :text)))
    (is (search "BBB" (getf (first b) :text)))
    (is (not (equal (getf (first a) :context)
                    (getf (first b) :context))))))

(test hybrid-meta-metrics-self-model
  (metis:boot :bootstrap t :reset t)
  (metis:hippocampus-clear!)
  (metis:hybrid-metrics-reset!)
  (metis:nn-enable-path metis:*mind*)
  (metis:cognitive-unit metis:*mind* "/learn metric teach one" :force-learn t :skip-act t)
  (metis:nn-disable-path-meta metis:*mind*)
  (metis:cognitive-unit metis:*mind* "/generate online-lm x" :learn nil)
  (let* ((m (metis:hybrid-metrics))
         (adj (metis:hybrid-metrics-adjust! metis:*mind*))
         (mode-fact (list (intern "HYBRID-MODE" :metis) (getf adj :mode)))
         (in-p (metis:tms-in-p (metis::mind-tms metis:*mind*) mode-fact)))
    (is (plusp (getf m :units)))
    (is (plusp (getf m :path-flips)))
    (is (numberp (getf m :refuse-count)))
    (is (not (null (getf adj :mode))))
    (is (not (null in-p)))
    (is (member mode-fact
                (metis:tms-in-facts (metis::mind-tms metis:*mind*))
                :test #'equal))))

(test hybrid-explain-and-out-freezes-plasticity
  (metis:boot :bootstrap t :reset t)
  (metis:hippocampus-clear!)
  (metis:nn-disable-path metis:*mind*)
  (let ((u (metis:cognitive-unit metis:*mind* "/generate online-lm hi" :learn nil)))
    (is (eq (getf u :decision) :refuse))
    (let ((ex (getf u :explain)))
      (is (getf ex :explain))
      (is (eq (getf ex :tms-label) :out))
      (is (null (getf ex :weights-stepped)))
      (is (find :out (mapcar (lambda (s) (getf s :label)) (getf ex :supporters))))))
  (let ((c (metis:neocortex-consolidate! "cannot learn" :mind metis:*mind*)))
    (is (null (getf c :learned)))
    (is (getf c :refused))))

(test hybrid-coupled-accept-reject
  (metis:boot :bootstrap t :reset t)
  (metis:hippocampus-clear!)
  (metis:nn-enable-path metis:*mind*)
  (metis:nn-train-language-model "couple couple couple "
                                 :name "online-lm" :epochs 1 :hidden 24
                                 :seq-len 16 :depth 2 :max-batches 4)
  (let ((acc (metis:hybrid-coupled-propose
              metis:*mind* '(coupled-fact accepted-1) :goal 'g-couple)))
    (is (getf acc :accepted))
    (is (member (getf acc :decision) '(:allow :learn)))
    (is (getf (getf acc :explain) :explain))
    (is (find t (mapcar (lambda (s) (getf s :accepted))
                        (getf (getf acc :explain) :supporters)))))
  (let* ((before (metis:hippocampus-size))
         (rej (metis:hybrid-coupled-propose
               metis:*mind*
               ;; invalid fact shape still can assert as list — use something
               ;; that assert-fact accepts but mark reject by using a closed path:
               ;; actually force reject by disable path mid... use accept false path:
               '(ok-fact 2))))
    ;; second accept also ok; for reject use path OUT
    (declare (ignore before rej)))
  (metis:nn-disable-path metis:*mind*)
  (let ((rej (metis:hybrid-coupled-propose metis:*mind* '(should-fail x))))
    (is (null (getf rej :accepted)))
    (is (eq (getf rej :decision) :refuse))
    (is (eq (getf (getf rej :explain) :tms-label) :out)))
  ;; reject while path IN: use a fact then check success flag on episodes
  (metis:nn-enable-path metis:*mind*)
  (let* ((n0 (metis:hippocampus-size))
         (r (metis:hybrid-coupled-propose metis:*mind* '(another-ok 3)))
         (eps (metis:hippocampus-episodes :source :coupled-accept)))
    (is (getf r :accepted))
    (is (>= (length eps) 1))
    (is (every (lambda (e) (getf e :success)) eps))
    (is (> (metis:hippocampus-size) n0))))

(test hybrid-sleep-consolidate
  (metis:boot :bootstrap t :reset t)
  (metis:hippocampus-clear!)
  (metis:nn-enable-path metis:*mind*)
  (dotimes (i 6)
    (metis:hippocampus-encode! (format nil "sleep episode ~A alpha beta" i)
                               :source :teach :priority 6))
  (let ((r (metis:sleep-consolidate! :mind metis:*mind* :max-batches 4)))
    (is (getf r :learned))
    (is (getf r :sleep))
    (is (eq (getf r :batch-mode) :interleaved-k-old-plus-1-new))
    (is (getf r :weights-stepped))))

(test hybrid-iface-turn-attaches-hybrid
  (metis:boot :bootstrap t :reset t)
  (let* ((s (metis:session-create :id "hyb-iface" :boot nil))
         (out (metis:iface-turn s "(tell (hybrid-on-the-fly))")))
    (is (getf out :hybrid))
    (is (getf (getf out :hybrid) :explain))))
