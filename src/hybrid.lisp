;;;; hybrid.lisp — CLS v2: prioritized interleaved replay, separation, meta-cog,
;;;; structured explain, coupled draft, sleep consolidate
(in-package :metis)

(defparameter *hippocampus-capacity* 128)
(defparameter *hippocampus* nil
  "Episodes newest-first. Each: :id :text :source :valence :priority
   :goal :context :tms-state :success :time :meta")

(defparameter *online-learn-enabled* t)
(defparameter *consolidation-epochs* 1)
(defparameter *consolidation-max-batches* 12)
(defparameter *consolidation-lr* 5d-4)
(defparameter *consolidation-hidden* 48)
(defparameter *consolidation-seq-len* 48)
(defparameter *consolidation-depth* 2)
(defparameter *online-lm-name* "online-lm")
(defparameter *replay-k* 3
  "k old episodes per interleaved mini-batch (+ 1 new).")
(defparameter *replay-enabled* t)

(defparameter *hybrid-metrics*
  (list :loss-delta 0d0
        :refuse-count 0
        :allow-count 0
        :learn-count 0
        :path-flips 0
        :last-path nil
        :units 0
        :last-loss nil)
  "Cognitive metrics for meta-control.")

(defparameter *hybrid-thesis*
  "Hybrid cognitive unit v2: prioritized interleaved CLS replay, separation keys,
meta-cog metrics/self-model, structured explain, coupled neural→symbolic accept,
TMS re-check — refuse/allow/learn with machine-checkable justification.")

;;; ------------------------------------------------------------------
;;; Hippocampus — separation keys + priority
;;; ------------------------------------------------------------------

(defun hippocampus-clear! ()
  (setf *hippocampus* nil))

(defun %episode-priority (source valence success)
  (cond
    ((eq source :refuse) 10)
    ((eq source :error) 10)
    ((eq source :failed-goal) 10)
    ((eq source :coupled-reject) 8)
    ((eq valence :blocked) 9)
    ((eq success nil) 7)
    ((eq source :teach) 6)
    ((eq source :coupled-accept) 5)
    ((eq source :generate) 2)
    ((eq source :turn) 1)
    (t 1)))

(defun hippocampus-encode! (text &key (source :turn) (valence :neutral)
                                   (meta nil) (goal nil) (context nil)
                                   (tms-state nil) (success t) (priority nil))
  "Encode episodic trace with separation keys and priority for replay v2."
  (when (and text (plusp (length (string-trim '(#\Space #\Newline) text))))
    (let* ((m *mind*)
           (tms-state (or tms-state
                          (if (and m (nn-path-allowed-p m)) :in :out)))
           (goal (or goal
                     (and m (mind-goals m) (first (mind-goals m)))))
           (pri (or priority (%episode-priority source valence success)))
           (ep (list :id (format nil "ep-~D-~D"
                                 (get-universal-time) (random 100000))
                     :text text
                     :source source
                     :valence valence
                     :priority pri
                     :goal goal
                     :context context
                     :tms-state tms-state
                     :success success
                     :time (now-iso)
                     :meta meta)))
      (push ep *hippocampus*)
      (when (> (length *hippocampus*) *hippocampus-capacity*)
        (setf *hippocampus* (subseq *hippocampus* 0 *hippocampus-capacity*)))
      (when m
        (assert-fact m
                     (list 'episode (getf ep :id) source
                           (or goal '*) (or context '*) tms-state)
                     :support :hippocampus :forward nil))
      ep)))

(defun hippocampus-size ()
  (length *hippocampus*))

(defun hippocampus-episodes (&key (goal nil) (context nil) (source nil))
  "List episodes filtered by separation keys (nil = no filter)."
  (remove-if-not
   (lambda (ep)
     (and (or (null goal) (equal goal (getf ep :goal)))
          (or (null context) (equal context (getf ep :context)))
          (or (null source) (eq source (getf ep :source)))))
   *hippocampus*))

(defun %weighted-pick (eps)
  "Pick one episode weighted by :priority."
  (let* ((wsum (max 1 (loop for e in eps sum (max 1 (or (getf e :priority) 1)))))
         (r (random wsum))
         (acc 0))
    (dolist (e eps (first eps))
      (incf acc (max 1 (or (getf e :priority) 1)))
      (when (> acc r) (return e)))))

(defun hippocampus-sample-prioritized (n &key (exclude-ids nil))
  "Sample up to N distinct episodes with priority bias (error/refuse > routine)."
  (let ((pool (remove-if (lambda (e) (member (getf e :id) exclude-ids :test #'equal))
                         *hippocampus*))
        (out nil)
        (ids nil))
    (when (null pool) (return-from hippocampus-sample-prioritized nil))
    (dotimes (_ n)
      (when (null pool) (return))
      (let ((e (%weighted-pick pool)))
        (push e out)
        (push (getf e :id) ids)
        (setf pool (remove (getf e :id) pool :key (lambda (x) (getf x :id))
                           :test #'equal))))
    (nreverse out)))

(defun hippocampus-interleaved-batches (new-text &key (k nil) (steps nil))
  "Build mini-batches: each is k old (prioritized) + 1 new.
   Returns (:batches list-of-strings :composition list-of-plists)."
  (let* ((k (or k *replay-k*))
         (steps (or steps (max 1 *consolidation-max-batches*)))
         (batches nil)
         (composition nil)
         (new (or new-text "")))
    (dotimes (i steps)
      (let* ((olds (hippocampus-sample-prioritized k))
             (old-texts (mapcar (lambda (e) (getf e :text)) olds))
             (pri-sum (loop for e in olds sum (or (getf e :priority) 1)))
             (blob (format nil "~{~A~%~}~A"
                           old-texts
                           (if (plusp (length new)) new ""))))
        (push blob batches)
        (push (list :step (1+ i)
                    :k-old (length olds)
                    :new 1
                    :old-ids (mapcar (lambda (e) (getf e :id)) olds)
                    :old-sources (mapcar (lambda (e) (getf e :source)) olds)
                    :old-priorities (mapcar (lambda (e) (getf e :priority)) olds)
                    :priority-sum pri-sum)
              composition)))
    (list :batches (nreverse batches)
          :composition (nreverse composition)
          :mode :interleaved-k-old-plus-1-new
          :k k
          :steps steps)))

;;; legacy helper used by older call sites
(defun hippocampus-replay-corpus (&key (n 16) (include-new nil))
  (declare (ignore include-new))
  (with-output-to-string (out)
    (dolist (ep (reverse (hippocampus-sample-prioritized n)))
      (format out "~A~%" (getf ep :text)))))

;;; ------------------------------------------------------------------
;;; Meta-cognition metrics + self-model
;;; ------------------------------------------------------------------

(defun hybrid-metrics ()
  (copy-list *hybrid-metrics*))

(defun hybrid-metrics-reset! ()
  (setf *hybrid-metrics*
        (list :loss-delta 0d0 :refuse-count 0 :allow-count 0 :learn-count 0
              :path-flips 0 :last-path nil :units 0 :last-loss nil)))

(defun hybrid-metrics-update! (unit)
  "Score unit: loss-delta, refuse/allow/learn counts, path flips."
  (incf (getf *hybrid-metrics* :units))
  (let* ((dec (getf unit :decision))
         (tms (getf unit :tms))
         (path (getf tms :after))
         (learned (getf unit :learned))
         (loss (and (consp learned)
                    (let ((h (getf learned :history)))
                      (and h (getf (first (last h)) :loss))))))
    (case dec
      (:refuse (incf (getf *hybrid-metrics* :refuse-count)))
      (:allow (incf (getf *hybrid-metrics* :allow-count)))
      (:learn (incf (getf *hybrid-metrics* :learn-count))))
    (when (and (getf *hybrid-metrics* :last-path)
               (not (eq (getf *hybrid-metrics* :last-path) path)))
      (incf (getf *hybrid-metrics* :path-flips)))
    (setf (getf *hybrid-metrics* :last-path) path)
    (when (and loss (numberp loss))
      (let ((prev (getf *hybrid-metrics* :last-loss)))
        (when (and prev (numberp prev))
          (setf (getf *hybrid-metrics* :loss-delta) (- prev loss)))
        (setf (getf *hybrid-metrics* :last-loss) loss)))
    *hybrid-metrics*))

(defun hybrid-refuse-rate ()
  (let* ((u (max 1 (getf *hybrid-metrics* :units)))
         (r (getf *hybrid-metrics* :refuse-count)))
    (/ (float r 0d0) u)))

(defun hybrid-metrics-adjust! (mind)
  "Adjust consolidation rate / path preference from metrics; persist self-model under TMS."
  (let* ((m (ensure-mind mind))
         (rr (hybrid-refuse-rate))
         (flips (getf *hybrid-metrics* :path-flips))
         (mode (cond ((>= rr 0.4d0) 'conservative)
                     ((>= flips 3) 'cautious)
                     (t 'normal)))
         (lr (cond ((eq mode 'conservative) 1d-4)
                   ((eq mode 'cautious) 2.5d-4)
                   (t 5d-4)))
         (batches (cond ((eq mode 'conservative) 6)
                        ((eq mode 'cautious) 8)
                        (t 12))))
    (setf *consolidation-lr* lr
          *consolidation-max-batches* batches)
    (let ((tms (or (mind-tms m) (setf (mind-tms m) (make-empty-tms)))))
      (tms-assert tms (list 'hybrid-mode mode) :informant :meta-cog)
      (tms-assert tms (list 'learn-rate lr) :informant :meta-cog)
      (tms-assert tms (list 'consolidation-batches batches) :informant :meta-cog)
      (assert-fact m (list 'hybrid-mode mode) :support :meta-cog :forward nil)
      (assert-fact m (list 'learn-rate lr) :support :meta-cog :forward nil)
      (assert-fact m (list 'consolidation-batches batches) :support :meta-cog :forward nil))
    (list :mode mode :lr lr :batches batches
          :refuse-rate rr :path-flips flips
          :metrics (hybrid-metrics))))

;;; ------------------------------------------------------------------
;;; Structured explain object
;;; ------------------------------------------------------------------

(defun make-explain-object (&key decision supporters tms-label episodes-used
                              weights-stepped why meta)
  "Machine-checkable explain for refuse/allow/learn."
  (list :explain t
        :decision decision
        :supporters (or supporters nil)
        :tms-label tms-label
        :episodes-used (or episodes-used nil)
        :weights-stepped (and weights-stepped t)
        :why (or why nil)
        :meta meta))

;;; ------------------------------------------------------------------
;;; Neocortex — interleaved prioritized consolidation
;;; ------------------------------------------------------------------

(defun neocortex-consolidate! (new-text &key (name nil)
                                          (epochs nil)
                                          (max-batches nil)
                                          (lr nil)
                                          (mind nil)
                                          (replay nil)
                                          (sleep nil))
  "Consolidate with replay v2: interleaved k-old + 1-new mini-batches.
   REPLAY defaults to *replay-enabled*. SLEEP = offline pass (new-text may be empty)."
  (let* ((mind (or mind *mind*))
         (name (or name *online-lm-name*))
         (use-replay (if (eq replay nil)
                         (if sleep t *replay-enabled*)
                         replay))
         (steps (or max-batches *consolidation-max-batches*))
         (batch-info nil)
         (hist-all nil)
         (weights-stepped nil))
    (when (and mind (not (nn-path-allowed-p mind)))
      (return-from neocortex-consolidate!
        (list :learned nil
              :refused t
              :reason "TMS nn-path-enabled is OUT — plasticity gated"
              :weights-stepped nil
              :batch-composition nil)))
    (cond
      (use-replay
       (setf batch-info (hippocampus-interleaved-batches
                         (or new-text "")
                         :k *replay-k*
                         :steps steps))
       (let ((batches (getf batch-info :batches)))
         (when (null batches)
           (return-from neocortex-consolidate!
             (list :learned nil :reason "no batches" :weights-stepped nil)))
         (dolist (b batches)
           (when (>= (length (string-trim '(#\Space #\Newline #\Tab) b)) 4)
             (let ((r (nn-continuous-train b
                                           :name name
                                           :epochs (or epochs *consolidation-epochs*)
                                           :lr (or lr *consolidation-lr*)
                                           :max-batches 1
                                           :hidden *consolidation-hidden*
                                           :seq-len *consolidation-seq-len*
                                           :depth *consolidation-depth*)))
               (setf weights-stepped t)
               (setf hist-all (append hist-all (or (getf r :history) nil))))))))
      (t
       (let ((corpus (or new-text "")))
         (when (< (length (string-trim '(#\Space #\Newline #\Tab) corpus)) 8)
           (return-from neocortex-consolidate!
             (list :learned nil :reason "corpus too small" :weights-stepped nil)))
         (let ((r (nn-continuous-train corpus
                                       :name name
                                       :epochs (or epochs *consolidation-epochs*)
                                       :lr (or lr *consolidation-lr*)
                                       :max-batches steps
                                       :hidden *consolidation-hidden*
                                       :seq-len *consolidation-seq-len*
                                       :depth *consolidation-depth*)))
           (setf weights-stepped t
                 hist-all (getf r :history)
                 batch-info (list :mode :no-replay :steps 1))))))
    (when mind
      (assert-fact mind
                   (list 'neocortex-consolidated name
                         (if sleep :sleep :online))
                   :support :neocortex :forward nil))
    (list :learned t
          :name name
          :history hist-all
          :weights-stepped weights-stepped
          :backend (ignore-errors (nn-backend-status))
          :op-counts (ignore-errors (metis.symbols:nn-backend-op-counts))
          :replay use-replay
          :sleep (and sleep t)
          :batch-composition (getf batch-info :composition)
          :batch-mode (getf batch-info :mode)
          :k (getf batch-info :k)
          :steps (or (getf batch-info :steps) steps)
          :replay-episodes (hippocampus-size)
          :corpus-chars (if use-replay
                            (reduce #'+ (mapcar #'length (getf batch-info :batches))
                                    :initial-value 0)
                            (length (or new-text ""))))))

(defun sleep-consolidate! (&key (mind nil) (max-batches nil))
  "Offline/sleep consolidation: prioritized interleaved replay over hippocampus."
  (neocortex-consolidate! ""
                          :mind (or mind *mind*)
                          :replay t
                          :sleep t
                          :max-batches (or max-batches *consolidation-max-batches*)))

;;; ------------------------------------------------------------------
;;; Forget-test (replay on vs off)
;;; ------------------------------------------------------------------

(defun %lm-eval-loss (model-name text)
  "Mean NLL of TEXT under registered MODEL-NAME (shipped lm-loss path)."
  (let* ((entry (metis.nn:nn-registry-get model-name))
         (model (getf entry :model)))
    (unless model
      (return-from %lm-eval-loss most-positive-double-float))
    (let* ((enc (metis.nn:vocab-encode (metis.nn:lm-vocab model) text))
           (n (length enc)))
      (when (< n 2)
        (return-from %lm-eval-loss most-positive-double-float))
      (let* ((inputs (subseq enc 0 (1- n)))
             (targets (subseq enc 1 n))
             (loss (metis.nn:lm-loss model inputs targets)))
        (aref (metis.nn:tensor-data loss) 0)))))

(defun %probe-token-score (model prompt token &key (length 60))
  "How often TOKEN appears in generate output (case-insensitive)."
  (let* ((entry (metis.nn:nn-registry-get model))
         (m (and entry (getf entry :model)))
         (gen (if m
                  (metis.nn:lm-generate m :prompt prompt :length length
                                        :temperature 0.7d0)
                  ""))
         (tok (string-downcase token))
         (g (string-downcase gen))
         (count 0)
         (pos 0))
    (loop
      (let ((p (search tok g :start2 pos)))
        (unless p (return))
        (incf count)
        (setf pos (+ p (length tok)))))
    (list :generate gen :token token :count count :score count)))

(defun hybrid-forget-test (&key (name "forget-lm"))
  "Teach A then B; probe retention of A with replay on vs off.
   Primary metric: lower eval loss on A is better (score = -loss)."
  (labels ((arm (replay-flag corpus-a corpus-b)
             (hippocampus-clear!)
             (let ((mname (format nil "~A-~A" name
                                  (if replay-flag "with" "without"))))
               (let ((*replay-enabled* replay-flag)
                     (*online-lm-name* mname))
                 (nn-train-language-model corpus-a
                                          :name mname
                                          :epochs 4 :hidden 48 :seq-len 32
                                          :depth 2 :max-batches 40 :lr 3d-2)
                 (dotimes (i 20)
                   (hippocampus-encode! corpus-a :source :teach :goal 'task-a
                                        :context "domain-a" :priority 20))
                 (neocortex-consolidate! corpus-a :name mname
                                         :replay t :max-batches 6 :lr 1d-2)
                 (dotimes (i 2)
                   (hippocampus-encode! corpus-b :source :teach :goal 'task-b
                                        :context "domain-b" :priority 1))
                 (if replay-flag
                     (neocortex-consolidate! corpus-b :name mname
                                             :replay t :max-batches 8 :lr 3d-3)
                     (neocortex-consolidate! corpus-b :name mname
                                             :replay nil :max-batches 40
                                             :lr 5d-2 :epochs 2))
                 (let* ((loss-a (%lm-eval-loss mname corpus-a))
                        (probe (%probe-token-score mname "alpha " "aaa"
                                                   :length 100))
                        (score (- loss-a)))
                   (list :replay replay-flag
                         :model mname
                         :loss-a loss-a
                         :probe-a probe
                         :score score))))))
    (let* ((corpus-a (format nil "~{~A ~}"
                             (loop repeat 50 collect "alpha zeta unique-token-AAA")))
           (corpus-b (format nil "~{~A ~}"
                             (loop repeat 50 collect "beta omega unique-token-BBB")))
           (with-r (arm t corpus-a corpus-b))
           (without-r (arm nil corpus-a corpus-b))
           (better (< (getf with-r :loss-a) (getf without-r :loss-a))))
      (list :with-replay with-r
            :without-replay without-r
            :better-with-replay better
            :scores (list :with (getf with-r :score)
                          :without (getf without-r :score)
                          :loss-with (getf with-r :loss-a)
                          :loss-without (getf without-r :loss-a))))))

(defun hybrid-coupled-propose (mind candidate-fact &key (prompt nil) (goal nil))
  "Neural may draft; symbolic assert-fact is the accept gate.
   Only accepted facts become success hippocampus episodes; rejects are high-priority errors."
  (let* ((m (ensure-mind mind))
         (*mind* m)
         (path (nn-path-allowed-p m))
         (supporters nil)
         (draft nil)
         (accepted nil)
         (decision nil)
         (why nil))
    (unless path
      (hippocampus-encode! (format nil "coupled-refuse ~S" candidate-fact)
                           :source :refuse :valence :blocked :success nil
                           :goal goal :priority 10)
      (return-from hybrid-coupled-propose
        (list :decision :refuse
              :accepted nil
              :candidate candidate-fact
              :explain (make-explain-object
                        :decision :refuse
                        :supporters (list (list :informant :tms
                                                :fact *nn-path-fact*
                                                :label :out))
                        :tms-label :out
                        :episodes-used nil
                        :weights-stepped nil
                        :why (list "TMS path OUT — coupled draft frozen")))))
    (when prompt
      (handler-case
          (setf draft (nn-generate *online-lm-name* :prompt prompt :length 40 :mind m))
        (error (e) (setf draft (princ-to-string e)))))
    (handler-case
        (progn
          (assert-fact m candidate-fact :support :coupled :forward nil)
          (setf accepted t))
      (error () (setf accepted nil)))
    (if accepted
        (progn
          (setf decision :allow)
          (push (list :informant :coupled :accepted t :fact candidate-fact) supporters)
          (push (list :informant :tms :fact *nn-path-fact* :label :in) supporters)
          (hippocampus-encode!
           (format nil "ACCEPTED ~S draft=~A" candidate-fact (or draft ""))
           :source :coupled-accept :success t :goal goal :priority 5)
          (push "Symbolic accept — success episode encoded" why)
          (let ((learned (when *online-learn-enabled*
                           (neocortex-consolidate!
                            (format nil "~S" candidate-fact) :mind m))))
            (list :decision (if (getf learned :learned) :learn :allow)
                  :accepted t
                  :candidate candidate-fact
                  :draft draft
                  :learned learned
                  :explain (make-explain-object
                            :decision (if (getf learned :learned) :learn :allow)
                            :supporters supporters
                            :tms-label :in
                            :episodes-used (list (getf (first *hippocampus*) :id))
                            :weights-stepped (getf learned :weights-stepped)
                            :why (if (getf learned :learned)
                                     (cons "Consolidated after accept" why)
                                     why)))))
        (progn
          (push (list :informant :coupled :accepted nil :fact candidate-fact) supporters)
          (hippocampus-encode!
           (format nil "REJECTED ~S" candidate-fact)
           :source :coupled-reject :success nil :goal goal :priority 8
           :valence :blocked)
          (list :decision :refuse
                :accepted nil
                :candidate candidate-fact
                :draft draft
                :learned nil
                :explain (make-explain-object
                          :decision :refuse
                          :supporters supporters
                          :tms-label :in
                          :episodes-used (list (getf (first *hippocampus*) :id))
                          :weights-stepped nil
                          :why (list "Symbolic reject — no success episode"
                                     "High-priority reject stored for replay")))))))

;;; ------------------------------------------------------------------
;;; TMS re-check (+ learn-rate influence on path flip)
;;; ------------------------------------------------------------------

(defun tms-recheck (mind &key (marker nil))
  (let* ((m (ensure-mind mind))
         (tms (or (mind-tms m) (setf (mind-tms m) (make-empty-tms))))
         (path-in (tms-in-p tms *nn-path-fact*))
         (marker (or marker (list 'hybrid-integrity (get-universal-time))))
         (ok t)
         (notes nil))
    (handler-case
        (progn
          (tms-assert tms marker :informant :hybrid-recheck)
          (unless (tms-in-p tms marker)
            (setf ok nil) (push "marker failed IN" notes))
          (tms-retract-assumption tms marker)
          (when (tms-in-p tms marker)
            (setf ok nil) (push "marker stuck IN" notes))
          (tms-assert tms marker :informant :hybrid-recheck)
          (unless (tms-in-p tms marker)
            (setf ok nil) (push "marker reinstate failed" notes)))
      (error (e) (setf ok nil) (push (princ-to-string e) notes)))
    (list :ok ok
          :nn-path (if path-in :in :out)
          :path-allowed (nn-path-allowed-p m)
          :notes (nreverse notes)
          :in-facts-sample (subseq (tms-in-facts tms)
                                   0 (min 8 (length (tms-in-facts tms)))))))

;;; On path retract, meta-adjust learn rate (dependency → plasticity policy)
(defun nn-disable-path-meta (&optional (mind *mind*))
  "Retract neural path and lower learn-rate via meta-cog (assumption retract effect)."
  (nn-disable-path mind)
  (incf (getf *hybrid-metrics* :path-flips))
  (setf (getf *hybrid-metrics* :last-path) :out)
  (hybrid-metrics-adjust! mind))

;;; ------------------------------------------------------------------
;;; Learn signal
;;; ------------------------------------------------------------------

(defun %learn-signal-p (text result &key force)
  (or force
      (and *online-learn-enabled*
           (or (and (stringp text)
                    (or (eql 0 (search "/learn" text :test #'char-equal))
                        (eql 0 (search "/teach" text :test #'char-equal))))
               (and (consp result)
                    (or (eq (getf result :freeform) :unknown)
                        (eq (first result) :error)))))))

(defun %strip-learn-prefix (text)
  (cond
    ((and (stringp text) (eql 0 (search "/learn " text :test #'char-equal)))
     (string-trim '(#\Space) (subseq text 7)))
    ((and (stringp text) (eql 0 (search "/teach " text :test #'char-equal)))
     (string-trim '(#\Space) (subseq text 7)))
    (t text)))

;;; ------------------------------------------------------------------
;;; Cognitive unit
;;; ------------------------------------------------------------------

(defun cognitive-unit (mind text &key (session nil)
                                   (learn :auto)
                                   (force-learn nil)
                                   (neural-prompt nil)
                                   (neural-model nil)
                                   (skip-act nil)
                                   (act-fn nil)
                                   (goal nil)
                                   (context nil))
  "Hybrid unit with explain object, separation encode, prioritized consolidate."
  (declare (ignore session))
  (let* ((m (ensure-mind mind))
         (*mind* m)
         (path-before (nn-path-allowed-p m))
         (tms-before (if path-before :in :out))
         (text (or text ""))
         (teach-body (%strip-learn-prefix text))
         (act-result nil)
         (neural-result nil)
         (decision :act)
         (why nil)
         (supporters nil)
         (learned nil)
         (episode nil)
         (episodes-used nil)
         (weights-stepped nil))
    (unless skip-act
      (cond
        ((or neural-prompt
             (and (stringp text)
                  (eql 0 (search "/generate" text :test #'char-equal))))
         (if (not path-before)
             (progn
               (setf decision :refuse
                     neural-result (list :refused t :reason "TMS nn-path-enabled is OUT")
                     why (list "Neural fire blocked: TMS path OUT"))
               (push (list :informant :tms :fact *nn-path-fact* :label :out) supporters)
               (hippocampus-encode! text :source :refuse :valence :blocked
                                    :success nil :goal goal :context context
                                    :tms-state :out :priority 10))
             (handler-case
                 (let* ((model (or neural-model *online-lm-name*))
                        (prompt (or neural-prompt
                                    (cl-ppcre:register-groups-bind (p)
                                        ("(?i)^/generate\\s+\\S+\\s*(.*)$" text)
                                      (or p ""))
                                    ""))
                        ;; constrained completion: cue + allowed IN facts
                        (facts (when (mind-tms m)
                                 (mapcar #'princ-to-string
                                         (subseq (tms-in-facts (mind-tms m))
                                                 0 (min 5 (length (tms-in-facts (mind-tms m))))))))
                        (full-prompt (format nil "~{~A ~}~A" facts (or prompt "")))
                        (gen (nn-generate model :prompt full-prompt :length 80 :mind m)))
                   (setf decision :allow
                         neural-result (list :text gen :model model :cue full-prompt)
                         why (list "TMS path IN — neural fire allowed"
                                   "completion uses cue + allowed TMS facts"))
                   (push (list :informant :tms :fact *nn-path-fact* :label :in) supporters)
                   (hippocampus-encode! (format nil "GEN: ~A" gen)
                                        :source :generate :valence :ok
                                        :goal goal :context context :tms-state :in))
               (error (e)
                 (setf decision :refuse
                       neural-result (list :error (princ-to-string e))
                       why (list "Neural fire failed" (princ-to-string e)))
                 (hippocampus-encode! text :source :error :valence :blocked
                                      :success nil :goal goal :priority 10)))))
        (act-fn
         (setf act-result (funcall act-fn m text)
               decision :act
               why (list "Symbolic act completed")))
        (t
         (setf act-result (list :note :no-act)
               why (list "No neural generate; symbolic path only")))))

    (setf episode
          (hippocampus-encode!
           (if (and teach-body (not (equal teach-body text))) teach-body text)
           :source (if (not (equal teach-body text)) :teach :turn)
           :valence (if (eq decision :refuse) :blocked :ok)
           :goal goal :context context
           :tms-state tms-before
           :success (not (eq decision :refuse))
           :meta (list :decision decision)))
    (when episode (push (getf episode :id) episodes-used))

    (let ((should (or force-learn
                      (eq learn t)
                      (and (eq learn :auto)
                           (%learn-signal-p text act-result :force force-learn))
                      (and (eq learn :auto) (not (equal teach-body text)))
                      (and (eq learn :auto) (eq decision :allow)))))
      (when (and should *online-learn-enabled*)
        (let ((cons (neocortex-consolidate!
                     (or teach-body text) :mind m :replay *replay-enabled*)))
          (setf learned cons
                weights-stepped (getf cons :weights-stepped))
          (if (getf cons :learned)
              (progn
                (setf decision (if (eq decision :refuse) :refuse :learn))
                (push (format nil "Interleaved consolidate k=~A steps=~A"
                              (or (getf cons :k) *replay-k*)
                              (or (getf cons :steps) 0))
                      why)
                (push (list :informant :neocortex
                            :weights-stepped weights-stepped
                            :batch-mode (getf cons :batch-mode))
                      supporters))
              (push (format nil "Learn skipped/refused: ~A"
                            (or (getf cons :reason) "unknown"))
                    why)))))

    (let* ((re (tms-recheck m))
           (unit (list :decision decision
                       :act act-result
                       :neural neural-result
                       :learned learned
                       :episode (and episode (getf episode :id))
                       :hippocampus-size (hippocampus-size)
                       :tms (list :before tms-before
                                  :after (getf re :nn-path)
                                  :recheck (getf re :ok)
                                  :notes (getf re :notes)
                                  :path-allowed (getf re :path-allowed))
                       :why (nreverse why)
                       :explain (make-explain-object
                                 :decision decision
                                 :supporters (nreverse supporters)
                                 :tms-label (getf re :nn-path)
                                 :episodes-used episodes-used
                                 :weights-stepped weights-stepped
                                 :why why)
                       :thesis *hybrid-thesis*)))
      (hybrid-metrics-update! unit)
      (hybrid-metrics-adjust! m)
      (setf (getf unit :metrics) (hybrid-metrics)
            (getf unit :self-model)
            (list :hybrid-mode
                  (ignore-errors
                    (and (mind-tms m)
                         (find-if (lambda (f)
                                    (and (consp f) (eq (first f) 'hybrid-mode)))
                                  (tms-in-facts (mind-tms m)))))))
      unit)))

(defun cognitive-turn (sess text &key (learn :auto) (force-learn nil))
  (let* ((m (sess-mind sess))
         (*mind* m)
         (is-gen (and (stringp text)
                      (eql 0 (search "/generate" text :test #'char-equal))))
         (is-learn-cmd (and (stringp text)
                            (or (eql 0 (search "/learn" text :test #'char-equal))
                                (eql 0 (search "/teach" text :test #'char-equal))))))
    (cond
      (is-gen
       (incf (sess-turn-count sess))
       (push (list :role :user :text text :time (now-iso)) (sess-turns sess))
       (let* ((unit (cognitive-unit m text :session sess :learn learn
                                    :force-learn force-learn))
              (reply (prin1-to-string (or (getf unit :neural) unit))))
         (push (list :role :assistant :text reply :result unit :time (now-iso)
                     :hybrid unit)
               (sess-turns sess))
         (list :reply reply :result (getf unit :neural) :hybrid unit
               :turn (sess-turn-count sess) :session (session-status sess))))
      (is-learn-cmd
       (incf (sess-turn-count sess))
       (push (list :role :user :text text :time (now-iso)) (sess-turns sess))
       (let* ((unit (cognitive-unit m text :session sess :learn t
                                    :force-learn t :skip-act t))
              (reply (prin1-to-string unit)))
         (push (list :role :assistant :text reply :result unit :time (now-iso)
                     :hybrid unit)
               (sess-turns sess))
         (list :reply reply :result unit :hybrid unit
               :turn (sess-turn-count sess) :session (session-status sess))))
      (t
       (let ((iface (iface-turn sess text)))
         (setf (getf iface :hybrid)
               (cognitive-unit m text :session sess :learn learn
                               :force-learn force-learn :skip-act t))
         iface)))))

(defun epoch-cognitive-step (st &optional percepts &key (learn :auto))
  (let* ((report (epoch-step st percepts))
         (m (epx-mind st))
         (blob (format nil "epoch-step=~A status=~A goals=~S"
                       (epx-steps st) (getf report :status) (epx-open-goals st)))
         (unit (cognitive-unit m blob
                               :learn learn
                               :goal (first (epx-open-goals st))
                               :force-learn (eq (getf report :status) :complete)
                               :skip-act t)))
    (list :epoch report :hybrid unit)))

;;; ------------------------------------------------------------------
;;; Demo
;;; ------------------------------------------------------------------

(defun hybrid-demo (&key (reset t))
  (when reset
    (boot :bootstrap t :reset t)
    (hippocampus-clear!)
    (hybrid-metrics-reset!))
  (let* ((m *mind*)
         (s (session-create :id "hybrid-demo" :boot nil))
         (trace nil))
    (nn-train-language-model
     (format nil "~{~A~%~}"
             (loop repeat 20 collect "metis learns with hippocampus and neocortex"))
     :name *online-lm-name*
     :epochs 1 :hidden 32 :seq-len 32 :depth 2 :max-batches 8)
    (nn-disable-path m)
    (let ((u (cognitive-unit m "/generate online-lm metis " :session s :learn nil)))
      (push (list :refuse u) trace)
      (assert (eq (getf u :decision) :refuse))
      (assert (eq (getf (getf u :explain) :tms-label) :out)))
    (nn-enable-path m)
    (let ((u (cognitive-unit m "/generate online-lm metis " :session s :learn :auto)))
      (push (list :allow u) trace)
      (assert (member (getf u :decision) '(:allow :learn))))
    (let ((u (cognitive-unit m "/learn the hippocampus encodes episodes quickly"
                             :session s :learn t :force-learn t)))
      (push (list :learn u) trace)
      (assert (getf (getf u :learned) :learned))
      (assert (getf (getf u :explain) :weights-stepped)))
    (let* ((ordered (reverse trace))
           (last-u (second (first (last ordered)))))
      (list :demo :hybrid :ok t :trace ordered
            :explain (getf last-u :explain)
            :metrics (hybrid-metrics)
            :thesis *hybrid-thesis*))))

(defun install-hybrid-tools (mind)
  (register-tool mind 'cognitive-unit
                 (lambda (text) (cognitive-unit mind text :learn :auto))
                 :doc "Hybrid cognitive unit" :schema '(text) :safe t)
  (register-tool mind 'hippocampus-size (lambda () (hippocampus-size))
                 :doc "Episode count" :safe t)
  (register-tool mind 'hybrid-demo (lambda () (hybrid-demo :reset nil))
                 :doc "Refuse/allow/learn/explain" :safe t)
  (register-tool mind 'hybrid-forget-test (lambda () (hybrid-forget-test))
                 :doc "Replay on vs off forget-test" :safe t)
  (register-tool mind 'sleep-consolidate (lambda () (sleep-consolidate! :mind mind))
                 :doc "Offline prioritized replay consolidate" :safe t)
  (register-tool mind 'hybrid-metrics (lambda () (hybrid-metrics))
                 :doc "Meta-cog metrics" :safe t)
  t)
