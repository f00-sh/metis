;;;; log.lisp — structured production logging
(in-package :metis)

(defparameter *log-stream* *error-output*)
(defparameter *log-level* :info)
(defparameter *log-lock* (bt:make-lock "metis-log"))
(defparameter *log-buffer* nil) ; ring of recent entries for API/introspect
(defparameter *log-buffer-size* 500)

(defparameter *log-levels*
  '((:trace . 0) (:debug . 1) (:info . 2) (:warn . 3) (:error . 4) (:fatal . 5)))

(defun log-level>= (a b)
  (>= (or (cdr (assoc a *log-levels*)) 2)
      (or (cdr (assoc b *log-levels*)) 2)))

(defun log-set-level (level)
  (setf *log-level* level)
  (set-config :log-level level)
  level)

(defun %log-push (entry)
  (push entry *log-buffer*)
  (when (> (length *log-buffer*) *log-buffer-size*)
    (setf *log-buffer* (subseq *log-buffer* 0 *log-buffer-size*))))

(defun metis-log (level format-string &rest args)
  (when (log-level>= level *log-level*)
    (bt:with-lock-held (*log-lock*)
      (let* ((msg (apply #'format nil format-string args))
             (entry (list :time (now-iso) :level level :msg msg)))
        (%log-push entry)
        (when (get-config :log-to-stream t)
          (format *log-stream* "~&[~A] ~A ~A~%"
                  (getf entry :time) level msg)
          (force-output *log-stream*))
        entry))))

(defmacro with-logged-errors ((context) &body body)
  `(handler-case (progn ,@body)
     (error (e)
       (metis-log :error "~A: ~A" ,context e)
       (error e))))

(defun recent-logs (&optional (n 50) &key level)
  (let ((xs *log-buffer*))
    (when level
      (setf xs (remove-if-not (lambda (e) (eq (getf e :level) level)) xs)))
    (subseq xs 0 (min n (length xs)))))
