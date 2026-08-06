;;;; unifier.lisp — Robinson unification with occurs-check
;;;; Empty substitution must NOT be NIL (NIL means failure).
(in-package :metis)

(defparameter +fail+ nil
  "Unification failure marker.")

(defparameter +no-bindings+ '((t . t))
  "Successful unification with no variable bindings (PAIP-style).")

(defun unify-fail-p (subst)
  (eq subst +fail+))

(defun lookup-binding (var subst)
  (unless (or (null subst) (eq subst +no-bindings+))
    (let ((pair (assoc var subst :test #'eq)))
      (when (and pair (not (eq (car pair) t)))
        (cdr pair)))))

(defun bind-var (var val subst)
  (cons (cons var val)
        (if (eq subst +no-bindings+) nil subst)))

(defun deref (x subst)
  "Follow variable bindings."
  (if (and (variablep x) (not (anonymous-var-p x)))
      (let ((b (lookup-binding x subst)))
        (if b (deref b subst) x))
      x))

(defun occurs-check (var x subst)
  "T if VAR occurs in X under SUBST."
  (let ((x (deref x subst)))
    (cond ((eq var x) t)
          ((consp x)
           (or (occurs-check var (car x) subst)
               (occurs-check var (cdr x) subst)))
          (t nil))))

(defun unify (x y &optional (subst +no-bindings+))
  "Unify X and Y. Return substitution or +fail+ (NIL).
   Empty success is +no-bindings+, never bare NIL confusion for equals."
  (cond ((unify-fail-p subst) +fail+)
        (t
         (let ((x (deref x subst))
               (y (deref y subst)))
           (cond ((equal x y) subst)
                 ((anonymous-var-p x) subst)
                 ((anonymous-var-p y) subst)
                 ((variablep x)
                  (if (occurs-check x y subst)
                      +fail+
                      (bind-var x y subst)))
                 ((variablep y)
                  (if (occurs-check y x subst)
                      +fail+
                      (bind-var y x subst)))
                 ((and (consp x) (consp y))
                  (unify (cdr x) (cdr y)
                         (unify (car x) (car y) subst)))
                 (t +fail+))))))

(defun apply-subst (tree subst)
  "Instantiate TREE under SUBST."
  (cond ((or (null subst) (eq subst +no-bindings+)) tree)
        ((and (variablep tree) (not (anonymous-var-p tree)))
         (let ((v (deref tree subst)))
           (if (eq v tree) tree (apply-subst v subst))))
        ((consp tree)
         (cons (apply-subst (car tree) subst)
               (apply-subst (cdr tree) subst)))
        (t tree)))

(defvar *var-counter* 0)

(defun fresh-var (&optional (base '?V))
  (intern (format nil "~A~D" base (incf *var-counter*)) :metis))

(defun rename-variables (tree &optional (map (make-hash-table :test #'eq)))
  "Alpha-rename all logic variables in TREE to fresh ones."
  (labels ((ren (x)
             (cond ((anonymous-var-p x) (fresh-var '?))
                   ((variablep x)
                    (or (gethash x map)
                        (setf (gethash x map) (fresh-var x))))
                   ((consp x) (cons (ren (car x)) (ren (cdr x))))
                   (t x))))
    (ren tree)))

(defun compose-subst (s1 s2)
  "Apply S1 then S2 (s2 outer)."
  (cond ((unify-fail-p s1) +fail+)
        ((unify-fail-p s2) +fail+)
        ((eq s1 +no-bindings+) s2)
        ((eq s2 +no-bindings+) s1)
        (t
         (append
          (mapcar (lambda (pair)
                    (cons (car pair) (apply-subst (cdr pair) s2)))
                  (remove t s1 :key #'car))
          s2))))

(defun subst-bound-vars (subst)
  (if (or (null subst) (eq subst +no-bindings+))
      nil
      (mapcar #'car (remove t subst :key #'car))))

(defun pretty-subst (subst)
  (if (or (null subst) (eq subst +no-bindings+))
      nil
      (mapcar (lambda (p) (list (car p) '-> (cdr p)))
              (remove t subst :key #'car))))

(defun %bindings-key (subst)
  (prin1-to-string
   (sort (copy-list (pretty-subst subst)) #'string<
         :key (lambda (p) (prin1-to-string p)))))
