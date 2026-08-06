;;;; further-paths.lisp — Metis 2.0 acceptance tests (real entry points)
(in-package :metis/tests)

(def-suite :metis-further
  :description "RETE, durable LMDB, TMS formal, large KB, API security, ARC")
(in-suite :metis-further)

(test rete-forward-derives-mortal
  "Pure RETE: kb-assert only (no tell/assert-fact agenda), then RETE derives."
  (with-fixture clean-mind ()
    ;; Ensure auto-forward cannot smuggle agenda derivations.
    (metis:set-config :auto-forward nil)
    (let* ((m metis:*mind*)
           (kb (metis::mind-kb m))
           (seed (mread "(philosopher hypatia-rete-only)"))
           (human (mread "(human hypatia-rete-only)"))
           (mortal (mread "(mortal hypatia-rete-only)")))
      ;; Must NOT use tell/assert-fact (those can agenda-forward).
      (metis::kb-assert kb seed :support :asserted)
      ;; ask/prove can succeed without KB membership — use kb-holds-p.
      (is (not (metis::kb-holds-p kb mortal))
          "precondition: mortal not in KB before RETE")
      (is (not (metis::kb-holds-p kb human))
          "precondition: human not in KB before RETE")
      (let ((derived (metis:forward-chain-rete m)))
        (is-true (plusp (length derived)))
        (is (member human derived :test #'equal))
        (is (member mortal derived :test #'equal))
        (is-true (metis::kb-holds-p kb mortal))
        (is-true (metis::kb-holds-p kb human))
        ;; Heads must be tagged :rete by the shipped RETE assert path.
        (let ((hmeta (gethash human (metis::kb-facts kb)))
              (mmeta (gethash mortal (metis::kb-facts kb))))
          (is-true hmeta)
          (is-true mmeta)
          (is (eq :rete (metis::fm-support hmeta)))
          (is (eq :rete (metis::fm-support mmeta))))))))

(test rete-assert-fact-entry
  "Shipped rete-assert-fact: no agenda; returns non-empty derived list."
  (with-fixture clean-mind ()
    (metis:set-config :auto-forward nil)
    (let* ((m metis:*mind*)
           (kb (metis::mind-kb m))
           (fact (mread "(philosopher pure-rete-person)"))
           (mortal (mread "(mortal pure-rete-person)"))
           (derived (metis:rete-assert-fact m fact)))
      (is-true (plusp (length derived)))
      (is-true (metis::kb-holds-p kb mortal))
      (let ((meta (gethash mortal (metis::kb-facts kb))))
        (is-true meta)
        (is (eq :rete (metis::fm-support meta)))))))

(test rete-naf-penguin-cannot-fly
  "birds-fly has (not (penguin ?x)): pure RETE must NOT assert (can-fly opus)."
  (with-fixture clean-mind ()
    (metis:set-config :auto-forward nil)
    (let* ((m metis:*mind*)
           (kb (metis::mind-kb m))
           (can-fly-opus (mread "(can-fly opus)"))
           (fresh-bird (mread "(bird sky-lark-rete)"))
           (can-fly-fresh (mread "(can-fly sky-lark-rete)")))
      (is-true (metis::kb-holds-p kb (mread "(penguin opus)")))
      (is (not (metis::kb-holds-p kb can-fly-opus)))
      (let ((derived (metis:forward-chain-rete m)))
        (is (not (member can-fly-opus derived :test #'equal)))
        (is (not (metis::kb-holds-p kb can-fly-opus))))
      ;; Positive control: fresh non-penguin bird → RETE may derive can-fly.
      (metis::kb-assert kb fresh-bird :support :asserted)
      (let ((d2 (metis:forward-chain-rete m)))
        (is (member can-fly-fresh d2 :test #'equal))
        (is-true (metis::kb-holds-p kb can-fly-fresh))
        (is (eq :rete
                (metis::fm-support
                 (gethash can-fly-fresh (metis::kb-facts kb)))))
        ;; Still no can-fly opus
        (is (not (metis::kb-holds-p kb can-fly-opus)))))))

(test rete-naf-clear-blocked-by-on
  "clear-if-nothing-on: (not (on ?y ?x)) must block (clear a) while (on c a)."
  (with-fixture clean-mind ()
    (metis:set-config :auto-forward nil)
    (let* ((m metis:*mind*)
           (kb (metis::mind-kb m))
           (clear-a (mread "(clear a)"))
           (on-c-a (mread "(on c a)")))
      (is-true (metis::kb-holds-p kb on-c-a))
      ;; May or may not hold pre-RETE from bootstrap asserts; force retract.
      (metis::kb-retract kb clear-a)
      (metis:rete-invalidate m)
      (is (not (metis::kb-holds-p kb clear-a)))
      (let ((derived (metis:forward-chain-rete m)))
        (is (not (member clear-a derived :test #'equal)))
        (is (not (metis::kb-holds-p kb clear-a))))
      ;; After removing on-c-a, RETE may derive clear a.
      (metis::kb-retract kb on-c-a)
      (metis:rete-invalidate m)
      (let ((d2 (metis:forward-chain-rete m)))
        (is (or (member clear-a d2 :test #'equal)
                (metis::kb-holds-p kb clear-a)))))))

(test rete-lifecycle-matrix
  "Multi-property RETE matrix on shipped entry points (no agenda).
   (a) multi-hop :rete  (b) NAF  (c) join  (d) re-derive after head retract
   (e) no fire from stale alpha after premise retract."
  (with-fixture clean-mind ()
    (metis:set-config :auto-forward nil)
    (let* ((m metis:*mind*)
           (kb (metis::mind-kb m))
           (phil (mread "(philosopher again-y)"))
           (human (mread "(human again-y)"))
           (mortal (mread "(mortal again-y)"))
           (can-fly-opus (mread "(can-fly opus)"))
           (clear-a (mread "(clear a)"))
           (link-ab (mread "(link n-rete-a n-rete-b)"))
           (link-bc (mread "(link n-rete-b n-rete-c)"))
           (conn (mread "(connected n-rete-a n-rete-c)")))
      ;; --- (a) positive multi-hop ---
      (metis::kb-assert kb phil :support :asserted)
      (let ((d1 (metis:forward-chain-rete m)))
        (is (member human d1 :test #'equal))
        (is (member mortal d1 :test #'equal))
        (is (eq :rete (metis::fm-support (gethash mortal (metis::kb-facts kb))))))
      ;; --- (d) re-derive after retracting ONLY the derived head ---
      (metis:retract-fact m mortal) ; shipped retract — must invalidate rete
      (is (not (metis::kb-holds-p kb mortal)))
      (is (metis::kb-holds-p kb phil)) ; premise remains
      (let ((d2 (metis:forward-chain-rete m)))
        (is (member mortal d2 :test #'equal)
            "must re-derive mortal after head retract with premise held")
        (is-true (metis::kb-holds-p kb mortal))
        (is (eq :rete (metis::fm-support (gethash mortal (metis::kb-facts kb))))))
      ;; --- (b) NAF ---
      (metis::kb-retract kb clear-a)
      (metis:rete-invalidate m)
      (let ((d3 (metis:forward-chain-rete m)))
        (is (not (member can-fly-opus d3 :test #'equal)))
        (is (not (metis::kb-holds-p kb can-fly-opus)))
        (is (not (member clear-a d3 :test #'equal)))
        (is (not (metis::kb-holds-p kb clear-a))))
      ;; --- (c) join rule connected (install join rule on live KB) ---
      (metis:assert-rule m
                         (mread "(connected ?a ?c)")
                         (list (mread "(link ?a ?b)")
                               (mread "(link ?b ?c)"))
                         :name 'metis::rete-matrix-link-join)
      (metis::kb-assert kb link-ab :support :asserted)
      (metis::kb-assert kb link-bc :support :asserted)
      (let ((d4 (metis:forward-chain-rete m)))
        (is (member conn d4 :test #'equal))
        (is-true (metis::kb-holds-p kb conn))
        (is (eq :rete (metis::fm-support (gethash conn (metis::kb-facts kb))))))
      ;; --- (e) retract premise → no re-fire of dependent from stale alpha ---
      (metis:retract-fact m phil)
      (metis:retract-fact m human)
      (metis:retract-fact m mortal)
      (is (not (metis::kb-holds-p kb phil)))
      (let ((d5 (metis:forward-chain-rete m)))
        (is (not (member mortal d5 :test #'equal)))
        (is (not (metis::kb-holds-p kb mortal)))
        (is (not (member human d5 :test #'equal)))
        (is (not (metis::kb-holds-p kb human)))))))

(test rete-compile-structure
  (with-fixture clean-mind ()
    (let ((net (metis:rete-compile (metis::mind-kb metis:*mind*))))
      (is (plusp (metis::rn-compiled-rules net)))
      (is (plusp (length (metis::rn-alphas net))))
      (is (plusp (length (metis::rn-prods net)))))))

(test durable-lmdb-roundtrip
  (with-fixture clean-mind ()
    (let* ((scratch "/tmp/grok-goal-d727c3e6d114/implementer/store")
           (path (uiop:ensure-directory-pathname
                  (merge-pathnames "lmdb-test/" scratch))))
      (ensure-directories-exist path)
      (metis:durable-close)
      (metis:durable-open path)
      (is-true (metis:durable-roundtrip-ok-p metis:*mind* "test-key"))
      (metis:durable-put "ping" (list :hello 42))
      (is (equal (list :hello 42) (metis:durable-get "ping")))
      (metis:durable-close))))

(test tms-formal-all-properties
  (multiple-value-bind (ok results)
      (metis:tms-formal-verify)
    (is-true ok)
    (is (= 6 (length results)))
    (dolist (r results)
      (is-true (getf r :pass)))))

(test large-corpus-load-and-query
  (with-fixture clean-mind ()
    (let ((stats (metis:load-large-corpus metis:*mind*
                                          :taxonomy 200
                                          :graph-nodes 80)))
      (is (>= (getf stats :total-facts) 200))
      (is (ask metis:*mind* (mread "(warm-blooded ent-0)")))
      (is (ask metis:*mind* (mread "(animal ent-0)")))
      (is (ask metis:*mind* (mread "(node n0)"))))))

(test api-security-auth-gate
  (is-true (metis:api-require-auth nil nil))
  (is-true (metis:api-require-auth "secret" "secret"))
  (is (null (metis:api-require-auth "wrong" "secret")))
  (is (null (metis:api-require-auth nil "secret"))))

(test api-security-input-gate
  (multiple-value-bind (ok reason)
      (metis:api-security-check-input "(mortal socrates)")
    (is-true ok)
    (is (null reason)))
  (multiple-value-bind (ok reason)
      (metis:api-security-check-input "#.(uiop:quit 0)")
    (is (not ok))
    (is (equal "reader-eval-forbidden" reason)))
  (multiple-value-bind (ok reason)
      (metis:api-security-check-input (make-string 70000 :initial-element #\a))
    (is (not ok))
    (is (equal "body-too-large" reason)))
  (multiple-value-bind (ok reason)
      (metis:api-security-check-input "(uiop:run-program \"id\")")
    (is (not ok))
    (is (equal "dangerous-form" reason))))

(test arc-continuum-cycle
  "ARC novel intelligence: real arc-boot + arc-cycle path."
  (with-fixture clean-mind ()
    (let* ((scratch "/tmp/grok-goal-d727c3e6d114/implementer/store")
           (path (uiop:ensure-directory-pathname
                  (merge-pathnames "arc-lmdb/" scratch))))
      (ensure-directories-exist path)
      (metis:set-config :durable-path path)
      (metis:durable-close)
      (let ((st (metis:arc-boot metis:*mind*)))
        (is (search "Autopoietic Reflexive Continuum" (metis:arc-thesis)))
        (let ((r (metis:arc-cycle st (list (mread "(philosopher emmy)")))))
          (is (getf r :arc))
          (is (plusp (getf r :cycle)))
          (is (ask metis:*mind* (mread "(mortal emmy)"))))
        (is (getf (metis:arc-status st) :cycles))
        (metis:durable-close)))))

(test adversarial-review-artifact-exists
  (let ((path (merge-pathnames
               "docs/adversarial-api-review.md"
               (asdf:system-source-directory :metis))))
    (is-true (probe-file path))
    (let ((text (uiop:read-file-string path)))
      (is (search "HIGH" text))
      (is (search "mitigat" text :test #'char-equal)))))
