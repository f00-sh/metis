;;;; backward.lisp — Prolog-style backward chaining with depth limit
(in-package :metis)

(defstruct (proof-state (:conc-name ps-))
  goal-stack
  subst
  depth
  (trace nil)
  (choice-points 0))

(defvar *proof-trace* nil)

(defun %trace-proof (event &rest args)
  (when (get-config :trace-reasoning)
    (push (list* (now-iso) event args) *proof-trace*)
    (when (> (length *proof-trace*) (get-config :trace-limit 200))
      (setf *proof-trace* (subseq *proof-trace* 0 (get-config :trace-limit 200))))))

(defun %primitive-goal-p (goal)
  (and (consp goal)
       (member (car goal)
               '(= == \\= \\== not call lisp eval cut true fail member
                 > < >= <= numberp atom symbolp)
               :test #'eq)))

(defun %eval-primitive (goal subst kb)
  "Handle built-in goals. Return list of subst extensions or :cut / :fail."
  (declare (ignore kb))
  (let* ((g (apply-subst goal subst))
         (op (car g))
         (args (cdr g)))
    (case op
      ((true) (list subst))
      ((fail) nil)
      ((cut) :cut)
      ((= ==)
       (let ((s (unify (first args) (second args) subst)))
         (unless (unify-fail-p s) (list s))))
      ((/= \\= \\==)
       (if (unify-fail-p (unify (first args) (second args) subst))
           (list subst)
           nil))
      ((not)
       ;; negation as failure — succeed if no proof of inner
       (if (null (prove-all (list (first args)) subst
                            :kb *current-kb* :depth-left 16 :silent t))
           (list subst)
           nil))
      ((> < >= <=)
       (let ((a (apply-subst (first args) subst))
             (b (apply-subst (second args) subst)))
         (when (and (numberp a) (numberp b)
                    (funcall (case op
                               (> #'>) (< #'<) (>= #'>=) (<= #'<=))
                             a b))
           (list subst))))
      ((numberp atom symbolp)
       (let ((x (apply-subst (first args) subst)))
         (when (funcall (case op
                          (numberp #'numberp)
                          (atom #'atom)
                          (symbolp #'symbolp))
                        x)
           (list subst))))
      ((member)
       (let ((item (first args))
             (lst (apply-subst (second args) subst)))
         (when (listp lst)
           (loop for el in lst
                 for s = (unify item el subst)
                 unless (unify-fail-p s)
                 collect s))))
      ((lisp eval call)
       (let* ((form (apply-subst (first args) subst))
              (result (handler-case (eval form)
                        (error (e)
                          (declare (ignore e))
                          (return-from %eval-primitive nil)))))
         (if (rest args)
             (let ((s (unify (second args) result subst)))
               (unless (unify-fail-p s) (list s)))
             (list subst))))
      (t nil))))

(defvar *current-kb* nil)

(defun prove-all (goals subst &key kb (depth-left nil) (silent nil))
  "Return list of successful substitutions for GOALS."
  (let* ((*current-kb* (or kb *current-kb*))
         (depth-left (or depth-left (get-config :max-proof-depth 64)))
         (subst (or subst +no-bindings+))
         (results nil))
    (labels
        ((solve (gs subst depth)
           (when (< depth 0)
             (%trace-proof :depth-exhausted gs)
             (return-from solve nil))
           (if (null gs)
               (push subst results)
               (let* ((goal (apply-subst (first gs) subst))
                      (rest (rest gs)))
                 (unless silent (%trace-proof :goal goal depth))
                 (cond
                   ((%primitive-goal-p goal)
                    (let ((ext (%eval-primitive goal subst *current-kb*)))
                      (cond ((eq ext :cut)
                             (solve rest subst depth)
                             (return-from prove-all (nreverse results)))
                            ((eq ext :fail) nil)
                            (t (dolist (s (or ext nil))
                                 (solve rest s depth))))))
                   (t
                    ;; facts
                    (dolist (fact (kb-candidates *current-kb* goal))
                      (let ((s2 (unify goal fact subst)))
                        (unless (unify-fail-p s2)
                          (unless silent (%trace-proof :fact fact))
                          (solve rest s2 depth))))
                    ;; rules
                    (dolist (rule (kb-rules-for-goal *current-kb* goal))
                      (let* ((ren (rename-variables
                                   (cons (rule-head rule)
                                         (rule-body rule))))
                             (rhead (car ren))
                             (rbody (cdr ren))
                             (s2 (unify goal rhead subst)))
                        (unless (unify-fail-p s2)
                          (unless silent
                            (%trace-proof :rule (rule-name rule) goal))
                          (solve (append rbody rest) s2 (1- depth)))))))))))
      (solve goals subst depth-left)
      (nreverse results))))

(defun prove (goal &key (kb *current-kb*) (subst nil))
  "Prove a single goal. Returns (values success-p first-subst all-substs)."
  (let* ((*proof-trace* nil)
         (goal (if (and (consp goal) (eq (car goal) 'and))
                   (cdr goal)
                   (list goal)))
         (subs (prove-all goal (or subst +no-bindings+) :kb kb)))
    (values (not (null subs))
            (first subs)
            subs
            (reverse *proof-trace*))))

(defun prove-query (pattern &key (kb *current-kb*))
  "Return list of ground instantiations of PATTERN."
  (multiple-value-bind (ok sub all)
      (prove pattern :kb kb)
    (declare (ignore ok sub))
    (mapcar (lambda (s) (apply-subst pattern s)) all)))
