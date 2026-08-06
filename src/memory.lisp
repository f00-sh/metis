;;;; memory.lisp — working, episodic, procedural memory
(in-package :metis)

;;; ---------- Working memory (activation + capacity) ----------

(defstruct (wm-chunk (:conc-name wm-))
  content
  (activation 1.0)
  (created 0)
  (touched 0)
  (source :internal)
  (meta nil))

(defstruct (working-memory (:conc-name wmem-))
  (chunks nil)
  (capacity 64)
  (lock (bt:make-lock "metis-wm")))

(defun make-empty-wm (&optional capacity)
  (make-working-memory
   :capacity (or capacity (get-config :working-memory-capacity 64))))

(defun wm-decay (wmem)
  (let ((d (get-config :activation-decay 0.05)))
    (dolist (c (wmem-chunks wmem))
      (setf (wm-activation c) (* (wm-activation c) (- 1.0 d))))
    (setf (wmem-chunks wmem)
          (remove-if (lambda (c) (< (wm-activation c) 0.05))
                     (wmem-chunks wmem)))))

(defun wm-cull (wmem)
  (setf (wmem-chunks wmem)
        (subseq (sort (copy-list (wmem-chunks wmem))
                      #'> :key #'wm-activation)
                0 (min (length (wmem-chunks wmem))
                       (wmem-capacity wmem)))))

(defun wm-add (wmem content &key (source :internal) (activation 1.0) meta)
  (bt:with-lock-held ((wmem-lock wmem))
    (wm-decay wmem)
    (let ((existing (find content (wmem-chunks wmem)
                          :key #'wm-content :test #'equal)))
      (if existing
          (progn
            (setf (wm-activation existing)
                  (min 10.0 (+ (wm-activation existing) activation)))
            (setf (wm-touched existing) (now-universal))
            existing)
          (let ((c (make-wm-chunk :content content
                                  :activation activation
                                  :created (now-universal)
                                  :touched (now-universal)
                                  :source source
                                  :meta meta)))
            (push c (wmem-chunks wmem))
            (wm-cull wmem)
            c)))))

(defun wm-contents (wmem)
  (mapcar #'wm-content
          (sort (copy-list (wmem-chunks wmem)) #'> :key #'wm-activation)))

(defun wm-find (wmem pattern)
  (loop for c in (wmem-chunks wmem)
        for s = (unify pattern (wm-content c))
        unless (unify-fail-p s)
        collect (list :content (wm-content c)
                      :subst s
                      :activation (wm-activation c))))

;;; ---------- Episodic memory ----------

(defstruct (episode (:conc-name ep-))
  id
  (time 0)
  situation    ; what was true / perceived
  goals
  action
  outcome
  (valence 0.0) ; -1..1
  (tags nil)
  (meta nil))

(defstruct (episodic-memory (:conc-name emem-))
  (episodes nil)
  (next-id 0)
  (lock (bt:make-lock "metis-em")))

(defun make-empty-em ()
  (make-episodic-memory))

(defun em-remember (emem &key situation goals action outcome
                           (valence 0.0) tags meta)
  (bt:with-lock-held ((emem-lock emem))
    (let ((e (make-episode
              :id (incf (emem-next-id emem))
              :time (now-universal)
              :situation situation
              :goals goals
              :action action
              :outcome outcome
              :valence valence
              :tags (ensure-list tags)
              :meta meta)))
      (push e (emem-episodes emem))
      e)))

(defun em-recall (emem &key pattern tag since limit (min-valence nil))
  (let ((eps (emem-episodes emem)))
    (when tag
      (setf eps (remove-if-not (lambda (e) (member tag (ep-tags e))) eps)))
    (when since
      (setf eps (remove-if-not (lambda (e) (>= (ep-time e) since)) eps)))
    (when min-valence
      (setf eps (remove-if-not (lambda (e) (>= (ep-valence e) min-valence))
                               eps)))
    (when pattern
      (setf eps
            (remove-if-not
             (lambda (e)
               (or (not (unify-fail-p (unify pattern (ep-situation e))))
                   (not (unify-fail-p (unify pattern (ep-action e))))
                   (not (unify-fail-p (unify pattern (ep-outcome e))))))
             eps)))
    (when limit
      (setf eps (subseq eps 0 (min limit (length eps)))))
    eps))

;;; ---------- Procedural memory (skills as code-as-data) ----------

(defstruct (skill (:conc-name skill-))
  name
  params
  preconds          ; symbolic preconditions
  body              ; list of forms (code as data) OR plan template
  (kind :procedure) ; :procedure | :plan-template | :inference
  (source :asserted)
  (utility 0.0)
  (uses 0)
  (successes 0)
  (created 0)
  (code nil)        ; compiled function when available
  meta)

(defstruct (procedural-memory (:conc-name pmem-))
  (skills (make-hash-table :test #'eq))
  (lock (bt:make-lock "metis-pm")))

(defun make-empty-pm ()
  (make-procedural-memory))

(defun pm-install (pmem skill)
  (bt:with-lock-held ((pmem-lock pmem))
    (setf (skill-created skill) (or (skill-created skill) (now-universal)))
    ;; compile body if it's lisp forms
    (when (and (eq (skill-kind skill) :procedure)
               (skill-body skill)
               (not (skill-code skill)))
      (handler-case
          (setf (skill-code skill)
                (compile nil
                         `(lambda (,@ (skill-params skill))
                            ,@(skill-body skill))))
        (error (e)
          (setf (skill-meta skill)
                (alist-set :compile-error (princ-to-string e)
                           (skill-meta skill))))))
    (setf (gethash (skill-name skill) (pmem-skills pmem)) skill)
    skill))

(defun pm-get (pmem name)
  (gethash name (pmem-skills pmem)))

(defun pm-all (pmem)
  (hash-table-values (pmem-skills pmem)))

(defun pm-find (pmem &key pattern precond-subset kind)
  (remove-if-not
   (lambda (sk)
     (and (or (null kind) (eq (skill-kind sk) kind))
          (or (null pattern)
              (search (string pattern) (string (skill-name sk))
                      :test #'char-equal))
          (or (null precond-subset)
              (subsetp precond-subset (skill-preconds sk) :test #'equal))))
   (pm-all pmem)))

(defun pm-record-outcome (pmem name success-p &optional utility-delta)
  (let ((sk (pm-get pmem name)))
    (when sk
      (incf (skill-uses sk))
      (when success-p (incf (skill-successes sk)))
      (when utility-delta
        (setf (skill-utility sk)
              (+ (skill-utility sk) utility-delta)))
      sk)))

(defun skill-success-rate (skill)
  (if (zerop (skill-uses skill))
      0.5
      (/ (skill-successes skill) (float (skill-uses skill)))))

(defun synthesize-skill-from-plan (name plan-steps goals preconds
                                   &key (params nil))
  "Compile a successful plan into a reusable skill (code as data)."
  (let* ((body
          `((let ((log nil))
              ,@(mapcar
                 (lambda (step)
                   `(push ',(list :do (getf step :name)
                                  (getf step :params)
                                  :add (getf step :add)
                                  :del (getf step :del))
                          log))
                 plan-steps)
              (values t (nreverse log) ',goals))))
         (sk (make-skill
              :name name
              :params params
              :preconds preconds
              :body body
              :kind :plan-template
              :source :compiled-from-plan
              :utility 1.0
              :meta (list :plan plan-steps :goals goals))))
    sk))
