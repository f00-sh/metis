;;;; hybrid.lisp — Complementary Learning Systems + cognitive unit
;;;;
;;;; Brain-inspired on-the-fly learning (functional CLS):
;;;;   hippocampus  = fast episodic buffer
;;;;   neocortex    = slow LM consolidation (continuous train + replay)
;;;;   gate         = TMS nn-path-enabled
;;;; Cognitive unit: turn → optional train → TMS re-check → explain
(in-package :metis)

(defparameter *hippocampus-capacity* 64
  "Max episodic traces retained (ring buffer).")

(defparameter *hippocampus* nil
  "List of episode plists, newest first.")

(defparameter *online-learn-enabled* t
  "When true, cognitive-unit may consolidate after turns.")

(defparameter *consolidation-epochs* 1)
(defparameter *consolidation-max-batches* 12)
(defparameter *consolidation-lr* 5d-4)
(defparameter *consolidation-hidden* 64)
(defparameter *consolidation-seq-len* 64)
(defparameter *consolidation-depth* 2)
(defparameter *online-lm-name* "online-lm")

(defparameter *hybrid-thesis*
  "Hybrid cognitive unit: symbolic act and optional neural fire under TMS,
then CLS-style encode (hippocampus) + consolidate (neocortex with replay),
then TMS re-check — refuse / allow / learn / explain as one product path.")

;;; ------------------------------------------------------------------
;;; Hippocampus — fast episodic encode
;;; ------------------------------------------------------------------

(defun hippocampus-clear! ()
  (setf *hippocampus* nil))

(defun hippocampus-encode! (text &key (source :turn) (valence :neutral) (meta nil))
  "One-shot episodic encode (hippocampus). TEXT is the experience string."
  (when (and text (plusp (length text)))
    (let ((ep (list :id (format nil "ep-~D-~D"
                                (get-universal-time) (random 100000))
                    :text text
                    :source source
                    :valence valence
                    :time (now-iso)
                    :meta meta)))
      (push ep *hippocampus*)
      (when (> (length *hippocampus*) *hippocampus-capacity*)
        (setf *hippocampus* (subseq *hippocampus* 0 *hippocampus-capacity*)))
      (when *mind*
        (assert-fact *mind*
                     (list 'episode (getf ep :id) source)
                     :support :hippocampus :forward nil))
      ep)))

(defun hippocampus-replay-corpus (&key (n 16) (include-new nil))
  "Interleave recent episodes into a consolidation corpus (replay)."
  (declare (ignore include-new))
  (with-output-to-string (out)
    (let ((eps (subseq *hippocampus* 0 (min n (length *hippocampus*)))))
      ;; reverse so older material appears; still small set
      (dolist (ep (reverse eps))
        (format out "~A~%" (getf ep :text))))))

(defun hippocampus-size ()
  (length *hippocampus*))

;;; ------------------------------------------------------------------
;;; Neocortex — slow consolidation via continuous train + replay
;;; ------------------------------------------------------------------

(defun neocortex-consolidate! (new-text &key (name nil)
                                          (epochs nil)
                                          (max-batches nil)
                                          (lr nil)
                                          (mind nil))
  "Consolidate NEW-TEXT with replay of episodic buffer into online LM.
   Mimics neocortical slow learning interleaved with hippocampal replay.
   Requires TMS neural path IN when a mind is present."
  (let* ((mind (or mind *mind*))
         (name (or name *online-lm-name*))
         (replay (hippocampus-replay-corpus))
         (corpus (if (and new-text (plusp (length new-text)))
                     (format nil "~A~%~A" replay new-text)
                     replay)))
    (when (and mind (not (nn-path-allowed-p mind)))
      (return-from neocortex-consolidate!
        (list :learned nil
              :refused t
              :reason "TMS nn-path-enabled is OUT — plasticity gated")))
    (when (< (length (string-trim '(#\Space #\Newline #\Tab) corpus)) 8)
      (return-from neocortex-consolidate!
        (list :learned nil :reason "corpus too small")))
    (let ((r (nn-continuous-train corpus
                                  :name name
                                  :epochs (or epochs *consolidation-epochs*)
                                  :lr (or lr *consolidation-lr*)
                                  :max-batches (or max-batches
                                                   *consolidation-max-batches*)
                                  :hidden *consolidation-hidden*
                                  :seq-len *consolidation-seq-len*
                                  :depth *consolidation-depth*)))
      (when mind
        (assert-fact mind
                     (list 'neocortex-consolidated name
                           (getf r :continuous-steps))
                     :support :neocortex :forward nil))
      (list :learned t
            :name name
            :history (getf r :history)
            :continued (getf r :continued)
            :steps (getf r :continuous-steps)
            :backend (ignore-errors (nn-backend-status))
            :op-counts (ignore-errors (metis.symbols:nn-backend-op-counts))
            :corpus-chars (length corpus)
            :replay-episodes (hippocampus-size)))))

;;; ------------------------------------------------------------------
;;; TMS re-check
;;; ------------------------------------------------------------------

(defun tms-recheck (mind &key (marker nil))
  "Re-verify mind TMS integrity and neural path policy after a unit."
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
            (setf ok nil)
            (push "marker failed to go IN" notes))
          (tms-retract-assumption tms marker)
          (when (tms-in-p tms marker)
            (setf ok nil)
            (push "marker stuck IN after retract" notes))
          (tms-assert tms marker :informant :hybrid-recheck)
          (unless (tms-in-p tms marker)
            (setf ok nil)
            (push "marker failed reinstate" notes)))
      (error (e)
        (setf ok nil)
        (push (princ-to-string e) notes)))
    (list :ok ok
          :nn-path (if path-in :in :out)
          :path-allowed (nn-path-allowed-p m)
          :notes (nreverse notes)
          :in-facts-sample (subseq (tms-in-facts tms)
                                   0 (min 8 (length (tms-in-facts tms)))))))

;;; ------------------------------------------------------------------
;;; Learn signal (when should we consolidate?)
;;; ------------------------------------------------------------------

(defun %learn-signal-p (text result &key force)
  (or force
      (and *online-learn-enabled*
           (or (and (stringp text)
                    (or (eql 0 (search "/learn" text :test #'char-equal))
                        (eql 0 (search "/teach" text :test #'char-equal))))
               (and (consp result)
                    (or (eq (getf result :freeform) :unknown)
                        (eq (first result) :error)
                        (getf result :learned)
                        (member :train-text result)
                        (member :train-attachments result)))))))

(defun %strip-learn-prefix (text)
  (cond
    ((and (stringp text) (eql 0 (search "/learn " text :test #'char-equal)))
     (string-trim '(#\Space) (subseq text 7)))
    ((and (stringp text) (eql 0 (search "/teach " text :test #'char-equal)))
     (string-trim '(#\Space) (subseq text 7)))
    (t text)))

;;; ------------------------------------------------------------------
;;; Cognitive unit — single obligatory hybrid loop
;;; ------------------------------------------------------------------

(defun cognitive-unit (mind text &key (session nil)
                                   (learn :auto)
                                   (force-learn nil)
                                   (neural-prompt nil)
                                   (neural-model nil)
                                   (skip-act nil)
                                   (act-fn nil))
  "One cognitive unit:
   1. optional symbolic/neural act
   2. hippocampus encode
   3. optional neocortex consolidate (on-the-fly train + replay)
   4. TMS re-check
   5. explain refuse | allow | learn | why

   LEARN is :auto | t | nil. FORCE-LEARN always consolidates when path IN."
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
         (learned nil)
         (episode nil))
    ;; --- Act (unless skip) ---
    (unless skip-act
      (cond
        ;; explicit neural generate request
        ((or neural-prompt
             (and (stringp text)
                  (eql 0 (search "/generate" text :test #'char-equal))))
         (if (not path-before)
             (progn
               (setf decision :refuse
                     neural-result
                     (list :refused t
                           :reason "TMS nn-path-enabled is OUT")
                     why (list "Neural fire blocked: TMS path OUT"
                               "Enable with nn-enable-path or /nn enable"))
               (hippocampus-encode! text :source :refuse :valence :blocked))
             (handler-case
                 (let* ((model (or neural-model *online-lm-name*))
                        (prompt (or neural-prompt
                                    (cl-ppcre:register-groups-bind (p)
                                        ("(?i)^/generate\\s+\\S+\\s*(.*)$" text)
                                      (or p ""))
                                    ""))
                        (gen (nn-generate model
                                          :prompt (or prompt "")
                                          :length 80
                                          :mind m)))
                   (setf decision :allow
                         neural-result (list :text gen :model model)
                         why (list "TMS path IN — neural fire allowed"
                                   (format nil "generated from ~A" model)))
                   (hippocampus-encode! (format nil "GEN: ~A" gen)
                                        :source :generate :valence :ok))
               (error (e)
                 (setf decision :refuse
                       neural-result (list :error (princ-to-string e))
                       why (list "Neural fire failed"
                                 (princ-to-string e)))))))
        (act-fn
         (setf act-result (funcall act-fn m text session)
               decision :act
               why (list "Symbolic/iface act completed")))
        (t
         (setf act-result (list :note :no-act)
               why (list "No neural generate; symbolic path only")))))

    ;; Always encode the user material (experience)
    (setf episode
          (hippocampus-encode!
           (if (and teach-body (not (equal teach-body text)))
               teach-body
               text)
           :source (if (not (equal teach-body text)) :teach :turn)
           :valence (if (eq decision :refuse) :blocked :ok)
           :meta (list :decision decision)))

    ;; --- Learn (neocortex consolidate) ---
    (let ((should (or force-learn
                      (eq learn t)
                      (and (eq learn :auto)
                           (%learn-signal-p text act-result :force force-learn))
                      (and (eq learn :auto)
                           (not (equal teach-body text)))
                      (and (eq learn :auto)
                           (eq decision :allow)))))
      (when (and should *online-learn-enabled*)
        (let ((cons (neocortex-consolidate!
                     (or teach-body text)
                     :mind m)))
          (setf learned cons)
          (if (getf cons :learned)
              (progn
                (setf decision (if (eq decision :refuse) :refuse :learn))
                (push (format nil "Consolidated ~A chars with ~A replay episodes"
                              (getf cons :corpus-chars)
                              (getf cons :replay-episodes))
                      why))
              (push (format nil "Learn skipped/refused: ~A"
                            (or (getf cons :reason) "unknown"))
                    why)))))

    ;; --- TMS re-check ---
    (let ((re (tms-recheck m)))
      (list :decision decision
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
            :thesis *hybrid-thesis*))))

(defun cognitive-turn (sess text &key (learn :auto) (force-learn nil))
  "Session-level cognitive unit: run iface act then hybrid learn/explain.
   On-the-fly training runs when learn signals fire (teach, unknown, allow)."
  (let* ((m (sess-mind sess))
         (*mind* m)
         (is-gen (and (stringp text)
                      (eql 0 (search "/generate" text :test #'char-equal))))
         (is-learn-cmd (and (stringp text)
                            (or (eql 0 (search "/learn" text :test #'char-equal))
                                (eql 0 (search "/teach" text :test #'char-equal)))))
         (unit nil)
         (iface nil))
    (cond
      (is-gen
       (incf (sess-turn-count sess))
       (push (list :role :user :text text :time (now-iso)) (sess-turns sess))
       (setf unit (cognitive-unit m text :session sess :learn learn
                                  :force-learn force-learn))
       (let ((reply (prin1-to-string (or (getf unit :neural) unit))))
         (push (list :role :assistant :text reply :result unit :time (now-iso)
                     :hybrid unit)
               (sess-turns sess))
         (list :reply reply :result (getf unit :neural) :hybrid unit
               :turn (sess-turn-count sess)
               :session (session-status sess))))
      (is-learn-cmd
       (incf (sess-turn-count sess))
       (push (list :role :user :text text :time (now-iso)) (sess-turns sess))
       (setf unit (cognitive-unit m text :session sess :learn t
                                  :force-learn t :skip-act t))
       (let ((reply (prin1-to-string unit)))
         (push (list :role :assistant :text reply :result unit :time (now-iso)
                     :hybrid unit)
               (sess-turns sess))
         (list :reply reply :result unit :hybrid unit
               :turn (sess-turn-count sess)
               :session (session-status sess))))
      (t
       (setf iface (iface-turn sess text))
       (setf unit
             (cognitive-unit m text
                             :session sess
                             :learn learn
                             :force-learn (or force-learn
                                              (let ((r (getf iface :result)))
                                                (and (consp r)
                                                     (eq (getf r :freeform)
                                                         :unknown))))
                             :skip-act t))
       (setf (getf iface :hybrid) unit)
       iface))))

(defun epoch-cognitive-step (st &optional percepts &key (learn :auto))
  "EPOCH step as hybrid unit: pursue + optional consolidate + TMS re-check."
  (let* ((report (epoch-step st percepts))
         (m (epx-mind st))
         (blob (format nil "epoch-step=~A status=~A goals=~S"
                       (epx-steps st)
                       (getf report :status)
                       (epx-open-goals st)))
         (unit (cognitive-unit m blob
                               :learn learn
                               :force-learn (eq (getf report :status) :complete)
                               :skip-act t)))
    (list :epoch report :hybrid unit)))

;;; ------------------------------------------------------------------
;;; Demo: refuse / allow / learn / explain
;;; ------------------------------------------------------------------

(defun hybrid-demo (&key (reset t))
  "Public demo converting architecture into reckonable path:
   refuse (TMS OUT) → enable → allow generate → teach/learn → explain."
  (when reset
    (boot :bootstrap t :reset t)
    (hippocampus-clear!))
  (let* ((m *mind*)
         (s (session-create :id "hybrid-demo" :boot nil))
         (trace nil))
    ;; ensure model exists small
    (nn-train-language-model
     (format nil "~{~A~%~}"
             (loop repeat 20 collect "metis learns with hippocampus and neocortex"))
     :name *online-lm-name*
     :epochs 1 :hidden 32 :seq-len 32 :depth 2 :max-batches 8)
    ;; 1 REFUSE
    (nn-disable-path m)
    (let ((u (cognitive-unit m "/generate online-lm metis "
                             :session s :learn nil)))
      (push (list :refuse u) trace)
      (assert (eq (getf u :decision) :refuse) () "expected refuse"))
    ;; 2 ALLOW (+ auto consolidate → decision may be :learn)
    (nn-enable-path m)
    (let ((u (cognitive-unit m "/generate online-lm metis "
                             :session s :learn :auto)))
      (push (list :allow u) trace)
      (assert (member (getf u :decision) '(:allow :learn))
              () "expected allow or learn after path IN"))
    ;; 3 LEARN (explicit teach)
    (let ((u (cognitive-unit m "/learn the hippocampus encodes episodes quickly"
                             :session s :learn t :force-learn t)))
      (push (list :learn u) trace)
      (assert (getf (getf u :learned) :learned) () "expected consolidation"))
    ;; 4 EXPLAIN snapshot
    (let* ((ordered (reverse trace))
           (last-u (second (first (last ordered))))
           (explain (list :phases (mapcar #'first ordered)
                          :last-decision (getf last-u :decision)
                          :why (getf last-u :why)
                          :tms (getf last-u :tms)
                          :hippocampus (hippocampus-size)
                          :thesis *hybrid-thesis*)))
      (list :demo :hybrid
            :ok t
            :trace ordered
            :explain explain))))

(defun install-hybrid-tools (mind)
  (register-tool
   mind 'cognitive-unit
   (lambda (text)
     (cognitive-unit mind text :learn :auto))
   :doc "Run hybrid cognitive unit on TEXT"
   :schema '(text)
   :safe t)
  (register-tool
   mind 'hippocampus-size
   (lambda () (hippocampus-size))
   :doc "Number of episodic traces"
   :safe t)
  (register-tool
   mind 'hybrid-demo
   (lambda () (hybrid-demo :reset nil))
   :doc "Refuse/allow/learn/explain demo"
   :safe t)
  t)
