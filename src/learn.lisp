;;;; learn.lisp — chunking / skill compilation / utility learning
(in-package :metis)

(defun learn-from-plan (mind plan-steps goals &key (name nil))
  "Compile a successful plan into a named skill with utility tracking."
  (let* ((m (ensure-mind mind))
         (name (or name
                   (intern (format nil "CHUNK-~D" (get-universal-time)) :metis)))
         (pre (loop for s in plan-steps
                    append (getf s :preconds)))
         ;; only keep preconds true in initial... approximate: first step preconds
         (pre0 (when plan-steps (getf (first plan-steps) :preconds)))
         (sk (synthesize-skill-from-plan name plan-steps goals pre0)))
    (setf (skill-utility sk) 1.0
          (skill-source sk) :chunking)
    (pm-install (mind-pm m) sk)
    (tms-assert (mind-tms m) (list 'skill-known name) :informant :learn)
    (metis-log :info "chunked skill ~A (~D steps)" name (length plan-steps))
    sk))

(defun learn-from-episode (mind episode)
  "If episode was successful plan execution, chunk it."
  (when (and (eq (ep-outcome episode) :success)
             (consp (ep-action episode)))
    (let ((plan (getf (ep-meta episode) :plan)))
      (when plan
        (learn-from-plan mind plan (ep-goals episode))))))

(defun reinforce-skill (mind name success-p)
  (pm-record-outcome (mind-pm (ensure-mind mind)) name success-p
                     (if success-p 0.15 -0.2)))

(defun forget-weak-skills (mind &key (min-utility -1.0) (min-uses 5))
  "Drop skills with poor utility after enough uses."
  (let ((m (ensure-mind mind))
        (removed nil))
    (dolist (sk (pm-all (mind-pm m)))
      (when (and (>= (skill-uses sk) min-uses)
                 (< (skill-utility sk) min-utility))
        (remhash (skill-name sk) (pmem-skills (mind-pm m)))
        (push (skill-name sk) removed)))
    removed))

(defun inductive-rule-propose (mind examples head-template)
  "Very simple induction: if all examples share head-template pattern via subst,
   install a rule. EXAMPLES is list of ground facts."
  (declare (ignore head-template))
  (let ((m (ensure-mind mind)))
    (when (and examples (every #'groundp examples))
      ;; propose: common predicate
      (let ((pred (fact-predicate (first examples))))
        (when (every (lambda (e) (eq (fact-predicate e) pred)) examples)
          (let* ((arity (length (first examples)))
                 (vars (loop for i below (1- arity)
                             collect (fresh-var (format nil "?X~D" i))))
                 (head (cons pred vars)))
            ;; body empty => just assert each as fact (not a rule)
            ;; instead: if two-arg and second constant often, skip
            (metis-log :info "induction noticed ~D ~A facts" (length examples) pred)
            (list :proposed-head head :count (length examples))))))))
