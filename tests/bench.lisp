;;;; bench.lisp — performance / stress benchmarks (also FiveAM suite)
(in-package :metis/tests)

(def-suite :metis-bench :description "Metis stress benchmarks")
(in-suite :metis-bench)

(defun %time-ms (thunk)
  (let* ((s (get-internal-real-time))
         (v (funcall thunk))
         (e (get-internal-real-time)))
    (values v
            (* 1000.0 (/ (- e s) internal-time-units-per-second)))))

(test bench-forward-chain-bulk
  (with-fixture clean-mind ()
    (dotimes (i 50)
      (tell metis:*mind*
            (let ((*package* (find-package :metis)))
              (read-from-string (format nil "(philosopher p~D)" i)))))
    (multiple-value-bind (derived ms)
        (%time-ms (lambda () (forward-chain metis:*mind*)))
      (declare (ignore derived))
      (format t "~&[bench] forward-chain 50 philos: ~,2F ms~%" ms)
      (is (< ms 5000.0))
      (is (ask metis:*mind* (mread "(mortal p0)"))))))

(test bench-plan-stack
  (with-fixture clean-mind ()
    (multiple-value-bind (res ms)
        (%time-ms (lambda ()
                    (plan metis:*mind* (list (mread "(on b c)")) :execute t)))
      (format t "~&[bench] plan on-b-c: ~,2F ms~%" ms)
      (is (getf res :plan))
      (is (< ms 2000.0)))))

(test bench-prove-depth
  (with-fixture clean-mind ()
    (multiple-value-bind (ans ms)
        (%time-ms (lambda ()
                    (ask metis:*mind* (mread "(grandparent cronus ares)"))))
      (format t "~&[bench] prove grandparent: ~,2F ms => ~S~%" ms ans)
      (is-true ans)
      (is (< ms 1000.0)))))

(test bench-1000-cycles-idle
  (with-fixture clean-mind ()
    (multiple-value-bind (_ ms)
        (%time-ms
         (lambda ()
           (dotimes (i 200)
             (cognitive-cycle metis:*mind*))))
      (declare (ignore _))
      (format t "~&[bench] 200 idle cycles: ~,2F ms~%" ms)
      (is (< ms 5000.0)))))
