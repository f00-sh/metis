;;;; explain.lisp — deep explanation / proof trees
(in-package :metis)

(defun explain-fact (mind fact)
  "Multi-source explanation of why FACT is believed."
  (let* ((m (ensure-mind mind))
         (in-kb (kb-holds-p (mind-kb m) fact))
         (tms (and (mind-tms m) (tms-why (mind-tms m) fact)))
         (belief (and (mind-beliefs m) (belief-get (mind-beliefs m) fact)))
         (proof (multiple-value-list (prove fact :kb (mind-kb m))))
         (episodes (recall-episodes m :pattern fact :limit 5)))
    (list :fact fact
          :in-kb (and in-kb t)
          :belief belief
          :tms tms
          :provable (first proof)
          :proof-bindings (pretty-subst (second proof))
          :proof-trace (fourth proof)
          :episodes (mapcar (lambda (e)
                              (list :action (ep-action e)
                                    :outcome (ep-outcome e)
                                    :valence (ep-valence e)))
                            episodes)
          :frame (ignore-errors
                  (when (and (consp fact) (symbolp (second fact)))
                    (fs-describe (mind-frames m) (second fact)))))))

(defun explain-goal (mind goal)
  (let* ((m (ensure-mind mind))
         (delib (mind-last-deliberation m))
         (trace (reason-trace m 40)))
    (list :goal goal
          :status (cond ((kb-holds-p (mind-kb m) (%goal-literal goal)) :achieved)
                        ((member goal (mind-goals m) :test #'equal) :active)
                        (t :unknown))
          :last-deliberation delib
          :strategies (meta-suggest-strategies m)
          :trace trace
          :related-skills
          (mapcar #'skill-name (pm-all (mind-pm m))))))

(defun explain-deep (mind topic)
  "Unified explain entry used by API and REPL."
  (cond
    ((null topic) (explain mind nil))
    ((and (consp topic) (eq (car topic) :goal))
     (explain-goal mind (second topic)))
    ((and (consp topic) (eq (car topic) :why))
     (explain-fact mind (second topic)))
    ((keywordp topic) (explain mind topic))
    (t (or (explain-fact mind topic)
           (explain mind topic)))))
