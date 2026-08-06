(ql:quickload :metis :silent t)
(metis:boot)
(format t "FACTS:~%~{  ~S~%~}" (metis:facts))
(format t "RULES:~%")
(dolist (r (metis:rules))
  (format t "  ~S: ~S <- ~S~%"
          (metis::rule-name r)
          (metis::rule-head r)
          (metis::rule-body r)))

(format t "~%prove mortal:~%")
(multiple-value-bind (ok sub all tr)
    (metis:prove '(mortal socrates) :kb (metis::mind-kb metis:*mind*))
  (format t "ok=~S sub=~S all=~S~%trace=~S~%" ok sub all (subseq tr 0 (min 20 (length tr)))))

(format t "~%candidates for philosopher:~%")
(format t "~S~%" (metis::kb-candidates (metis::mind-kb metis:*mind*) '(philosopher ?x)))

(format t "~%unify test: ~S~%" (metis::unify '(mortal ?x) '(mortal socrates)))

(format t "~%plan debug~%")
(let* ((kb (metis::mind-kb metis:*mind*))
       (facts (remove-if-not #'metis::groundp (metis::kb-all-facts kb)))
       (domain (metis::mind-domain metis:*mind*)))
  (format t "state facts: ~S~%" facts)
  (format t "ops: ~S~%" (mapcar #'metis::op-name (metis::pd-operators-list domain)))
  (multiple-value-bind (steps st nodes)
      (metis::plan-search domain facts '((on b c)))
    (format t "steps=~S nodes=~S~%" steps nodes)))

(uiop:quit 0)
