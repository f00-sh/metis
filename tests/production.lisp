;;;; production.lisp — production-grade feature tests
(in-package :metis/tests)

(def-suite :metis-production
  :description "Metis 1.0 production features")
(in-suite :metis-production)

(test version-and-build
  (is (stringp (metis:metis-version-string)))
  (is (equal "2.0.0" metis:*metis-version*))
  (is (getf (metis:metis-build-info) :version)))

(test tms-justify-and-why
  (with-fixture clean-mind ()
    (let ((tms (metis::mind-tms metis:*mind*)))
      (metis::tms-assert tms (mread "(rain)") :informant :asserted)
      (metis::tms-justify tms (mread "(wet-grass)")
                          (list (mread "(rain)"))
                          :informant 'rain-rule)
      (is (metis::tms-in-p tms (mread "(wet-grass)")))
      (is (metis::tms-why tms (mread "(wet-grass)")))
      (metis::tms-retract-assumption tms (mread "(rain)"))
      (is (not (metis::tms-in-p tms (mread "(wet-grass)")))))))

(test belief-weights
  (with-fixture clean-mind ()
    (metis:belief-set (metis::mind-beliefs metis:*mind*)
                      (mread "(alien)") 0.2)
    (is (< (metis:belief-get (metis::mind-beliefs metis:*mind*)
                             (mread "(alien)"))
           0.3))))

(test htn-blocks-clear
  (with-fixture clean-mind ()
    (let ((r (metis:htn-plan metis:*mind* (mread "(clear-rec a)") :execute t)))
      (is (eq (getf r :status) :ok))
      (is (ask metis:*mind* (mread "(clear a)"))))))

(test csp-all-diff
  (let* ((csp (metis::make-csp
               :variables '(x y z)
               :domains '((x . (1 2 3)) (y . (1 2 3)) (z . (1 2 3)))
               :constraints (list (metis::csp-all-diff 'x 'y 'z))))
         (sol (metis:csp-solve csp)))
    (is-true sol)
    (is (= 3 (length (remove-duplicates (mapcar #'cdr sol) :test #'equal))))))

(test transactional-rollback
  (with-fixture clean-mind ()
    (let ((tx (metis:tx-begin metis:*mind*)))
      (metis:tx-assert tx (mread "(temp-fact 1)"))
      (is (ask metis:*mind* (mread "(temp-fact 1)")))
      (metis:tx-rollback tx)
      (is (null (ask metis:*mind* (mread "(temp-fact 1)")))))))

(test transactional-commit
  (with-fixture clean-mind ()
    (metis:with-mind-transaction (tx metis:*mind*)
      (metis:tx-assert tx (mread "(committed-fact yes)")))
    (is (ask metis:*mind* (mread "(committed-fact yes)")))))

(test sandbox-blocks-forbidden
  (signals metis::metis-error
    (metis:sandboxed-eval '(uiop:quit 0))))

(test sandbox-allows-safe
  (is (= 4 (metis:sandboxed-eval '(+ 2 2)))))

(test society-ensemble
  (with-fixture clean-mind ()
    (let ((soc (metis:society-default-ensemble)))
      (is (>= (length (metis::society-minds soc)) 4))
      (metis:society-send soc "conductor" "planner"
                          (list :goal (mread "(clear a)")))
      (metis:society-step soc)
      (is (plusp (length (metis::bb-entries (metis::soc-blackboard soc))))))))

(test kinship-domain
  (with-fixture clean-mind ()
    (is (ask metis:*mind* (mread "(grandparent cronus ares)")))))

(test circuit-domain
  (with-fixture clean-mind ()
    (is (ask metis:*mind* (mread "(signal w3 on)")))))

(test explain-deep-why
  (with-fixture clean-mind ()
    (let ((e (metis:explain-deep metis:*mind*
                                 (list :why (mread "(mortal socrates)")))))
      (is (getf e :provable)))))

(test production-boot-smoke
  (let ((r (metis:production-boot :api nil :daemon nil :society t)))
    (is (equal "2.0.0" (getf r :version)))
    (is (getf r :society))
    (metis:society-stop metis:*society*)))

(test learn-chunk-from-plan
  (with-fixture clean-mind ()
    (let* ((pr (plan metis:*mind* (list (mread "(on b c)")) :execute nil))
           (steps (getf pr :steps)))
      (is-true steps)
      (let ((sk (metis:learn-from-plan metis:*mind* steps
                                       (list (mread "(on b c)"))
                                       :name 'metis::chunk-test)))
        (is (eq 'metis::chunk-test (metis::skill-name sk)))))))
