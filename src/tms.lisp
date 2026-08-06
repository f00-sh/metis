;;;; tms.lisp — justification-based truth maintenance (JTMS-lite)
(in-package :metis)

(defstruct (tms-node (:conc-name tn-))
  fact
  (label :out)              ; :in | :out
  (justifications nil)      ; list of just-ids that support this
  (consequences nil)        ; just-ids that depend on this
  (belief 1.0)              ; soft weight when :in
  (meta nil))

(defstruct (tms-just (:conc-name tj-))
  id
  informant               ; :asserted | rule-name | :plan | :percept
  conclusion              ; fact
  (supporters nil)        ; facts that must be :in
  (assumptions nil)
  (valid nil))

(defstruct (tms (:conc-name tms-))
  (nodes (make-hash-table :test #'equal))
  (justs (make-hash-table :test #'eql))
  (next-id 0)
  (lock (bt:make-lock "metis-tms")))

(defun make-empty-tms ()
  (make-tms))

(defun tms-get-node (tms fact)
  (or (gethash fact (tms-nodes tms))
      (setf (gethash fact (tms-nodes tms))
            (make-tms-node :fact fact :label :out))))

(defun tms-in-p (tms fact)
  (let ((n (gethash fact (tms-nodes tms))))
    (and n (eq (tn-label n) :in))))

(defun tms-justify (tms conclusion supporters &key (informant :asserted)
                                               (assumptions nil)
                                               (belief 1.0))
  "Add a justification. If all supporters :in, mark conclusion :in."
  (bt:with-lock-held ((tms-lock tms))
    (let* ((id (incf (tms-next-id tms)))
           (just (make-tms-just
                  :id id
                  :informant informant
                  :conclusion conclusion
                  :supporters (ensure-list supporters)
                  :assumptions (ensure-list assumptions)))
           (node (tms-get-node tms conclusion)))
      (setf (gethash id (tms-justs tms)) just)
      (push id (tn-justifications node))
      (setf (tn-belief node) belief)
      (dolist (s (tj-supporters just))
        (push id (tn-consequences (tms-get-node tms s))))
      (tms-update-just tms just)
      (values just node))))

(defun tms-supporters-in-p (tms just)
  (every (lambda (f) (tms-in-p tms f)) (tj-supporters just)))

(defun tms-update-just (tms just)
  (let ((ok (or (null (tj-supporters just))
                (tms-supporters-in-p tms just))))
    (setf (tj-valid just) ok)
    (when ok
      (tms-enable-node tms (tj-conclusion just) just))
    ok))

(defun tms-enable-node (tms fact just)
  (let ((node (tms-get-node tms fact)))
    (unless (eq (tn-label node) :in)
      (setf (tn-label node) :in)
      (metis-log :debug "TMS IN ~S via ~A" fact (tj-informant just))
      ;; propagate
      (dolist (jid (tn-consequences node))
        (let ((j (gethash jid (tms-justs tms))))
          (when j (tms-update-just tms j)))))
    node))

(defun tms-retract-assumption (tms fact)
  "Mark fact OUT: invalidate its own justifications and dependents (JTMS retract)."
  (bt:with-lock-held ((tms-lock tms))
    (let ((node (tms-get-node tms fact)))
      (setf (tn-label node) :out)
      ;; invalidate justifications *of* this node (assumption dropped)
      (dolist (jid (copy-list (tn-justifications node)))
        (let ((j (gethash jid (tms-justs tms))))
          (when j (setf (tj-valid j) nil))))
      ;; invalidate justifications that used this as supporter
      (dolist (jid (copy-list (tn-consequences node)))
        (let ((j (gethash jid (tms-justs tms))))
          (when j
            (setf (tj-valid j) nil)
            (tms-reconsider-conclusion tms (tj-conclusion j)))))
      ;; do not auto-reinstate from invalidated self-justs
      node)))

(defun tms-reconsider-conclusion (tms fact)
  (let* ((node (tms-get-node tms fact))
         (valid (remove-if-not
                 (lambda (jid)
                   (let ((j (gethash jid (tms-justs tms))))
                     (and j (or (tj-valid j)
                                (tms-update-just tms j)))))
                 (tn-justifications node))))
    (if valid
        (setf (tn-label node) :in)
        (when (eq (tn-label node) :in)
          (setf (tn-label node) :out)
          (metis-log :debug "TMS OUT ~S" fact)
          (dolist (jid (tn-consequences node))
            (let ((j (gethash jid (tms-justs tms))))
              (when j
                (setf (tj-valid j) nil)
                (tms-reconsider-conclusion tms (tj-conclusion j)))))))
    node))

(defun tms-assert (tms fact &key (informant :asserted) (belief 1.0))
  (tms-justify tms fact nil :informant informant :belief belief)
  (tms-enable-node tms fact
                   (make-tms-just :id 0 :informant informant
                                  :conclusion fact :valid t)))

(defun tms-why (tms fact)
  "Return supporting justifications for FACT if IN."
  (let ((node (gethash fact (tms-nodes tms))))
    (when (and node (eq (tn-label node) :in))
      (loop for jid in (tn-justifications node)
            for j = (gethash jid (tms-justs tms))
            when (and j (tj-valid j))
            collect (list :id (tj-id j)
                          :informant (tj-informant j)
                          :supporters (tj-supporters j)
                          :assumptions (tj-assumptions j))))))

(defun tms-in-facts (tms)
  (loop for n being the hash-values of (tms-nodes tms)
        when (eq (tn-label n) :in)
        collect (tn-fact n)))

(defun tms-snapshot (tms)
  (list :nodes
        (loop for n being the hash-values of (tms-nodes tms)
              collect (list :fact (tn-fact n)
                            :label (tn-label n)
                            :belief (tn-belief n)))
        :justs
        (loop for j being the hash-values of (tms-justs tms)
              collect (list :id (tj-id j)
                            :informant (tj-informant j)
                            :conclusion (tj-conclusion j)
                            :supporters (tj-supporters j)
                            :valid (tj-valid j)))))
