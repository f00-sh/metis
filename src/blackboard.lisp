;;;; blackboard.lisp — concurrent shared workspace for multi-agent collaboration
(in-package :metis)

(defstruct (bb-entry (:conc-name bbe-))
  id
  kind          ; :fact :goal :hypothesis :plan :message
  content
  author
  (priority 0)
  (time 0)
  (meta nil))

(defstruct (blackboard (:conc-name bb-))
  (entries nil)
  (next-id 0)
  (subscribers nil) ; list of (kind . function)
  (lock (bt:make-lock "metis-bb"))
  (cv (bt:make-condition-variable :name "metis-bb")))

(defun make-empty-blackboard ()
  (make-blackboard))

(defun bb-post (bb kind content &key author (priority 0) meta)
  (bt:with-lock-held ((bb-lock bb))
    (let ((e (make-bb-entry
              :id (incf (bb-next-id bb))
              :kind kind
              :content content
              :author author
              :priority priority
              :time (now-universal)
              :meta meta)))
      (push e (bb-entries bb))
      (setf (bb-entries bb)
            (sort (copy-list (bb-entries bb)) #'> :key #'bbe-priority))
      (dolist (sub (bb-subscribers bb))
        (when (or (eq (car sub) t) (eq (car sub) kind))
          (ignore-errors (funcall (cdr sub) e))))
      (bt:condition-notify (bb-cv bb))
      e)))

(defun bb-read (bb &key kind author since limit pattern)
  (bt:with-lock-held ((bb-lock bb))
    (let ((xs (bb-entries bb)))
      (when kind
        (setf xs (remove kind xs :key #'bbe-kind :test-not #'eq)))
      (when author
        (setf xs (remove author xs :key #'bbe-author :test-not #'equal)))
      (when since
        (setf xs (remove-if-not (lambda (e) (>= (bbe-time e) since)) xs)))
      (when pattern
        (setf xs (remove-if-not
                  (lambda (e)
                    (not (unify-fail-p (unify pattern (bbe-content e)))))
                  xs)))
      (when limit
        (setf xs (subseq xs 0 (min limit (length xs)))))
      xs)))

(defun bb-subscribe (bb kind fn)
  (bt:with-lock-held ((bb-lock bb))
    (push (cons kind fn) (bb-subscribers bb))))

(defun bb-snapshot (bb)
  (mapcar (lambda (e)
            (list :id (bbe-id e)
                  :kind (bbe-kind e)
                  :content (bbe-content e)
                  :author (bbe-author e)
                  :priority (bbe-priority e)))
          (bb-entries bb)))
