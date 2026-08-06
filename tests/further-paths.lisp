;;;; further-paths.lisp — Metis 2.0 acceptance tests (real entry points)
(in-package :metis/tests)

(def-suite :metis-further
  :description "RETE, durable LMDB, TMS formal, large KB, API security, ARC")
(in-suite :metis-further)

(test rete-forward-derives-mortal
  "RETE path derives mortal from philosopher via real forward-chain-rete."
  (with-fixture clean-mind ()
    (tell metis:*mind* (mread "(philosopher hypatia)"))
    (let ((derived (metis:forward-chain-rete metis:*mind*)))
      (declare (ignore derived))
      (is (equal (mread "(mortal hypatia)")
                 (ask metis:*mind* (mread "(mortal hypatia)"))))
      (is (equal (mread "(human hypatia)")
                 (ask metis:*mind* (mread "(human hypatia)")))))))

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
