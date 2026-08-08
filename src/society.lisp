;;;; society.lisp — multi-mind society with roles and message bus
(in-package :metis)

(defstruct (society (:conc-name soc-))
  (minds (make-hash-table :test #'equal)) ; name -> mind
  (blackboard (make-empty-blackboard))
  (lock (bt:make-lock "metis-society"))
  (running nil)
  (threads nil))

(defvar *society* nil)

(defun make-empty-society ()
  (make-society))

(defun society-boot (&key (reset nil))
  (when (or reset (null *society*))
    (setf *society* (make-empty-society)))
  *society*)

(defun society-register (society mind &key (name nil) (role :general))
  (let ((name (or name (mind-name mind) (format nil "mind-~A" (random 100000)))))
    (setf (mind-name mind) name
          (mind-role mind) role
          (mind-society mind) society
          (mind-blackboard mind) (soc-blackboard society))
    (bt:with-lock-held ((soc-lock society))
      (setf (gethash name (soc-minds society)) mind))
    (bb-post (soc-blackboard society) :message
             (list :joined name :role role)
             :author name :priority 1)
    mind))

(defun society-get (society name)
  (gethash name (soc-minds society)))

(defun society-minds (society)
  (hash-table-values (soc-minds society)))

(defun society-send (society from to content &key (priority 0))
  (let ((target (society-get society to)))
    (unless target
      (error 'metis-error :message (format nil "unknown mind ~A" to)))
    (bt:with-lock-held ((mind-lock target))
      (push (list :from from :content content :time (now-universal))
            (mind-inbox target)))
    (bb-post (soc-blackboard society) :message
             (list :from from :to to :content content)
             :author from :priority priority)
    t))

(defun society-broadcast (society from content &key (priority 0))
  (dolist (m (society-minds society))
    (unless (equal (mind-name m) from)
      (society-send society from (mind-name m) content :priority priority))))

(defun mind-drain-inbox (mind)
  (bt:with-lock-held ((mind-lock mind))
    (prog1 (nreverse (mind-inbox mind))
      (setf (mind-inbox mind) nil))))

(defun society-step (society)
  "One cooperative step: each mind drains inbox, perceives, one cognitive cycle if goals."
  (dolist (m (society-minds society))
    (let ((msgs (mind-drain-inbox m)))
      (dolist (msg msgs)
        (perceive m (list (list :message (getf msg :from) (getf msg :content))))
        (when (and (consp (getf msg :content))
                   (eq (car (getf msg :content)) :goal))
          (goal-push m (second (getf msg :content))))))
    (when (mind-goals m)
      (cognitive-cycle m)))
  (list :minds (mapcar #'mind-name (society-minds society))
        :bb (length (bb-entries (soc-blackboard society)))))

(defun society-run-cycles (society n)
  (loop repeat n collect (society-step society)))

(defun %mind-worker (society name)
  (lambda ()
    (loop while (soc-running society)
          do (let ((m (society-get society name)))
               (when m
                 (ignore-errors (society-step society)))
               (sleep 0.05)))))

(defun society-start-async (society)
  "Start background threads (one coordinator)."
  (setf (soc-running society) t)
  (let ((th (bt:make-thread
             (lambda ()
               (loop while (soc-running society)
                     do (ignore-errors (society-step society))
                        (sleep 0.1)))
             :name "metis-society")))
    (push th (soc-threads society))
    th))

(defun society-stop (society)
  (setf (soc-running society) nil)
  (dolist (th (soc-threads society))
    (when (bt:thread-alive-p th)
      (ignore-errors (bt:join-thread th))))
  (setf (soc-threads society) nil)
  t)

(defun make-specialist-mind (role &key (bootstrap nil))
  "Create a non-global mind with role-specific setup."
  (let ((m (make-fresh-mind)))
    (setf (mind-role m) role)
    (init-mind-subsystems m)
    (install-core-tools (mind-tools m) (lambda () m))
    (when bootstrap (load-bootstrap m))
    (case role
      (:planner
       (setf (mind-name m) "planner")
       (goal-push m '(role-ready planner)))
      (:reasoner
       (setf (mind-name m) "reasoner"))
      (:critic
       (setf (mind-name m) "critic"))
      (t
       (setf (mind-name m) (string-downcase (string role)))))
    (setf (mind-booted m) t)
    m))

(defun society-default-ensemble ()
  "Production multi-agent ensemble: reasoner + planner + critic + executor."
  (let ((soc (society-boot :reset t)))
    (society-register soc (make-specialist-mind :reasoner :bootstrap t)
                      :name "reasoner" :role :reasoner)
    (society-register soc (make-specialist-mind :planner :bootstrap t)
                      :name "planner" :role :planner)
    (society-register soc (make-specialist-mind :critic :bootstrap t)
                      :name "critic" :role :critic)
    (society-register soc (make-specialist-mind :executor :bootstrap t)
                      :name "executor" :role :executor)
    ;; wire primary *mind* as conductor if present
    (when *mind*
      (society-register soc *mind* :name "conductor" :role :conductor))
    soc))

;;; ------------------------------------------------------------------
;;; Multi-mind trust (product frontier)
;;; ------------------------------------------------------------------

(defparameter *society-trust-edges*
  (make-hash-table :test #'equal)
  "Directed trust edges as (from . to) → level. Survives actors not yet registered.")

(defun society-trust-clear! ()
  (clrhash *society-trust-edges*)
  t)

(defun society-trust! (society from to &key (level 1.0))
  "Establish directed trust FROM → TO.
   Edge always recorded in *society-trust-edges*; also asserts facts when minds exist."
  (setf (gethash (cons from to) *society-trust-edges*) level)
  (let ((fm (society-get society from))
        (tm (society-get society to)))
    (when fm
      (assert-fact fm (list 'trusts to level) :support :society-trust
                   :forward nil)
      (when (mind-tms fm)
        (tms-assert (mind-tms fm) (list 'trusts to level)
                    :informant :society-trust)))
    (when tm
      (assert-fact tm (list 'trusted-by from level) :support :society-trust
                   :forward nil)
      (when (mind-tms tm)
        (tms-assert (mind-tms tm) (list 'trusted-by from level)
                    :informant :society-trust)))
    (when (soc-blackboard society)
      (bb-post (soc-blackboard society) :message
               (list :trust from to :level level)
               :author (or from "trust") :priority 2))
    (list :trusted t :from from :to to :level level)))

(defun society-trust-p (society from to)
  "T if FROM trusts TO (edge table or mind KB/TMS)."
  (or (and (gethash (cons from to) *society-trust-edges*) t)
      (let ((fm (society-get society from)))
        (when fm
          (or (ask fm (list 'trusts to '?l))
              (and (mind-tms fm)
                   (tms-in-p (mind-tms fm) (list 'trusts to 1.0)))
              (some (lambda (f)
                      (and (consp f)
                           (eq (first f) 'trusts)
                           (equal (second f) to)))
                    (kb-all-facts (mind-kb fm))))))))

(defun society-trusted-send (society from to content &key (priority 0))
  "Send only if society-trust-p holds; otherwise error (exercisable trust gate)."
  (unless (society-trust-p society from to)
    (error 'metis-error
           :message (format nil "no trust edge ~A → ~A" from to)))
  (society-send society from to content :priority priority)
  (list :sent t :from from :to to :trusted t :content content))
