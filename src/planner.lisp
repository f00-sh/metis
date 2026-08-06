;;;; planner.lisp — STRIPS planner (BFS state-space search)
(in-package :metis)

(defstruct (operator (:conc-name op-))
  name
  params
  preconds
  add-list
  del-list
  (cost 1)
  (meta nil))

(defstruct (planner-domain (:conc-name pd-))
  (operators (make-hash-table :test #'eq))
  (lock (bt:make-lock "metis-planner")))

(defun make-empty-domain ()
  (make-planner-domain))

(defun pd-define-operator (domain name &key params preconds add del cost meta)
  (let ((op (make-operator
             :name name
             :params params
             :preconds (ensure-list preconds)
             :add-list (ensure-list add)
             :del-list (ensure-list del)
             :cost (or cost 1)
             :meta meta)))
    (setf (gethash name (pd-operators domain)) op)
    op))

(defun pd-operators-list (domain)
  (hash-table-values (pd-operators domain)))

(defun state-from-facts (facts)
  (let ((s (make-hash-table :test #'equal)))
    (dolist (f facts) (setf (gethash f s) t))
    s))

(defun state-copy (state)
  (let ((s (make-hash-table :test #'equal)))
    (maphash (lambda (k v) (setf (gethash k s) v)) state)
    s))

(defun state-holds (state lit)
  (gethash lit state))

(defun state-list (state)
  (hash-table-keys state))

(defun state-hash (state)
  (sxhash
   (prin1-to-string
    (sort (mapcar #'prin1-to-string (state-list state)) #'string<))))

(defun goals-satisfied (state goals)
  (every (lambda (g) (state-holds state g)) goals))

(defun ground-op (op subst)
  (list :name (op-name op)
        :params (mapcar (lambda (p) (apply-subst p subst)) (op-params op))
        :preconds (mapcar (lambda (p) (apply-subst p subst)) (op-preconds op))
        :add (mapcar (lambda (p) (apply-subst p subst)) (op-add-list op))
        :del (mapcar (lambda (p) (apply-subst p subst)) (op-del-list op))
        :cost (op-cost op)))

(defun applicable-p (state grounded)
  (every (lambda (p) (state-holds state p)) (getf grounded :preconds)))

(defun apply-op (state grounded)
  (let ((s (state-copy state)))
    (dolist (d (getf grounded :del))
      (remhash d s))
    (dolist (a (getf grounded :add))
      (setf (gethash a s) t))
    s))

(defun %objects-from-state (state goals)
  (let ((objs (make-hash-table :test #'equal)))
    (labels ((walk (x)
               (cond ((null x) nil)
                     ((and (symbolp x)
                           (not (variablep x))
                           (not (keywordp x))
                           (not (member x '(and or not true fail))))
                      (setf (gethash x objs) t))
                     ((consp x)
                      (walk (car x))
                      (walk (cdr x)))
                     (t nil))))
      (dolist (f (state-list state)) (walk f))
      (dolist (g goals) (walk g)))
    (hash-table-keys objs)))

(defun %groundings (op objects)
  (let ((params (op-params op)))
    (if (null params)
        (list nil)
        (labels ((prod (ps)
                   (if (null ps)
                       (list nil)
                       (loop for o in objects
                             nconc (mapcar (lambda (rest)
                                             (acons (car ps) o rest))
                                           (prod (cdr ps)))))))
          (prod params)))))

(defun expand-successors (domain state objects)
  (let ((out nil))
    (dolist (op (pd-operators-list domain))
      (dolist (subst (%groundings op objects))
        (let ((g (ground-op op subst)))
          (when (and (every #'groundp (getf g :preconds))
                     (applicable-p state g))
            (push (cons g (apply-op state g)) out)))))
    out))

(defstruct (plan-node (:conc-name pn-))
  state
  path
  depth
  cost)

(defun plan-search (domain initial-facts goals
                    &key (max-depth nil) (max-nodes nil))
  "BFS STRIPS search.
   Returns (values plan-steps final-state nodes-expanded)."
  (let* ((max-depth (or max-depth (get-config :max-plan-depth 24)))
         (max-nodes (or max-nodes (get-config :max-plan-nodes 5000)))
         (start (state-from-facts initial-facts))
         (goals (ensure-list goals))
         (objects (%objects-from-state start goals))
         (visited (make-hash-table :test #'eql))
         (nodes 0)
         (frontier (make-array 64 :adjustable t :fill-pointer 0)))
    (when (goals-satisfied start goals)
      (return-from plan-search (values nil start 0)))
    (vector-push-extend
     (make-plan-node :state start :path nil :depth 0 :cost 0)
     frontier)
    (setf (gethash (state-hash start) visited) t)
    (loop for head = 0 then (1+ head)
          while (< head (fill-pointer frontier))
          do
             (let ((node (aref frontier head)))
               (incf nodes)
               (when (> nodes max-nodes)
                 (return-from plan-search (values nil nil nodes)))
               (when (<= (pn-depth node) max-depth)
                 (dolist (pair (expand-successors domain
                                                  (pn-state node)
                                                  objects))
                   (destructuring-bind (gop . new-state) pair
                     (let ((h (state-hash new-state)))
                       (unless (gethash h visited)
                         (setf (gethash h visited) t)
                         (let ((n2 (make-plan-node
                                    :state new-state
                                    :path (cons gop (pn-path node))
                                    :depth (1+ (pn-depth node))
                                    :cost (+ (pn-cost node)
                                             (or (getf gop :cost) 1)))))
                           (when (goals-satisfied new-state goals)
                             (return-from plan-search
                               (values (reverse (pn-path n2))
                                       new-state
                                       nodes)))
                           (vector-push-extend n2 frontier)))))))))
    (values nil nil nodes)))

(defun plan-to-sexps (plan-steps)
  (mapcar (lambda (g)
            (list* (getf g :name) (getf g :params)))
          plan-steps))

(defun execute-grounded-plan (kb plan-steps &key (assert-effects t))
  (let ((log nil))
    (dolist (step plan-steps)
      (dolist (d (getf step :del))
        (when (kb-retract kb d)
          (push (list :del d) log)))
      (dolist (a (getf step :add))
        (when assert-effects
          (kb-assert kb a :support :action)
          (push (list :add a) log)))
      (push (list :did (getf step :name) (getf step :params)) log))
    (nreverse log)))
