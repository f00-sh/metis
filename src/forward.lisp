;;;; forward.lisp — agenda-based forward chaining
(in-package :metis)

(defstruct (forward-engine (:conc-name fe-))
  kb
  (agenda nil)
  (fired (make-hash-table :test #'equal)) ; (rule-id . bindings-key) -> t
  (trace nil)
  (derived 0))

(defun new-forward-engine (kb)
  (make-forward-engine :kb kb))

(defun %match-body (kb body subst)
  "Return list of extensions of SUBST that satisfy BODY against KB facts."
  (if (null body)
      (list subst)
      (let* ((lit (apply-subst (first body) subst))
             (rest (rest body))
             (results nil))
        (cond
          ;; (not LIT) — negation as failure on ground facts only
          ((and (consp lit) (eq (car lit) 'not))
           (let ((inner (second lit)))
             (if (and (groundp inner) (kb-holds-p kb inner))
                 nil
                 (when (or (groundp inner)
                           (not (collect-variables inner)))
                   (setf results (%match-body kb rest subst))))))
          (t
           (dolist (fact (kb-candidates kb lit))
             (let ((s2 (unify lit fact subst)))
               (unless (unify-fail-p s2)
                 (setf results
                       (nconc results (%match-body kb rest s2))))))))
        results)))

(defun %rule-instances (kb rule)
  (let* ((renamed (rename-variables
                   (cons (rule-head rule) (rule-body rule))))
         (head (car renamed))
         (body (cdr renamed)))
    (mapcar (lambda (subst)
              (list :rule rule
                    :subst subst
                    :head (apply-subst head subst)
                    :body (mapcar (lambda (b) (apply-subst b subst)) body)))
            (%match-body kb body +no-bindings+))))

(defun %already-fired-p (engine rule subst)
  (gethash (cons (rule-id rule) (%bindings-key subst)) (fe-fired engine)))

(defun %mark-fired (engine rule subst)
  (setf (gethash (cons (rule-id rule) (%bindings-key subst))
                 (fe-fired engine))
        t))

(defun %trace-fe (engine event &rest args)
  (when (get-config :trace-reasoning)
    (push (list* (now-iso) event args) (fe-trace engine))
    (when (> (length (fe-trace engine)) (get-config :trace-limit 200))
      (setf (fe-trace engine)
            (subseq (fe-trace engine) 0 (get-config :trace-limit 200))))))

(defun forward-refill-agenda (engine)
  (let ((kb (fe-kb engine))
        (agenda nil))
    (dolist (rule (kb-rules kb))
      (dolist (inst (%rule-instances kb rule))
        (let ((head (getf inst :head))
              (subst (getf inst :subst)))
          (unless (or (kb-holds-p kb head)
                      (%already-fired-p engine rule subst)
                      (not (groundp head)))
            (push inst agenda)))))
    ;; conflict resolution: priority, then more body literals (specificity)
    (setf (fe-agenda engine)
          (sort agenda
                (lambda (a b)
                  (let ((ra (getf a :rule)) (rb (getf b :rule)))
                    (cond ((/= (rule-priority ra) (rule-priority rb))
                           (> (rule-priority ra) (rule-priority rb)))
                          (t (> (length (rule-body ra))
                                (length (rule-body rb)))))))))
    (fe-agenda engine)))

(defun forward-step (engine)
  "Fire one agenda item. Returns derived fact or NIL."
  (unless (fe-agenda engine)
    (forward-refill-agenda engine))
  (let ((inst (pop (fe-agenda engine))))
    (when inst
      (let* ((rule (getf inst :rule))
             (head (getf inst :head))
             (subst (getf inst :subst)))
        (when (and (groundp head)
                   (not (kb-holds-p (fe-kb engine) head))
                   (not (%already-fired-p engine rule subst)))
          (%mark-fired engine rule subst)
          (incf (rule-times-fired rule))
          (kb-assert (fe-kb engine) head :support :derived)
          (incf (fe-derived engine))
          (%trace-fe engine :fire (rule-name rule) head)
          ;; agenda dirty
          (setf (fe-agenda engine) nil)
          head)))))

(defun run-forward (kb &key (max-iterations nil) (engine nil))
  "Forward chain to quiescence. Returns (values derived-facts engine)."
  (let* ((eng (or engine (new-forward-engine kb)))
         (max (or max-iterations (get-config :max-forward-iterations 500)))
         (derived nil))
    (loop for i from 1 to max
          for fact = (forward-step eng)
          while fact
          do (push fact derived)
          finally (return (values (nreverse derived) eng)))))
