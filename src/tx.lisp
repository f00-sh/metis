;;;; tx.lisp — transactional assert/retract with rollback
(in-package :metis)

(defstruct (tx (:conc-name tx-))
  mind
  (log nil)       ; reverse list of undo records
  (open t)
  (id 0))

(defvar *tx-counter* 0)

(defun tx-begin (mind)
  (make-tx :mind (ensure-mind mind) :id (incf *tx-counter*)))

(defun tx-log-undo (tx undo-fn)
  (push undo-fn (tx-log tx)))

(defun tx-assert (tx fact &key (support :asserted))
  (unless (tx-open tx)
    (error 'metis-error :message "transaction closed"))
  (let* ((m (tx-mind tx))
         (had (kb-holds-p (mind-kb m) fact)))
    (assert-fact m fact :support support)
    (tms-assert (mind-tms m) fact :informant :tx)
    (belief-boost (mind-beliefs m) fact 0.2)
    (tx-log-undo tx
                 (if had
                     (lambda () nil)
                     (lambda ()
                       (retract-fact m fact)
                       (tms-retract-assumption (mind-tms m) fact))))
    fact))

(defun tx-retract (tx fact)
  (unless (tx-open tx)
    (error 'metis-error :message "transaction closed"))
  (let* ((m (tx-mind tx))
         (had (kb-holds-p (mind-kb m) fact)))
    (when had
      (retract-fact m fact)
      (tms-retract-assumption (mind-tms m) fact)
      (tx-log-undo tx
                   (lambda ()
                     (assert-fact m fact :support :tx-rollback)
                     (tms-assert (mind-tms m) fact :informant :tx-rollback))))
    had))

(defun tx-commit (tx)
  (setf (tx-open tx) nil
        (tx-log tx) nil)
  (metis-log :debug "tx ~D commit" (tx-id tx))
  :committed)

(defun tx-rollback (tx)
  (when (tx-open tx)
    (dolist (undo (tx-log tx))
      (ignore-errors (funcall undo)))
    (setf (tx-open tx) nil
          (tx-log tx) nil)
    (metis-log :warn "tx ~D rollback" (tx-id tx)))
  :rolled-back)

(defmacro with-mind-transaction ((tx-var mind) &body body)
  `(let ((,tx-var (tx-begin ,mind)))
     (unwind-protect
          (multiple-value-prog1 (progn ,@body)
            (when (tx-open ,tx-var)
              (tx-commit ,tx-var)))
       (when (tx-open ,tx-var)
         (tx-rollback ,tx-var)))))
