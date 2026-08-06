;;;; meta.lisp — strategy selection and meta-reasoning
(in-package :metis)

(defparameter *strategies*
  '(:retrieve :forward :backward :plan :htn :skill :tool :llm :reflect :give-up)
  "Ordered catalogue of cognitive strategies.")

(defun meta-goal-type (goal)
  (cond ((null goal) :none)
        ((and (consp goal) (eq (car goal) :achieve)) :achieve)
        ((and (consp goal) (eq (car goal) :prove)) :prove)
        ((and (consp goal) (eq (car goal) :answer)) :answer)
        ((and (consp goal) (eq (car goal) :do)) :do)
        ((and (consp goal) (eq (car goal) :learn)) :learn)
        ((and (consp goal) (member (car goal)
                                   '(on clear holding arm-empty
                                     is-a can has location)))
         :achieve)
        ((variablep (if (consp goal) (car goal) goal)) :answer)
        (t :prove)))

(defun meta-suggest-strategies (mind)
  "Heuristic policy over strategies given current goals and resources."
  (let* ((goals (mind-goals mind))
         (g (first goals))
         (gtype (meta-goal-type g))
         (n-skills (hash-table-count (pmem-skills (mind-pm mind))))
         (n-ops (hash-table-count (pd-operators (mind-domain mind))))
         (n-rules (length (kb-rules (mind-kb mind))))
         (suggestions nil))
    (case gtype
      ((:prove :answer)
       (push :retrieve suggestions)
       (when (plusp n-rules) (push :backward suggestions))
       (when (plusp n-rules) (push :forward suggestions)))
      (:achieve
       ;; Prefer planning for world-state goals before soft retrieval.
       (when (plusp n-ops) (push :plan suggestions))
       (when (and (mind-htn mind)
                  (plusp (hash-table-count (hd-methods (mind-htn mind)))))
         (push :htn suggestions))
       (when (plusp n-skills) (push :skill suggestions))
       (when (plusp n-rules) (push :forward suggestions))
       (push :retrieve suggestions))
      (:do
       (push :tool suggestions)
       (push :skill suggestions))
      (:learn
       (push :reflect suggestions)
       (push :plan suggestions))
      (t
       (push :retrieve suggestions)
       (push :backward suggestions)
       (push :plan suggestions)))
    (when (llm-enabled-p)
      (push :llm suggestions))
    (push :reflect suggestions)
    (push :give-up suggestions)
    (remove-duplicates (nreverse suggestions))))

(defun meta-select-strategy (mind &optional goal)
  (let* ((goal (or goal (first (mind-goals mind))))
         (ranked (meta-suggest-strategies mind))
         ;; bias against strategies that failed for THIS goal recently
         (recent-fail
          (remove-if-not
           (lambda (e)
             (equal (getf (ep-situation e) :goals)
                    (list goal)))
           (em-recall (mind-em mind) :tag :failure :limit 20)))
         (failed-strats
          (mapcar (lambda (e) (getf (ep-meta e) :strategy))
                  recent-fail)))
    ;; Prefer first non-failed strategy; never sticky-loop on :reflect alone.
    (or (find-if (lambda (s)
                   (and (not (member s failed-strats))
                        (not (eq s :give-up))))
                 ranked)
        (find :plan ranked)
        (first ranked)
        :reflect)))

(defun meta-after-outcome (mind strategy success-p detail)
  (em-remember (mind-em mind)
               :situation (list :strategy strategy
                                :goals (copy-tree (mind-goals mind)))
               :action strategy
               :outcome (if success-p :success :failure)
               :valence (if success-p 0.4 -0.4)
               :tags (list (if success-p :success :failure) :meta strategy)
               :meta (list :strategy strategy :detail detail))
  (mind-trace-push mind :meta-outcome strategy
                   (if success-p :success :failure) detail))

(defun meta-should-compile-plan-p (mind plan goals)
  "Learn procedural skill when plan is non-trivial and novel."
  (declare (ignore mind))
  (and plan (>= (length plan) 1) goals))

(defun meta-deliberate (mind)
  "Produce a deliberation structure: strategy + focus goal + rationale."
  (let* ((goal (first (mind-goals mind)))
         (strategy (meta-select-strategy mind goal))
         (rationale
          (list :goal goal
                :goal-type (meta-goal-type goal)
                :strategy strategy
                :alternatives (meta-suggest-strategies mind)
                :wm-top (subseq (wm-contents (mind-wm mind))
                                0
                                (min 5 (length (wm-contents (mind-wm mind))))))))
    (mind-trace-push mind :deliberate rationale)
    (wm-add (mind-wm mind) (list :deliberation rationale) :source :meta)
    rationale))
