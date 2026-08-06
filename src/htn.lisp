;;;; htn.lisp — hierarchical task network planning
(in-package :metis)

(defstruct (htn-method (:conc-name hm-))
  name
  task          ; (task-name . args-pattern)
  preconds
  subtasks      ; list of tasks (primitive or compound)
  (priority 0))

(defstruct (htn-domain (:conc-name hd-))
  (methods (make-hash-table :test #'eq))  ; task-name -> list of methods
  (primitives (make-hash-table :test #'eq)) ; task-name -> strips-like op name
  (lock (bt:make-lock "metis-htn")))

(defun make-empty-htn ()
  (make-htn-domain))

(defun htn-defmethod (htn name task preconds subtasks &key (priority 0))
  (let ((m (make-htn-method
            :name name
            :task task
            :preconds (ensure-list preconds)
            :subtasks (ensure-list subtasks)
            :priority priority)))
    (let ((key (if (consp task) (car task) task)))
      (push m (gethash key (hd-methods htn)))
      (setf (gethash key (hd-methods htn))
            (sort (copy-list (gethash key (hd-methods htn)))
                  #'> :key #'hm-priority)))
    m))

(defun htn-defprimitive (htn task-name operator-name)
  (setf (gethash task-name (hd-primitives htn)) operator-name))

(defun %htn-match-preconds (state preconds subst)
  "Return list of subst extensions where preconds hold in STATE."
  (if (null preconds)
      (list subst)
      (let* ((lit (apply-subst (first preconds) subst))
             (rest (rest preconds))
             (out nil))
        (cond
          ((and (consp lit) (eq (car lit) 'not))
           (let ((inner (second lit)))
             ;; negation: succeed if no grounding of inner is in state
             (if (groundp inner)
                 (unless (state-holds state inner)
                   (setf out (%htn-match-preconds state rest subst)))
                 ;; if free vars, succeed only if no candidate unifies into state
                 (let ((any nil))
                   (dolist (f (state-list state))
                     (unless (unify-fail-p (unify inner f subst))
                       (setf any t)))
                   (unless any
                     (setf out (%htn-match-preconds state rest subst)))))))
          (t
           (if (groundp lit)
               (when (state-holds state lit)
                 (setf out (%htn-match-preconds state rest subst)))
               (dolist (f (state-list state))
                 (let ((s2 (unify lit f subst)))
                   (unless (unify-fail-p s2)
                     (setf out
                           (nconc out (%htn-match-preconds state rest s2)))))))))
        out)))

(defun %htn-methods-for (htn task)
  (let ((name (if (consp task) (car task) task)))
    (copy-list (gethash name (hd-methods htn)))))

(defun %htn-match-task (method task)
  (unify (hm-task method) task))

(defun htn-decompose (htn state tasks
                      &key (max-depth 16) (max-nodes 2000)
                        domain)
  "Decompose compound TASKS into a list of primitive grounded STRIPS steps.
   DOMAIN is planner-domain for grounding primitives."
  (let ((nodes 0)
        (domain (or domain (and *mind* (mind-domain *mind*)))))
    (labels
        ((solve (state todo depth)
           (when (> (incf nodes) max-nodes)
             (return-from htn-decompose (values nil nodes :max-nodes)))
           (when (< depth 0)
             (return-from solve nil))
           (if (null todo)
               (list nil) ; one empty plan success
               (let ((task (first todo))
                     (rest (rest todo)))
                 (cond
                   ;; primitive?
                   ((and (consp task)
                         (gethash (car task) (hd-primitives htn)))
                    (let* ((op-name (gethash (car task) (hd-primitives htn)))
                           (op (and domain (gethash op-name (pd-operators domain))))
                           (params (cdr task)))
                      (when op
                        (let* ((subst (mapcar #'cons (op-params op) params))
                               (gop (ground-op op subst)))
                          (when (and (every #'groundp (getf gop :preconds))
                                     (applicable-p state gop))
                            (let* ((new-state (apply-op state gop))
                                   (tails (solve new-state rest depth)))
                              (mapcar (lambda (tail) (cons gop tail))
                                      tails)))))))
                   (t
                    ;; compound: try methods
                    (let ((results nil))
                      (dolist (method (%htn-methods-for htn task))
                        (let ((s0 (%htn-match-task method task)))
                          (unless (unify-fail-p s0)
                            (dolist (s (%htn-match-preconds state
                                                            (hm-preconds method)
                                                            s0))
                              (let* ((subs (mapcar (lambda (st)
                                                     (apply-subst st s))
                                                   (hm-subtasks method)))
                                     (new-todo (append subs rest))
                                     (plans (solve state new-todo (1- depth))))
                                (setf results (nconc results plans)))))))
                      results)))))))
      (let ((plans (solve state (ensure-list tasks) max-depth)))
        (values (first plans) nodes (if plans :ok :fail))))))

(defun htn-plan (mind tasks &key (execute nil))
  "HTN plan from mind state for compound tasks."
  (let* ((m (ensure-mind mind))
         (state (state-from-facts
                 (remove-if-not #'groundp (kb-all-facts (mind-kb m)))))
         (htn (mind-htn m))
         (tasks (if (and (consp tasks) (symbolp (car tasks)))
                    (list tasks)
                    (ensure-list tasks))))
    (multiple-value-bind (steps nodes status)
        (htn-decompose htn state tasks :domain (mind-domain m))
      (mind-trace-push m :htn tasks (when steps (plan-to-sexps steps))
                       nodes status)
      (when (and steps execute)
        (execute-grounded-plan (mind-kb m) steps)
        (forward-chain m)
        (dolist (s steps)
          (dolist (a (getf s :add))
            (when (mind-tms m)
              (tms-assert (mind-tms m) a :informant :htn))
            (when (mind-beliefs m)
              (belief-set (mind-beliefs m) a 0.95)))))
      (list :htn (when steps (plan-to-sexps steps))
            :steps steps
            :nodes nodes
            :status status))))
