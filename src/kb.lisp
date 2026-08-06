;;;; kb.lisp — assertional knowledge base with predicate indexing
(in-package :metis)

(defstruct (knowledge-base (:conc-name kb-))
  (facts (make-hash-table :test #'equal))   ; fact-key -> fact meta
  (by-pred (make-hash-table :test #'equal)) ; pred -> list of facts
  (rules nil)                               ; list of rule structs
  (rules-by-head (make-hash-table :test #'equal))
  (generation 0)
  (lock (bt:make-lock "metis-kb")))

(defstruct (fact-meta (:conc-name fm-))
  form
  (support :asserted)   ; :asserted | :derived | :perceived
  (time 0)
  (id 0)
  (activation 1.0))

(defstruct (rule (:conc-name rule-))
  id
  name
  head
  body          ; list of literals
  (priority 0)
  (source :asserted)
  (times-fired 0)
  (created 0)
  meta)         ; free-form plist

(defun fact-predicate (fact)
  (cond ((and (consp fact) (symbolp (car fact))) (car fact))
        ((symbolp fact) fact)
        (t :|complex|)))

(defun fact-key (fact)
  fact)

(defun make-empty-kb ()
  (make-knowledge-base))

(defun kb-count-facts (kb)
  (hash-table-count (kb-facts kb)))

(defun kb-all-facts (kb)
  (mapcar #'fm-form (hash-table-values (kb-facts kb))))

(defun kb-all-rules (kb)
  (copy-list (kb-rules kb)))

(defun %index-fact (kb fact)
  (let ((pred (fact-predicate fact)))
    (push fact (gethash pred (kb-by-pred kb)))))

(defun %unindex-fact (kb fact)
  (let ((pred (fact-predicate fact)))
    (setf (gethash pred (kb-by-pred kb))
          (remove fact (gethash pred (kb-by-pred kb)) :test #'equal))))

(defun kb-assert (kb fact &key (support :asserted) (activation 1.0))
  "Assert FACT. Returns (values fact-meta new-p)."
  (bt:with-lock-held ((kb-lock kb))
    (let* ((key (fact-key fact))
           (existing (gethash key (kb-facts kb))))
      (if existing
          (progn
            (setf (fm-activation existing)
                  (min 10.0 (+ (fm-activation existing) 0.25)))
            (setf (fm-time existing) (now-universal))
            (values existing nil))
          (let ((meta (make-fact-meta
                       :form fact
                       :support support
                       :time (now-universal)
                       :id (incf (kb-generation kb))
                       :activation activation)))
            (setf (gethash key (kb-facts kb)) meta)
            (%index-fact kb fact)
            (values meta t))))))

(defun kb-retract (kb fact)
  (bt:with-lock-held ((kb-lock kb))
    (let ((key (fact-key fact)))
      (when (gethash key (kb-facts kb))
        (remhash key (kb-facts kb))
        (%unindex-fact kb fact)
        t))))

(defun kb-holds-p (kb fact)
  (gethash (fact-key fact) (kb-facts kb)))

(defun kb-candidates (kb pattern)
  "Facts that might unify with PATTERN, via predicate index."
  (let ((pred (fact-predicate pattern)))
    (if (or (variablep pred) (eq pred :|complex|))
        (kb-all-facts kb)
        (copy-list (gethash pred (kb-by-pred kb))))))

(defun kb-add-rule (kb head body &key name (priority 0) (source :asserted) meta)
  (bt:with-lock-held ((kb-lock kb))
    (let* ((id (incf (kb-generation kb)))
           (rule (make-rule
                  :id id
                  :name (or name (intern (format nil "RULE-~D" id) :metis))
                  :head head
                  :body (ensure-list body)
                  :priority priority
                  :source source
                  :created (now-universal)
                  :meta meta))
           (pred (fact-predicate head)))
      (push rule (kb-rules kb))
      (push rule (gethash pred (kb-rules-by-head kb)))
      ;; keep rules sorted by priority desc
      (setf (kb-rules kb)
            (sort (kb-rules kb) #'> :key #'rule-priority))
      rule)))

(defun kb-remove-rule (kb rule-or-name)
  (bt:with-lock-held ((kb-lock kb))
    (let ((rule (if (rule-p rule-or-name)
                    rule-or-name
                    (find rule-or-name (kb-rules kb)
                          :key #'rule-name :test #'equal))))
      (when rule
        (setf (kb-rules kb) (remove rule (kb-rules kb)))
        (let ((pred (fact-predicate (rule-head rule))))
          (setf (gethash pred (kb-rules-by-head kb))
                (remove rule (gethash pred (kb-rules-by-head kb)))))
        t))))

(defun kb-rules-for-goal (kb goal)
  (let ((pred (fact-predicate goal)))
    (if (variablep pred)
        (kb-all-rules kb)
        (copy-list (gethash pred (kb-rules-by-head kb))))))

(defun kb-clear (kb)
  (bt:with-lock-held ((kb-lock kb))
    (clrhash (kb-facts kb))
    (clrhash (kb-by-pred kb))
    (clrhash (kb-rules-by-head kb))
    (setf (kb-rules kb) nil)
    (setf (kb-generation kb) 0)
    kb))

(defun kb-snapshot (kb)
  (bt:with-lock-held ((kb-lock kb))
    (list :facts (kb-all-facts kb)
          :rules (mapcar (lambda (r)
                           (list :name (rule-name r)
                                 :head (rule-head r)
                                 :body (rule-body r)
                                 :priority (rule-priority r)
                                 :source (rule-source r)
                                 :meta (rule-meta r)))
                         (kb-rules kb)))))

(defun kb-restore (kb snapshot)
  (kb-clear kb)
  (dolist (f (getf snapshot :facts))
    (kb-assert kb f :support :asserted))
  (dolist (r (getf snapshot :rules))
    (kb-add-rule kb
                 (getf r :head)
                 (getf r :body)
                 :name (getf r :name)
                 :priority (or (getf r :priority) 0)
                 :source (or (getf r :source) :restored)
                 :meta (getf r :meta)))
  kb)
