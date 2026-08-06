;;;; suite.lisp — FiveAM tests for Metis
(defpackage :metis/tests
  (:use :cl :fiveam)
  (:import-from :metis
   :boot :reset-mind :*mind*
   :tell :ask :ask-all :assert-fact :assert-rule
   :forward-chain :plan :pursue :interpret
   :frame-get :self-model :reflect :synthesize-skill
   :find-skills :save-world :load-world :rewrite-rule
   :cognitive-cycle :production-boot))
(in-package :metis/tests)

(def-suite :metis
  :description "Metis cognitive architecture tests")
(in-suite :metis)

(defmacro with-metis-package (&body body)
  `(let ((*package* (find-package :metis)))
     ,@body))

(defun mread (string)
  "Read an s-expression in the :metis package."
  (let ((*package* (find-package :metis)))
    (read-from-string string)))

(def-fixture clean-mind ()
  (metis:boot :bootstrap t :reset t)
  (let ((metis:*mind* metis:*mind*))
    (&body)))

(test unification-basics
  (with-metis-package
    (is (equal '((metis::?x . metis::a))
               (remove t (metis::unify (mread "?x") (mread "a"))
                       :key #'car)))
    (is (metis::unify-fail-p (metis::unify (mread "(f ?x)") (mread "(g a)"))))
    (is (not (metis::unify-fail-p (metis::unify (mread "(f ?x)") (mread "(f a)")))))
    (is (metis::unify-fail-p (metis::unify (mread "?x") (mread "(f ?x)"))))
    (let ((s (metis::unify (mread "(loves ?x ?y)")
                           (mread "(loves john mary)"))))
      (is (equal (mread "john") (metis::apply-subst (mread "?x") s)))
      (is (equal (mread "mary") (metis::apply-subst (mread "?y") s))))))

(test kb-assert-query
  (with-fixture clean-mind ()
    (tell metis:*mind* (mread "(loves john mary)"))
    (is (equal (mread "(loves john mary)")
               (ask metis:*mind* (mread "(loves john mary)"))))
    (is (equal (mread "(loves john mary)")
               (ask metis:*mind* (mread "(loves john ?x)"))))
    (is (null (ask metis:*mind* (mread "(loves mary john)"))))))

(test backward-chaining
  (with-fixture clean-mind ()
    (is (equal (mread "(mortal socrates)")
               (ask metis:*mind* (mread "(mortal socrates)"))))
    (is (equal (mread "(can-fly tweety)")
               (ask metis:*mind* (mread "(can-fly tweety)"))))
    (is (null (ask metis:*mind* (mread "(can-fly opus)"))))
    (is (equal (mread "(bird opus)")
               (ask metis:*mind* (mread "(bird opus)"))))))

(test forward-chaining
  (with-fixture clean-mind ()
    (tell metis:*mind* (mread "(philosopher plato)"))
    (forward-chain metis:*mind*)
    (is (ask metis:*mind* (mread "(human plato)")))
    (is (ask metis:*mind* (mread "(mortal plato)")))))

(test frames-inheritance
  (with-fixture clean-mind ()
    (is (eq t (frame-get metis:*mind* 'metis::a 'metis::graspable)))
    (is (eq 'metis::red (frame-get metis:*mind* 'metis::a 'metis::color)))
    (is (equal "Metis" (frame-get metis:*mind* 'metis::metis-self 'metis::name)))))

(test strips-planner-stack
  (with-fixture clean-mind ()
    (let ((result (plan metis:*mind* (list (mread "(on b c)")) :execute t)))
      (is (getf result :plan))
      (is (ask metis:*mind* (mread "(on b c)"))))))

(test cognitive-pursue
  (with-fixture clean-mind ()
    (let ((r (pursue metis:*mind* (list (mread "(clear a)")) :max-cycles 16)))
      (is (or (getf r :success)
              (ask metis:*mind* (mread "(clear a)")))))))

(test introspection-self
  (with-fixture clean-mind ()
    (let ((sm (self-model metis:*mind*)))
      (is (equal "Metis" (getf sm :identity)))
      (is (plusp (getf (getf sm :knowledge) :facts))))
    (let ((r (reflect metis:*mind* :self)))
      (is (getf r :self))
      (is (consp (getf r :suggested-strategies))))))

(test skill-synthesis
  (with-fixture clean-mind ()
    (let* ((pr (plan metis:*mind* (list (mread "(on b c)")) :execute nil))
           (steps (getf pr :steps)))
      (is-true steps)
      (let ((sk (synthesize-skill metis:*mind* 'metis::stack-b-on-c steps
                                  :goals (list (mread "(on b c)")))))
        (is (eq 'metis::stack-b-on-c (metis::skill-name sk)))
        (is-true (find-skills metis:*mind* :pattern "STACK"))))))

(test interpret-language
  (with-fixture clean-mind ()
    (is (eq :ok (interpret metis:*mind* (mread "(tell (loves ada lovelace))"))))
    (is (equal (mread "(loves ada lovelace)")
               (interpret metis:*mind* (mread "(ask (loves ada ?x))"))))
    (is (stringp (interpret metis:*mind* (mread "(status)"))))))

(test world-roundtrip
  (with-fixture clean-mind ()
    (tell metis:*mind* (mread "(unique-fact-42 yes)"))
    (let ((path (save-world metis:*mind* "test-world")))
      (is (probe-file path))
      (boot :bootstrap t :reset t)
      (is (null (ask metis:*mind* (mread "(unique-fact-42 yes)"))))
      (load-world metis:*mind* "test-world")
      (is (equal (mread "(unique-fact-42 yes)")
                 (ask metis:*mind* (mread "(unique-fact-42 yes)")))))))

(test rewrite-rule-self-mod
  (with-fixture clean-mind ()
    (rewrite-rule metis:*mind* 'metis::humans-mortal
                  (mread "(fallible ?x)")
                  (list (mread "(human ?x)")))
    (is (equal (mread "(fallible socrates)")
               (ask metis:*mind* (mread "(fallible socrates)"))))))
