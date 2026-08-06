;;;; constraint.lisp — finite-domain CSP solver (backtracking + forward check)
(in-package :metis)

(defstruct (csp (:conc-name csp-))
  variables       ; list of var names
  domains         ; alist var -> list of values
  constraints)    ; list of (vars predicate-fn) or (vars :all-diff) etc.

(defun csp-all-diff (&rest vars)
  (list vars
        (lambda (assignment)
          (let ((vals (mapcar (lambda (v) (cdr (assoc v assignment))) vars)))
            (and (notany #'null vals)
                 (= (length vals) (length (remove-duplicates vals :test #'equal))))))))

(defun csp-predicate (vars fn)
  (list vars fn))

(defun %csp-consistent (constraints assignment)
  (every (lambda (c)
           (destructuring-bind (vars pred) c
             (if (every (lambda (v) (assoc v assignment)) vars)
                 (funcall pred assignment)
                 t))) ; not yet fully bound
         constraints))

(defun %csp-select-var (vars assignment domains)
  (find-if (lambda (v) (not (assoc v assignment))) vars))

(defun csp-solve (csp &key (max-nodes 10000))
  "Return first solution assignment alist or NIL."
  (let ((nodes 0))
    (labels
        ((bt (assignment)
           (when (> (incf nodes) max-nodes)
             (return-from csp-solve nil))
           (let ((var (%csp-select-var (csp-variables csp) assignment
                                       (csp-domains csp))))
             (if (null var)
                 assignment
                 (dolist (val (cdr (assoc var (csp-domains csp))) nil)
                   (let ((a2 (acons var val assignment)))
                     (when (%csp-consistent (csp-constraints csp) a2)
                       (let ((sol (bt a2)))
                         (when sol (return-from bt sol))))))))))
      (values (bt nil) nodes))))

(defun csp-solve-all (csp &key (max-solutions 20) (max-nodes 50000))
  (let ((nodes 0)
        (solutions nil))
    (labels
        ((bt (assignment)
           (when (or (> (incf nodes) max-nodes)
                     (>= (length solutions) max-solutions))
             (return-from csp-solve-all (values (nreverse solutions) nodes)))
           (let ((var (%csp-select-var (csp-variables csp) assignment
                                       (csp-domains csp))))
             (if (null var)
                 (push assignment solutions)
                 (dolist (val (cdr (assoc var (csp-domains csp))))
                   (let ((a2 (acons var val assignment)))
                     (when (%csp-consistent (csp-constraints csp) a2)
                       (bt a2))))))))
      (bt nil)
      (values (nreverse solutions) nodes))))
