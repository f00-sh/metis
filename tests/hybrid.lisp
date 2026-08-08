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
  "Teach A→B; A eval-loss lower with replay than without (shipped fair forget-test)."
  (let ((r (metis:hybrid-forget-test :name "ft")))
    (is (numberp (getf (getf r :scores) :loss-with)))
    (is (numberp (getf (getf r :scores) :loss-without)))
    (is (getf (getf r :fair-hyperparams) :identical-procedure)
        "forget-test must use identical procedure for both arms")
    (is (equal (getf (getf r :with-replay) :b-batches)
               (getf (getf r :without-replay) :b-batches)))
    (is (equal (getf (getf r :with-replay) :b-lr)
               (getf (getf r :without-replay) :b-lr)))
    (is (equal (getf (getf r :with-replay) :b-epochs)
               (getf (getf r :without-replay) :b-epochs)))
    (is (getf (getf r :with-replay) :replay))
    (is (null (getf (getf r :without-replay) :replay)))
    (is (getf r :better-with-replay)
        "loss-with ~A should be < loss-without ~A (fair hyperparams)"
        (getf (getf r :scores) :loss-with)
        (getf (getf r :scores) :loss-without))))

(test hybrid-replay-nil-forces-off
  "Explicit :replay nil must force no-replay even when *replay-enabled* is T."
  (metis:boot :bootstrap t :reset t)
  (metis:hippocampus-clear!)
  (metis:nn-enable-path metis:*mind*)
  (metis:nn-train-language-model "alpha beta gamma delta "
                                 :name "replay-nil-lm" :epochs 1 :hidden 24
                                 :seq-len 16 :depth 2 :max-batches 4)
  (let ((metis:*replay-enabled* t))
    (let ((r (metis:neocortex-consolidate!
              "pure beta corpus material long enough"
              :name "replay-nil-lm"
              :mind metis:*mind*
              :replay nil
              :max-batches 2
              :lr 1d-3)))
      (is (getf r :learned))
      (is (null (getf r :replay))
          "explicit :replay nil must not fall back to *replay-enabled*")
      (is (eq (getf r :batch-mode) :no-replay)))))

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
  ;; Accept arm: unifies with allow-template
  (let ((acc (metis:hybrid-coupled-propose
              metis:*mind* '(coupled-fact accepted-1) :goal 'g-couple
              :prompt "draft ")))
    (is (getf acc :accepted))
    (is (member (getf acc :decision) '(:allow :learn)))
    (is (getf (getf acc :explain) :explain))
    (is (eq (getf (getf acc :explain) :tms-label) :in))
    (is (find t (mapcar (lambda (s) (getf s :accepted))
                        (getf (getf acc :explain) :supporters))))
    (is (>= (length (getf (getf acc :explain) :supporters)) 2)
        "multi-justification: coupled + tms (+ unifier)"))
  ;; Path-IN symbolic reject: blocked predicate / no template match
  (let* ((n0 (metis:hippocampus-size))
         (rej (metis:hybrid-coupled-propose
               metis:*mind* '(should-fail x) :goal 'g-reject))
         (rej-eps (metis:hippocampus-episodes :source :coupled-reject)))
    (is (null (getf rej :accepted)))
    (is (eq (getf rej :decision) :coupled-reject))
    (is (eq (getf (getf rej :explain) :tms-label) :in)
        "path-IN reject must still report TMS IN")
    (is (null (getf rej :learned)))
    (is (plusp (length rej-eps)))
    (is (every (lambda (e) (null (getf e :success))) rej-eps)
        "reject episodes must not be success")
    (is (> (metis:hippocampus-size) n0)))
  ;; No-template unknown fact also rejects under path IN
  (let ((rej2 (metis:hybrid-coupled-propose
               metis:*mind* '(unknown-predicate 99))))
    (is (null (getf rej2 :accepted)))
    (is (eq (getf rej2 :decision) :coupled-reject)))
  ;; Path OUT still freezes coupled draft
  (metis:nn-disable-path metis:*mind*)
  (let ((rej (metis:hybrid-coupled-propose metis:*mind* '(coupled-fact blocked))))
    (is (null (getf rej :accepted)))
    (is (eq (getf rej :decision) :refuse))
    (is (eq (getf (getf rej :explain) :tms-label) :out)))
  ;; Accept arm after re-enable: success episodes only on accept
  (metis:nn-enable-path metis:*mind*)
  (let* ((n0 (metis:hippocampus-size))
         (r (metis:hybrid-coupled-propose metis:*mind* '(another-ok 3)))
         (eps (metis:hippocampus-episodes :source :coupled-accept)))
    (is (getf r :accepted))
    (is (>= (length eps) 1))
    (is (every (lambda (e) (getf e :success)) eps))
    (is (> (metis:hippocampus-size) n0)))
  ;; Gate pure function can fail without side effects
  (multiple-value-bind (ok kind)
      (metis:hybrid-coupled-accept-p metis:*mind* '(forbidden anything))
    (is (null ok))
    (is (eq kind :blocked-predicate)))
  (multiple-value-bind (ok2 kind2)
      (metis:hybrid-coupled-accept-p metis:*mind* '(ok-fact 7))
    (is (not (null ok2)))
    (is (eq kind2 :template))))

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

(test hybrid-soft-latent-replay
  "Episodes store summary/key; interleaved batches consume soft latents."
  (metis:hippocampus-clear!)
  (let ((ep (metis:hippocampus-encode! "alpha zeta unique-token-AAA for soft latent"
                                       :source :teach :goal 'task-a :context "ca"
                                       :priority 12)))
    (is (stringp (getf ep :summary)))
    (is (plusp (length (getf ep :summary))))
    (is (stringp (getf ep :key)))
    (is (search "task-a" (string-downcase (princ-to-string (getf ep :key)))
                :test #'char-equal)))
  (dotimes (i 4)
    (metis:hippocampus-encode! (format nil "error episode ~A fail" i)
                               :source :error :priority 10 :success nil))
  (let* ((batch (metis:hippocampus-interleaved-batches "new material here"
                                                       :k 3 :steps 3
                                                       :use-summary t))
         (comp (getf batch :composition)))
    (is (getf batch :soft-latent))
    (is (eq (getf batch :mode) :interleaved-k-old-plus-1-new))
    (dolist (c comp)
      (is (getf c :used-summary))
      (is (consp (getf c :old-summaries)))
      (is (consp (getf c :old-keys)))
      (is (some (lambda (s) (and s (plusp (length s)))) (getf c :old-summaries))))
    (let ((blob (first (getf batch :batches))))
      (is (or (search "[" blob) (search "alpha" blob :test #'char-equal))))))

(test hybrid-separation-probe-metrics
  "A→B then goal-A cue: NLL and A-token retention are both numeric."
  (let ((r (metis:hybrid-separation-probe :name "sep-probe" :seq-len 48
                                          :b-batches 8 :b-lr 5d-3)))
    (is (numberp (getf r :loss-a)))
    (is (numberp (getf r :loss-b)))
    (is (numberp (getf r :a-token-score)))
    (is (getf r :metrics-numeric))
    (is (numberp (getf (getf r :a-token-retention) :hits)))
    (is (plusp (getf (getf r :separation-keys) :a-count)))
    (is (not (equal (getf (getf r :separation-keys) :a-context)
                    (getf (getf r :separation-keys) :b-context))))
    (is (stringp (getf (getf r :separation-keys) :a-summary)))))

(test hybrid-domain-pack-couple-templates
  "Domain pack registers couple templates; accept/reject use them."
  (metis:boot :bootstrap t :reset t)
  (metis:hippocampus-clear!)
  (metis:nn-enable-path metis:*mind*)
  (let* ((pack (merge-pathnames "symbols/domain-pack/pack.lisp"
                                (asdf:system-source-directory :metis)))
         (loaded (metis:domain-pack-load metis:*mind* pack)))
    (is (getf loaded :loaded))
    (is (plusp (getf loaded :couple-templates)))
    (is (getf loaded :template-registration)))
  (let ((acc (metis:hybrid-coupled-propose
              metis:*mind* '(species dolphin mammal) :goal 'g-domain)))
    (is (getf acc :accepted))
    (is (member (getf acc :decision) '(:allow :learn))))
  (let ((acc2 (metis:hybrid-coupled-propose
               metis:*mind* '(frontier-allowed ok-item))))
    (is (getf acc2 :accepted)))
  (let ((rej (metis:hybrid-coupled-propose
              metis:*mind* '(not-in-pack 123))))
    (is (null (getf rej :accepted)))
    (is (eq (getf rej :decision) :coupled-reject))))

(test hybrid-long-context-reports-metrics
  "Longer context train reports separation and replay metrics."
  (metis:boot :bootstrap t :reset t)
  (metis:hippocampus-clear!)
  (metis:nn-enable-path metis:*mind*)
  (let* ((text (format nil "~{~A ~}"
                       (loop repeat 40 collect "long context alpha beta gamma")))
         (r (metis:hybrid-long-context-train! text :name "long-ctx"
                                              :seq-len 128 :depth 3
                                              :hidden 48 :max-batches 4
                                              :mind metis:*mind*)))
    (is (getf r :trained))
    (is (= 128 (getf r :seq-len)))
    (is (getf r :metrics-reported))
    (is (plusp (getf (getf r :separation) :episodes)))
    (is (eq (getf (getf r :replay) :mode) :interleaved-k-old-plus-1-new))
    (is (getf (getf r :consolidation) :learned))))



(test hybrid-durable-roundtrip
  "Hippocampus + self-model survive durable-save/load."
  (metis:boot :bootstrap t :reset t)
  (metis:hippocampus-clear!)
  (metis:hybrid-metrics-reset!)
  (metis:nn-enable-path metis:*mind*)
  (metis:hippocampus-encode! "durable episode alpha AAA"
                             :source :teach :goal 'dur-a :context "cd" :priority 9)
  (metis:cognitive-unit metis:*mind* "/learn durable self model"
                        :force-learn t :skip-act t)
  (metis:hybrid-metrics-adjust! metis:*mind*)
  (let* ((key "hybrid-test-rt")
         (n0 (metis:hippocampus-size))
         (eps0 (copy-tree (metis:hippocampus-episodes :goal 'dur-a)))
         (met0 (copy-list (metis:hybrid-metrics))))
    (is (plusp n0))
    (metis:durable-save-hybrid! :mind metis:*mind* :key key)
    (metis:hippocampus-clear!)
    (metis:hybrid-metrics-reset!)
    (is (zerop (metis:hippocampus-size)))
    (is (metis:durable-load-hybrid! :mind metis:*mind* :key key))
    (is (= n0 (metis:hippocampus-size)))
    (is (equal (getf (first eps0) :text)
               (getf (first (metis:hippocampus-episodes :goal 'dur-a)) :text)))
    (is (plusp (getf (metis:hybrid-metrics) :units)))))

(test hybrid-offline-schedule-mode
  (metis:boot :bootstrap t :reset t)
  (metis:hippocampus-clear!)
  (metis:nn-enable-path metis:*mind*)
  (let ((r (metis:hybrid-offline-schedule! metis:*mind*
                                           :mode :sleep-epoch :steps 2
                                           :max-batches 2)))
    (is (eq (getf r :mode) :sleep-epoch))
    (is (eq (getf (getf r :identity) :schedule) :offline-sleep))
    (is (= 2 (getf r :steps)))
    (is (= 2 (length (getf r :trace))))))

(test hybrid-plan-multi-supporter-explain
  (metis:boot :bootstrap t :reset t)
  (metis:nn-enable-path metis:*mind*)
  (let ((r (metis:hybrid-plan-explain metis:*mind* '(clear a))))
    (is (getf r :explain))
    (is (listp (getf (getf r :explain) :supporters)))
    (is (plusp (length (getf (getf r :explain) :supporters))))
    ;; TMS supporter always present when path enabled
    (is (find :tms (mapcar (lambda (s) (getf s :informant))
                           (getf (getf r :explain) :supporters))))
    ;; Failed HTN must not count as htn-ok / allow via HTN alone
    (when (and (getf r :htn) (null (getf r :htn-ok)))
      (is (null (getf r :htn-ok)))
      (is (not (and (eq (getf (getf r :explain) :decision) :allow)
                    (null (getf r :strips-ok))
                    (null (getf r :htn-ok))))))))

(test hybrid-separation-threshold
  "Fixed cue; :pass iff score >= threshold; high threshold fails."
  (let* ((r0 (metis:hybrid-separation-probe :name "thr-sep-lo" :b-batches 6
                                            :cue "alpha "
                                            :threshold 0d0))
         (score (getf r0 :a-token-score))
         (r-hi (metis:hybrid-separation-probe :name "thr-sep-hi" :b-batches 4
                                              :cue "alpha "
                                              :threshold 1.0d9))
         (r-def (metis:hybrid-separation-probe :name "thr-sep-def" :b-batches 4
                                               :cue "alpha ")))
    (is (numberp score))
    (is (numberp (getf r0 :loss-a)))
    (is (equal "alpha " (getf r0 :cue)))
    (is (eq (getf r0 :pass) (>= score (getf r0 :threshold)))
        "pass must equal score>=threshold (low thr) score=~A thr=~A pass=~A"
        score (getf r0 :threshold) (getf r0 :pass))
    (is (null (getf r-hi :pass))
        "absurd threshold 1e9 must fail (score=~A)"
        (getf r-hi :a-token-score))
    (is (= (getf r-def :threshold) metis:*separation-retention-threshold*)
        "omitted threshold uses *separation-retention-threshold*")
    (is (eq (getf r-def :pass)
            (>= (getf r-def :a-token-score) (getf r-def :threshold))))))

(test hybrid-curriculum-ladder
  (metis:boot :bootstrap t :reset t)
  (let ((r (metis:curriculum-ladder-run :name "lad" :mind metis:*mind*)))
    (is (getf r :retention))
    (is (numberp (getf (getf r :retention) :loss-a)))
    (is (= (getf (getf r :retention) :threshold)
           metis:*separation-retention-threshold*)
        "ladder defers threshold to separation probe default")
    (is (eq (getf r :retention-pass) (getf (getf r :retention) :pass)))
    (is (member :refuse (getf r :phases)))
    (is (member :allow (getf r :phases)))
    (is (member :learn (getf r :phases)))))

(test hybrid-trust-policy
  (metis:boot :bootstrap t :reset t)
  (let ((soc (metis:society-default-ensemble)))
    (is (metis:trust-policy-allows-p metis:*mind* :teach :actor nil))
    (is (null (metis:trust-policy-allows-p metis:*mind* :teach
                                           :actor "stranger" :society soc)))
    (metis:society-trust! soc "stranger" (metis::mind-name metis:*mind*))
    ;; after trust stranger -> mind name, may still fail if mind name is conductor
    (let ((den (metis:nn-enable-path-policy metis:*mind*
                                            :actor "unknown-actor" :society soc)))
      (is (getf den :refused)))
    (metis:society-trust! soc "planner" "conductor")
    (let ((ok (metis:nn-enable-path-policy metis:*mind*
                                           :actor "planner" :society soc)))
      (is (or (getf ok :enabled) (null (getf ok :refused)))))))
