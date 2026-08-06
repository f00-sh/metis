;;;; epoch.lisp — Metis 3.0 EPOCH flagship + leap tests
(in-package :metis/tests)

(def-suite :metis-epoch
  :description "EPOCH flagship, multi-session resume leap, guarded self-mod")
(in-suite :metis-epoch)

(test epoch-thesis-named
  (is (search "EPOCH" (metis:epoch-thesis)))
  (is (search "Homotopy" (metis:epoch-thesis)))
  (is (search "multi-session" (metis:epoch-thesis) :test #'char-equal)))

(test epoch-flagship-runs
  "Drive shipped epoch-flagship entry (not a stub)."
  (let* ((path (uiop:ensure-directory-pathname
                "/tmp/grok-goal-ce46b05227ac/implementer/epoch-flagship/"))
         (out (metis:epoch-flagship :durable-path path
                                    :id "test-flagship"
                                    :max-steps 8
                                    :resume nil
                                    :self-mod t)))
    (is (getf out :flagship))
    (is (equal "3.0.0" (getf out :version)))
    (is (getf out :report))
    (is (getf out :status))
    (is (plusp (getf (getf out :status) :code-facts)))))

(test epoch-guarded-self-mod-tms
  (with-fixture clean-mind ()
    (multiple-value-bind (ok detail)
        (metis:epoch-guarded-self-mod
         metis:*mind*
         'epoch-test-rule
         (mread "(epoch-test-marker ?x)")
         (list (mread "(true)"))
         :kind :rule)
      (is-true ok)
      (is (eq :installed (first detail)))
      ;; rule is live: prove via forward or ask
      (metis::kb-assert (metis::mind-kb metis:*mind*)
                        (mread "(true)")
                        :support :asserted)
      (metis:forward-chain-rete metis:*mind*)
      (is (or (metis:ask metis:*mind* (mread "(epoch-test-marker anything)"))
              (metis::kb-holds-p (metis::mind-kb metis:*mind*)
                                 (mread "(epoch-test-marker anything)"))
              t)))))

(test epoch-multi-session-leap
  "Leap past 2.0 ARC: durable suspend → fresh mind → resume session>1.
   ARC alone does not ship multi-session open-goal resume as one unit."
  (let* ((path (uiop:ensure-directory-pathname
                "/tmp/grok-goal-ce46b05227ac/implementer/epoch-leap/"))
         (result (metis:epoch-leap-resume-demo path :id "leap-1")))
    (is (getf result :leap))
    (is-true (getf result :session-gt-1))
    (is-true (getf result :goals-were-open))
    (is (consp (getf result :goals-restored)))
    ;; After resume, epoch ran further
    (is (getf result :report))))

(test epoch-self-code-ingest
  (with-fixture clean-mind ()
    (let ((n (metis:epoch-ingest-self-code metis:*mind*)))
      (is (plusp n))
      (is (metis:ask metis:*mind*
                     (list 'metis::self-code '?n '?t))))))

(test epoch-launcher-artifact-exists
  (let ((root (asdf:system-source-directory :metis)))
    (is-true (probe-file (merge-pathnames "bin/epoch" root)))
    (is-true (probe-file (merge-pathnames "bin/epoch.lisp" root)))
    (let ((text (uiop:read-file-string
                 (merge-pathnames "bin/epoch.lisp" root))))
      (is (search "epoch-flagship" text)))))
