;;;; hybrid.lisp — CLS v2: prioritized interleaved replay, separation, meta-cog,
;;;; structured explain, coupled draft, sleep consolidate
(in-package :metis)

(defparameter *hippocampus-capacity* 128)
(defparameter *hippocampus* nil
  "Episodes newest-first. Each: :id :text :source :valence :priority
   :goal :context :tms-state :success :time :meta
   :summary :key  (soft latent text keys — not VAE vectors)")
(defparameter *summary-max-chars* 96
  "Max chars for soft episode summary used in latent replay.")

(defparameter *online-learn-enabled* t)
(defparameter *consolidation-epochs* 1)
(defparameter *consolidation-max-batches* 12)
(defparameter *consolidation-lr* 5d-4)
(defparameter *consolidation-hidden* 48)
(defparameter *consolidation-seq-len* 48)
(defparameter *consolidation-depth* 2)
(defparameter *train-max-batches-cap* 64
  "Hard cap on max-batches for pure-CL train (stability under load).")
(defparameter *train-max-epochs-cap* 8
  "Hard cap on epochs for pure-CL train.")
(defparameter *separation-retention-threshold* 1d0
  "Min A-token hit score for hybrid-separation-probe to :pass.")
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

(defun episode-summary-key (text &key (goal nil) (context nil) (max-chars nil))
  "Soft latent: short text summary + compact key (pure CL strings, not VAE)."
  (let* ((max-chars (or max-chars *summary-max-chars*))
         (clean (string-trim '(#\Space #\Newline #\Tab) (or text "")))
         (words (cl-ppcre:split "\\s+" clean))
         (head (subseq words 0 (min 8 (length words))))
         (summary (truncate-string
                   (format nil "~{~A~^ ~}" head)
                   max-chars))
         (key (format nil "~A|~A|~A"
                      (or goal '*)
                      (or context '*)
                      (if (plusp (length summary))
                          (subseq summary 0 (min 24 (length summary)))
                          "empty"))))
    (list :summary summary :key key)))

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
                                   (tms-state nil) (success t) (priority nil)
                                   (summary nil) (key nil))
  "Encode episodic trace with separation keys, priority, and soft latent summary/key."
  (when (and text (plusp (length (string-trim '(#\Space #\Newline) text))))
    (let* ((m *mind*)
           (tms-state (or tms-state
                          (if (and m (nn-path-allowed-p m)) :in :out)))
           (goal (or goal
                     (and m (mind-goals m) (first (mind-goals m)))))
           (pri (or priority (%episode-priority source valence success)))
           (sk (episode-summary-key text :goal goal :context context))
           (summary (or summary (getf sk :summary)))
           (key (or key (getf sk :key)))
           (ep (list :id (format nil "ep-~D-~D"
                                 (get-universal-time) (random 100000))
                     :text text
                     :summary summary
                     :key key
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
                     :support :hippocampus :forward nil)
        (assert-fact m
                     (list 'episode-key (getf ep :id) key)
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

(defun %episode-replay-text (ep)
  "Prefer soft latent summary+key for compact replay; fall back to full text."
  (let ((sum (getf ep :summary))
        (key (getf ep :key))
        (txt (getf ep :text)))
    (if (and sum (plusp (length sum)))
        (format nil "[~A] ~A" (or key "nokey") sum)
        (or txt ""))))

(defun hippocampus-interleaved-batches (new-text &key (k nil) (steps nil)
                                                   (use-summary t))
  "Build mini-batches: each is k old (prioritized) + 1 new.
   When USE-SUMMARY, old slots use soft latent summary/key text (not VAE).
   Returns (:batches list-of-strings :composition list-of-plists)."
  (let* ((k (or k *replay-k*))
         (steps (or steps (max 1 *consolidation-max-batches*)))
         (batches nil)
         (composition nil)
         (new (or new-text "")))
    (dotimes (i steps)
      (let* ((olds (hippocampus-sample-prioritized k))
             (old-texts (mapcar (lambda (e)
                                  (if use-summary
                                      (%episode-replay-text e)
                                      (getf e :text)))
                                olds))
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
                    :old-summaries (mapcar (lambda (e) (getf e :summary)) olds)
                    :old-keys (mapcar (lambda (e) (getf e :key)) olds)
                    :used-summary (and use-summary t)
                    :priority-sum pri-sum)
              composition)))
    (list :batches (nreverse batches)
          :composition (nreverse composition)
          :mode :interleaved-k-old-plus-1-new
          :soft-latent (and use-summary t)
          :k k
          :steps steps)))

;;; legacy helper used by older call sites
(defun hippocampus-replay-corpus (&key (n 16) (include-new nil))
  (declare (ignore include-new))
  (with-output-to-string (out)
    (dolist (ep (reverse (hippocampus-sample-prioritized n)))
      (format out "~A~%" (%episode-replay-text ep)))))

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
                                          (replay :default)
                                          (sleep nil))
  "Consolidate with replay v2: interleaved k-old + 1-new mini-batches.
   REPLAY: T / NIL force on/off; :DEFAULT → *replay-enabled* (or T when SLEEP).
   Both arms use the same step structure (N × max-batches=1) so only
   batch *content* differs — fair forget-test / CLS comparison."
  (let* ((mind (or mind *mind*))
         (name (or name *online-lm-name*))
         (use-replay (if (eq replay :default)
                         (if sleep t *replay-enabled*)
                         replay))
         (steps (or max-batches *consolidation-max-batches*))
         (ep (or epochs *consolidation-epochs*))
         (learn-rate (or lr *consolidation-lr*))
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
                                           :epochs ep
                                           :lr learn-rate
                                           :max-batches 1
                                           :hidden *consolidation-hidden*
                                           :seq-len *consolidation-seq-len*
                                           :depth *consolidation-depth*)))
               (setf weights-stepped t)
               (setf hist-all (append hist-all (or (getf r :history) nil))))))))
      (t
       ;; Fair no-replay: same N steps of max-batches=1 on pure NEW-TEXT only
       ;; (not one multi-batch call — that would change step count vs replay).
       (let ((corpus (or new-text "")))
         (when (< (length (string-trim '(#\Space #\Newline #\Tab) corpus)) 8)
           (return-from neocortex-consolidate!
             (list :learned nil :reason "corpus too small" :weights-stepped nil)))
         (dotimes (_ steps)
           (let ((r (nn-continuous-train corpus
                                         :name name
                                         :epochs ep
                                         :lr learn-rate
                                         :max-batches 1
                                         :hidden *consolidation-hidden*
                                         :seq-len *consolidation-seq-len*
                                         :depth *consolidation-depth*)))
             (setf weights-stepped t
                   hist-all (append hist-all (or (getf r :history) nil)))))
         (setf batch-info (list :mode :no-replay
                                :steps steps
                                :composition (loop for i from 1 to steps
                                                   collect (list :step i
                                                                 :k-old 0
                                                                 :new 1
                                                                 :priority-sum 0)))))))
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
                            (* steps (length (or new-text "")))))))

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

(defun %cap-train-params (epochs max-batches)
  "Apply pure-CL stability caps; returns (values epochs max-batches caps-plist)."
  (let* ((e (min (or epochs *train-max-epochs-cap*) *train-max-epochs-cap*))
         (b (min (or max-batches *train-max-batches-cap*) *train-max-batches-cap*)))
    (values e b
            (list :epochs-capped e :batches-capped b
                  :epochs-cap *train-max-epochs-cap*
                  :batches-cap *train-max-batches-cap*))))

(defun hybrid-forget-test (&key (name "forget-lm")
                                 (b-batches 20)
                                 (b-lr 5d-3)
                                 (b-epochs 1)
                                 (seed 42))
  "Teach A then B; probe retention of A with replay on vs off.
   Both arms share identical train hyperparams and step structure;
   only REPLAY on/off differs (fair CLS forget-test).
   Primary metric: lower eval loss on A is better (score = -loss)."
  (multiple-value-bind (b-epochs b-batches caps)
      (%cap-train-params b-epochs b-batches)
    (labels ((arm (replay-flag corpus-a corpus-b)
             (hippocampus-clear!)
             (let* ((mname (format nil "~A-~A" name
                                   (if replay-flag "with" "without")))
                    (*replay-enabled* replay-flag)
                    (*online-lm-name* mname)
                    ;; Same seed for both arms so init is comparable.
                    (*random-state* (sb-ext:seed-random-state seed)))
               (multiple-value-bind (e0 b0)
                   (%cap-train-params 4 40)
                 (nn-train-language-model corpus-a
                                          :name mname
                                          :epochs e0 :hidden 48 :seq-len 32
                                          :depth 2 :max-batches b0 :lr 3d-2))
               ;; A engrams: short, high-priority, separation-keyed
               (dotimes (i 30)
                 (hippocampus-encode! "alpha zeta unique-token-AAA"
                                      :source :teach :goal 'task-a
                                      :context "domain-a" :priority 20))
               (neocortex-consolidate! corpus-a :name mname
                                       :replay t :max-batches 4 :lr 1d-2
                                       :epochs 1)
               (dotimes (i 2)
                 (hippocampus-encode! "beta omega unique-token-BBB"
                                      :source :teach :goal 'task-b
                                      :context "domain-b" :priority 1))
               ;; B phase: identical procedure; only :replay flag differs.
               (neocortex-consolidate! corpus-b :name mname
                                       :replay replay-flag
                                       :max-batches b-batches
                                       :lr b-lr
                                       :epochs b-epochs)
               (let* ((loss-a (%lm-eval-loss mname corpus-a))
                      (loss-b (%lm-eval-loss mname corpus-b))
                      (probe (%probe-token-score mname "alpha " "aaa"
                                                 :length 100))
                      (score (- loss-a)))
                 (list :replay replay-flag
                       :model mname
                       :loss-a loss-a
                       :loss-b loss-b
                       :probe-a probe
                       :score score
                       :b-batches b-batches
                       :b-lr b-lr
                       :b-epochs b-epochs
                       :train-caps caps)))))
      (let* ((corpus-a (format nil "~{~A ~}"
                               (loop repeat 50 collect "alpha zeta unique-token-AAA")))
             (corpus-b (format nil "~{~A ~}"
                               (loop repeat 80 collect "beta omega unique-token-BBB")))
             (with-r (arm t corpus-a corpus-b))
             (without-r (arm nil corpus-a corpus-b))
             (better (< (getf with-r :loss-a) (getf without-r :loss-a))))
        (list :with-replay with-r
              :without-replay without-r
              :better-with-replay better
              :train-caps caps
              :fair-hyperparams (list :b-batches b-batches
                                      :b-lr b-lr
                                      :b-epochs b-epochs
                                      :seed seed
                                      :identical-procedure t
                                      :train-caps-applied t)
              :scores (list :with (getf with-r :score)
                            :without (getf without-r :score)
                            :loss-with (getf with-r :loss-a)
                            :loss-without (getf without-r :loss-a)))))))

;;; ------------------------------------------------------------------
;;; Coupled neural → symbolic accept/reject (fail-capable gate)
;;; ------------------------------------------------------------------

(defparameter *coupled-accept-templates*
  '((coupled-fact ?x)
    (allowed ?x)
    (ok-fact ?x)
    (accepted ?x)
    (permit ?x)
    (goal-satisfied ?g)
    (another-ok ?x))
  "Symbolic allow-list templates. Candidate must unify with one, or prove in KB.")

(defparameter *coupled-template-sources* nil
  "Alist of (source . templates) for domain-pack registration audit.")

(defun %intern-fact-metis (fact)
  "Intern list/symbol structure into :metis so cross-package callers unify."
  (labels ((walk (x)
             (cond ((consp x) (cons (walk (car x)) (walk (cdr x))))
                   ((symbolp x) (intern (symbol-name x) :metis))
                   (t x))))
    (walk fact)))

(defun register-coupled-templates! (templates &key (source :manual) (replace nil))
  "Register allow-templates for hybrid-coupled-accept-p (domain packs use this).
   TEMPLATES is a list of patterns; symbols interned into :metis."
  (let ((clean (mapcar #'%intern-fact-metis templates)))
    (setf *coupled-template-sources*
          (cons (cons source clean)
                (remove source *coupled-template-sources* :key #'car)))
    (if replace
        (setf *coupled-accept-templates* clean)
        (dolist (tmpl clean)
          (unless (member tmpl *coupled-accept-templates* :test #'equal)
            (push tmpl *coupled-accept-templates*))))
    (list :registered (length clean)
          :source source
          :templates (copy-list *coupled-accept-templates*)
          :replace (and replace t))))

(defun hybrid-coupled-accept-p (mind candidate-fact)
  "Pure symbolic accept gate — can fail under path IN.
   Accepts when CANDIDATE-FACT unifies with *coupled-accept-templates*
   or is justified by prove-query. Never uses assert-fact as the gate
   (assert-fact never signals on normal facts).
   Facts are interned into :metis so iface/tests packages match templates."
  (let ((fact (%intern-fact-metis candidate-fact)))
    (cond
      ((null fact)
       (values nil :empty "empty candidate"))
      ((not (consp fact))
       (values nil :not-list "candidate is not a list fact"))
      ((member (first fact) '(forbidden reject should-fail bad-fact)
               :test #'eq)
       (values nil :blocked-predicate
               (format nil "blocked predicate ~A" (first fact))))
      (t
       (let ((tmpl (find-if (lambda (pat)
                              (not (unify-fail-p (unify pat fact))))
                            *coupled-accept-templates*)))
         (if tmpl
             (values t :template (format nil "unified ~S" tmpl) fact)
             (let* ((kb (and mind (mind-kb (ensure-mind mind))))
                    (proofs (when kb
                              (ignore-errors (prove-query fact :kb kb)))))
               (if (and proofs (consp proofs))
                   (values t :proved "prove-query justified" fact)
                   (values nil :no-match
                           "no template unify and no KB proof"
                           fact)))))))))

(defun hybrid-coupled-propose (mind candidate-fact &key (prompt nil) (goal nil))
  "Neural may draft; symbolic hybrid-coupled-accept-p is the accept gate.
   Only accepted facts become success hippocampus episodes + optional learn;
   rejects under path IN are :coupled-reject (success nil, high priority)."
  (let* ((m (ensure-mind mind))
         (*mind* m)
         (path (nn-path-allowed-p m))
         (supporters nil)
         (draft nil)
         (accepted nil)
         (accept-kind nil)
         (accept-why nil)
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
    (multiple-value-bind (ok kind reason fact)
        (hybrid-coupled-accept-p m candidate-fact)
      (setf accepted ok
            accept-kind kind
            accept-why reason)
      (let ((fact (or fact (%intern-fact-metis candidate-fact))))
        (if accepted
            (progn
              ;; Commit only after symbolic accept (metis-interned fact).
              (assert-fact m fact :support :coupled :forward nil)
              (push (list :informant :coupled :accepted t :fact fact
                          :kind accept-kind :reason accept-why)
                    supporters)
              (push (list :informant :tms :fact *nn-path-fact* :label :in)
                    supporters)
              (push (list :informant :unifier :kind accept-kind
                          :reason accept-why)
                    supporters)
              (hippocampus-encode!
               (format nil "ACCEPTED ~S draft=~A" fact (or draft ""))
               :source :coupled-accept :success t :goal goal :priority 5)
              (push (format nil "Symbolic accept (~A) — success episode encoded"
                            accept-kind)
                    why)
              (let ((learned (when *online-learn-enabled*
                               (neocortex-consolidate!
                                (format nil "~S" fact) :mind m))))
                (list :decision (if (getf learned :learned) :learn :allow)
                      :accepted t
                      :candidate fact
                      :draft draft
                      :accept-kind accept-kind
                      :learned learned
                      :explain (make-explain-object
                                :decision (if (getf learned :learned)
                                              :learn :allow)
                                :supporters supporters
                                :tms-label :in
                                :episodes-used
                                (list (getf (first *hippocampus*) :id))
                                :weights-stepped
                                (getf learned :weights-stepped)
                                :why (if (getf learned :learned)
                                         (cons "Consolidated after accept" why)
                                         why)))))
            (progn
              (push (list :informant :coupled :accepted nil :fact fact
                          :kind accept-kind :reason accept-why)
                    supporters)
              (push (list :informant :tms :fact *nn-path-fact* :label :in)
                    supporters)
              (push (list :informant :unifier :kind accept-kind
                          :reason accept-why)
                    supporters)
              (hippocampus-encode!
               (format nil "REJECTED ~S reason=~A" fact accept-why)
               :source :coupled-reject :success nil :goal goal :priority 8
               :valence :blocked)
              (list :decision :coupled-reject
                    :accepted nil
                    :candidate fact
                    :draft draft
                    :accept-kind accept-kind
                    :learned nil
                    :explain (make-explain-object
                              :decision :coupled-reject
                              :supporters supporters
                              :tms-label :in
                              :episodes-used
                              (list (getf (first *hippocampus*) :id))
                              :weights-stepped nil
                              :why (list
                                    (format nil "Symbolic reject (~A): ~A"
                                            accept-kind accept-why)
                                    "No success episode — high-priority reject for replay")))))))))

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
                                   (context nil)
                                   (task-symbols t))
  "Hybrid unit with explain object, separation encode, prioritized consolidate.
   When TASK-SYMBOLS is true, run symbol-task-prepare! (classify + ensure-on-miss)
   before the act path so domain seals can activate for the utterance."
  (declare (ignore session))
  (let* ((m (ensure-mind mind))
         (*mind* m)
         (path-before (nn-path-allowed-p m))
         (tms-before (if path-before :in :out))
         (text (or text ""))
         (teach-body (%strip-learn-prefix text))
         (task-symbols-result
          (when (and task-symbols
                     (stringp text)
                     (plusp (length (string-trim '(#\Space #\Tab) text)))
                     (fboundp 'symbol-task-prepare!)
                     ;; skip slash-commands — they are control, not domain text
                     (not (eql 0 (search "/" text :test #'char-equal))))
            (ignore-errors
              (symbol-task-prepare! text :mind m :ensure t))))
         (act-result nil)
         (neural-result nil)
         (decision :act)
         (why nil)
         (supporters nil)
         (learned nil)
         (episode nil)
         (episodes-used nil)
         (weights-stepped nil))
    (when task-symbols-result
      (let ((st (getf task-symbols-result :status)))
        (when (member st '(:ok :partial))
          (push (format nil "Task symbols activated: ~{~A~^, ~}"
                        (or (getf task-symbols-result :activated) '()))
                why))
        (when (eq st :suggest-only)
          (push (format nil "Task symbol suggestions: ~{~A~^, ~}"
                        (or (getf task-symbols-result :suggestions) '()))
                why))))
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
                       :task-symbols task-symbols-result
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
  "Default EPOCH step always surfaces hybrid explain + metrics."
  (let* ((report (epoch-step st percepts))
         (m (epx-mind st))
         (blob (format nil "epoch-step=~A status=~A goals=~S"
                       (epx-steps st) (getf report :status) (epx-open-goals st)))
         (unit (cognitive-unit m blob
                               :learn learn
                               :goal (first (epx-open-goals st))
                               :force-learn (eq (getf report :status) :complete)
                               :skip-act t)))
    (list :epoch report
          :hybrid unit
          :explain (getf unit :explain)
          :metrics (or (getf unit :metrics) (hybrid-metrics)))))

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

;;; ------------------------------------------------------------------
;;; Separation metric: A→B then goal-A cue generate (A-token + NLL)
;;; ------------------------------------------------------------------

(defun hybrid-a-token-retention (model-name cue tokens &key (length 80))
  "Count how often any of TOKENS appears in generate(CUE). Returns score plist."
  (let* ((entry (metis.nn:nn-registry-get model-name))
         (m (and entry (getf entry :model)))
         (gen (if m
                  (metis.nn:lm-generate m :prompt cue :length length
                                        :temperature 0.7d0)
                  ""))
         (g (string-downcase gen))
         (hits 0)
         (per nil))
    (dolist (tok tokens)
      (let* ((t0 (string-downcase tok))
             (c 0)
             (pos 0))
        (loop
          (let ((p (search t0 g :start2 pos)))
            (unless p (return))
            (incf c)
            (setf pos (+ p (length t0)))))
        (incf hits c)
        (push (list :token tok :count c) per)))
    (list :generate gen :hits hits :per-token (nreverse per)
          :score (float hits 0d0))))

(defun hybrid-separation-probe (&key (name "sep-lm")
                                  (seq-len 64)
                                  (b-batches 12)
                                  (b-lr 5d-3)
                                  (seed 7)
                                  (cue "alpha ")
                                  (tokens '("aaa" "alpha" "zeta"))
                                  (threshold nil))
  "Teach A then B; probe A via NLL and fixed goal-A cue A-token retention.
   Passes when a-token-score >= THRESHOLD (default *separation-retention-threshold*)."
  (hippocampus-clear!)
  (multiple-value-bind (be bb caps)
      (%cap-train-params 3 b-batches)
    (let* ((mname name)
           (threshold (or threshold *separation-retention-threshold*))
           (corpus-a (format nil "~{~A ~}"
                             (loop repeat 40 collect "alpha zeta unique-token-AAA")))
           (corpus-b (format nil "~{~A ~}"
                             (loop repeat 60 collect "beta omega unique-token-BBB")))
           (*random-state* (sb-ext:seed-random-state seed))
           (*online-lm-name* mname)
           (*replay-enabled* t))
      (nn-train-language-model corpus-a :name mname :epochs be :hidden 48
                               :seq-len seq-len :depth 2 :max-batches
                               (min 30 *train-max-batches-cap*) :lr 3d-2)
      (dotimes (i 20)
        (hippocampus-encode! "alpha zeta unique-token-AAA"
                             :source :teach :goal 'task-a :context "domain-a"
                             :priority 20))
      (neocortex-consolidate! corpus-a :name mname :replay t :max-batches 3
                              :lr 1d-2 :epochs 1)
      (dotimes (i 2)
        (hippocampus-encode! "beta omega unique-token-BBB"
                             :source :teach :goal 'task-b :context "domain-b"
                             :priority 1))
      (neocortex-consolidate! corpus-b :name mname :replay t
                              :max-batches bb :lr b-lr :epochs 1)
      (let* ((loss-a (%lm-eval-loss mname corpus-a))
             (loss-b (%lm-eval-loss mname corpus-b))
             (retention (hybrid-a-token-retention
                         mname cue tokens :length 100))
             (score (getf retention :score))
             (pass (>= score threshold))
             (eps-a (hippocampus-episodes :goal 'task-a))
             (eps-b (hippocampus-episodes :goal 'task-b)))
        (list :model mname
              :seq-len seq-len
              :cue cue
              :tokens tokens
              :threshold threshold
              :loss-a loss-a
              :loss-b loss-b
              :a-token-retention retention
              :a-token-score score
              :pass pass
              :train-caps caps
              :separation-keys (list :a-count (length eps-a)
                                     :b-count (length eps-b)
                                     :a-context (getf (first eps-a) :context)
                                     :b-context (getf (first eps-b) :context)
                                     :a-summary (getf (first eps-a) :summary)
                                     :a-key (getf (first eps-a) :key))
              :metrics-numeric t)))))

(defun hybrid-long-context-train! (text &key (name "long-ctx-lm")
                                          (seq-len 128)
                                          (depth 3)
                                          (hidden 64)
                                          (epochs 1)
                                          (max-batches 8)
                                          (lr 1d-2)
                                          (mind nil))
  "Longer pure-CL context train that also reports separation + replay metrics."
  (let* ((m (or mind *mind*))
         (*online-lm-name* name)
         (r (nn-train-language-model text :name name :epochs epochs
                                     :hidden hidden :seq-len seq-len
                                     :depth depth :max-batches max-batches
                                     :lr lr))
         (sep (when m
                (hippocampus-encode! (truncate-string text 200)
                                     :source :teach :goal 'long-ctx
                                     :context (format nil "seq-~A" seq-len)
                                     :priority 6)
                (hippocampus-interleaved-batches "long-context new"
                                                 :k *replay-k* :steps 2)))
         (cons (when (and m (nn-path-allowed-p m))
                 (neocortex-consolidate! (truncate-string text 400)
                                         :name name :mind m
                                         :replay t :max-batches 2 :lr lr))))
    (list :trained t
          :name name
          :seq-len (or (getf r :seq-len) seq-len)
          :depth (or (getf r :depth) depth)
          :history (getf r :history)
          :separation (list :goal 'long-ctx
                            :episodes (length (hippocampus-episodes :goal 'long-ctx))
                            :keys (mapcar (lambda (e) (getf e :key))
                                          (hippocampus-episodes :goal 'long-ctx)))
          :replay (list :mode (getf sep :mode)
                        :soft-latent (getf sep :soft-latent)
                        :composition (getf sep :composition)
                        :k (getf sep :k))
          :consolidation (list :learned (getf cons :learned)
                               :replay (getf cons :replay)
                               :batch-mode (getf cons :batch-mode)
                               :weights-stepped (getf cons :weights-stepped))
          :metrics-reported t)))

;;; ------------------------------------------------------------------
;;; Offline / EPOCH sleep schedule + multi-supporter plan explain
;;; ------------------------------------------------------------------

(defun hybrid-offline-schedule! (mind &key (mode :sleep-epoch) (steps 3)
                                         (max-batches 4))
  "First-class offline schedule: sleep consolidation steps under MODE.
   MODE is :sleep-epoch (default) or :sleep-only."
  (let* ((m (ensure-mind mind))
         (*mind* m)
         (trace nil))
    (unless (nn-path-allowed-p m)
      (nn-enable-path m))
    (dotimes (i steps)
      (hippocampus-encode! (format nil "offline schedule step ~A" i)
                           :source :teach :priority 6
                           :goal 'offline :context (string mode))
      (let ((r (sleep-consolidate! :mind m :max-batches max-batches)))
        (push (list :step (1+ i) :consolidate r) trace)))
    (list :mode mode
          :schedule :offline-sleep
          :steps steps
          :identity (list :mode mode :schedule :offline-sleep :steps steps)
          :trace (nreverse trace)
          :hippocampus-size (hippocampus-size)
          :metrics (hybrid-metrics))))

(defun %plan-success-p (plan-result)
  "True when STRIPS plan result contains a non-empty plan (not :no-plan)."
  (and (consp plan-result)
       (getf plan-result :plan)
       (not (eq (getf plan-result :error) :no-plan))))

(defun %htn-success-p (htn-result)
  "True when HTN result has steps and status is not a fail."
  (and (consp htn-result)
       (getf htn-result :steps)
       (let ((st (getf htn-result :status)))
         (not (member st '(:fail :failed :error :no-plan) :test #'eq)))))

(defun hybrid-plan-explain (mind goal &key (domain nil))
  "Plan for GOAL; return structured explain with multi-supporters (TMS/STRIPS/HTN).
   Only successful STRIPS/HTN results become supporters (failed HTN/plan ignored)."
  (declare (ignore domain))
  (let* ((m (ensure-mind mind))
         (*mind* m)
         (supporters nil)
         (plan nil)
         (htn nil)
         (why nil)
         (strips-ok nil)
         (htn-ok nil))
    (handler-case
        (setf plan (plan m goal))
      (error (e) (push (princ-to-string e) why)))
    (handler-case
        (setf htn (htn-plan m goal))
      (error (e) (push (princ-to-string e) why)))
    (setf strips-ok (%plan-success-p plan)
          htn-ok (%htn-success-p htn))
    (when strips-ok
      (push (list :informant :strips :plan plan :goal goal) supporters)
      (push "STRIPS planner returned a plan" why))
    (when htn-ok
      (push (list :informant :htn :plan htn :goal goal) supporters)
      (push "HTN planner returned a method expansion" why))
    (when (and htn (not htn-ok))
      (push (list :informant :htn :status (getf htn :status) :failed t)
            supporters)
      (push (format nil "HTN did not succeed (status ~A)" (getf htn :status))
            why))
    (when (mind-tms m)
      (push (list :informant :tms
                  :in-facts (subseq (tms-in-facts (mind-tms m))
                                   0 (min 5 (length (tms-in-facts (mind-tms m)))))
                  :nn-path (if (nn-path-allowed-p m) :in :out))
            supporters)
      (push "TMS IN facts contribute justification" why))
    (when (and (null strips-ok) (null htn-ok)
               (not (find :tms supporters :key (lambda (s) (getf s :informant)))))
      (push (list :informant :planner :status :no-plan :goal goal) supporters)
      (push "No plan produced" why))
    (list :goal goal
          :plan plan
          :htn htn
          :strips-ok strips-ok
          :htn-ok htn-ok
          :explain (make-explain-object
                    :decision (if (or strips-ok htn-ok) :allow :refuse)
                    :supporters supporters
                    :tms-label (if (nn-path-allowed-p m) :in :out)
                    :episodes-used nil
                    :weights-stepped nil
                    :why (nreverse why))
          :multi-supporter (>= (length supporters) 2))))

;;; ------------------------------------------------------------------
;;; Trust policy (who may teach / enable nn-path)
;;; ------------------------------------------------------------------

(defun trust-policy-allows-p (mind action &key (actor nil) (society nil))
  "Policy gate: :teach and :nn-enable require society trust or local default."
  (let ((m (ensure-mind mind)))
    (case action
      ((:teach :nn-enable)
       (cond
         ((null actor) t) ; local / no actor → allowed
         ((null society) t)
         ((and (stringp actor)
               (equal actor (mind-name m)))
          t)
         ((society-trust-p society actor (mind-name m)) t)
         ((society-trust-p society actor "conductor") t)
         (t nil)))
      (t t))))

(defun nn-enable-path-policy (mind &key (actor nil) (society nil))
  "Enable nn-path only if trust policy allows :nn-enable for ACTOR."
  (unless (trust-policy-allows-p mind :nn-enable :actor actor :society society)
    (return-from nn-enable-path-policy
      (list :enabled nil :refused t :reason "trust-policy denied nn-enable"
            :actor actor)))
  (list :enabled (nn-enable-path mind) :refused nil :actor actor))

(defun hybrid-teach-policy (mind text &key (actor nil) (society nil) (session nil))
  "Teach/learn path gated by trust policy."
  (unless (trust-policy-allows-p mind :teach :actor actor :society society)
    (return-from hybrid-teach-policy
      (list :decision :refuse
            :refused t
            :reason "trust-policy denied teach"
            :actor actor
            :explain (make-explain-object
                      :decision :refuse
                      :supporters (list (list :informant :trust-policy
                                              :allowed nil :actor actor))
                      :tms-label (if (nn-path-allowed-p mind) :in :out)
                      :why (list "trust policy denied teach")))))
  (cognitive-unit mind (if (and (stringp text)
                                (not (eql 0 (search "/learn" text
                                                    :test #'char-equal))))
                           (format nil "/learn ~A" text)
                           text)
                  :session session :learn t :force-learn t :skip-act t))

;;; ------------------------------------------------------------------
;;; Curriculum ladder: A→B retention + refuse/allow/learn
;;; ------------------------------------------------------------------

(defun curriculum-ladder-run (&key (name "ladder-lm")
                                (mind nil)
                                (curriculum-path nil)
                                (threshold nil))
  "Run curriculum text + A→B retention probe + hybrid refuse/allow/learn."
  (let* ((m (or mind *mind* (boot :bootstrap t)))
         (*mind* m)
         (cur (or curriculum-path
                  (merge-pathnames "symbols/curriculum/curriculum.txt"
                                   (asdf:system-source-directory :metis))))
         (cur-r (when (probe-file cur)
                  (curriculum-apply cur :name name :epochs 1 :hidden 32
                                    :seq-len 64 :depth 2 :max-batches 4)))
         ;; nil threshold → hybrid-separation-probe uses *separation-retention-threshold*
         (sep (hybrid-separation-probe :name (format nil "~A-sep" name)
                                       :b-batches 6
                                       :threshold threshold))
         (trace nil))
    (nn-disable-path m)
    (push (list :refuse
                (cognitive-unit m "/generate online-lm ladder "
                                :learn nil))
          trace)
    (nn-enable-path m)
    (push (list :allow
                (cognitive-unit m "/generate online-lm ladder "
                                :learn :auto))
          trace)
    (push (list :learn
                (cognitive-unit m "/learn ladder encodes A then B with replay"
                                :learn t :force-learn t :skip-act t))
          trace)
    (let ((ordered (nreverse trace)))
      (list :curriculum cur-r
            :retention sep
            :retention-pass (getf sep :pass)
            :ladder ordered
            :phases (mapcar #'first ordered)
            :metrics (hybrid-metrics)))))

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
  (register-tool mind 'hybrid-separation-probe
                 (lambda () (hybrid-separation-probe))
                 :doc "A→B NLL + A-token retention" :safe t)
  t)
