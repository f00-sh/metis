;;;; agent.lisp — mind structure and full cognitive cycle
(in-package :metis)

(defstruct (mind (:conc-name mind-))
  (kb nil)
  (frames nil)
  (domain nil)
  (htn nil)
  (rete nil)
  (wm nil)
  (em nil)
  (pm nil)
  (tms nil)
  (beliefs nil)
  (tools nil)
  (blackboard nil)
  (society nil)
  (name "metis")
  (role :general)
  (inbox nil)
  (goals nil)          ; stack, car = current
  (trace nil)
  (cycle 0)
  (booted nil)
  (last-deliberation nil)
  (last-result nil)
  (percept-buffer nil)
  (lock (bt:make-lock "metis-mind")))

(defvar *mind* nil
  "The current global mind image.")

(defun ensure-mind (&optional mind)
  (or mind *mind*
      (error 'mind-not-booted)))

;;; ---------- constructors / lifecycle ----------

(defun init-mind-subsystems (m)
  (unless (mind-kb m) (setf (mind-kb m) (make-empty-kb)))
  (unless (mind-frames m) (setf (mind-frames m) (make-empty-frame-system)))
  (unless (mind-domain m) (setf (mind-domain m) (make-empty-domain)))
  (unless (mind-htn m) (setf (mind-htn m) (make-empty-htn)))
  (unless (mind-wm m) (setf (mind-wm m) (make-empty-wm)))
  (unless (mind-em m) (setf (mind-em m) (make-empty-em)))
  (unless (mind-pm m) (setf (mind-pm m) (make-empty-pm)))
  (unless (mind-tms m) (setf (mind-tms m) (make-empty-tms)))
  (unless (mind-beliefs m) (setf (mind-beliefs m) (make-empty-beliefs)))
  (unless (mind-tools m) (setf (mind-tools m) (make-empty-tools)))
  m)

(defun make-fresh-mind ()
  (init-mind-subsystems
   (make-mind
    :goals nil
    :trace nil
    :cycle 0
    :booted nil
    :name "metis"
    :role :general)))

(defun boot (&key (bootstrap t) (reset nil) (domains t))
  "Boot or re-boot the global mind."
  (init-config)
  (when (or reset (null *mind*))
    (setf *mind* (make-fresh-mind)))
  (let ((m *mind*))
    (init-mind-subsystems m)
    (install-core-tools (mind-tools m) (lambda () *mind*))
    (when (fboundp 'install-nn-tools)
      (install-nn-tools m))
    (when bootstrap
      (load-bootstrap m)
      (when (and domains (fboundp 'load-domains))
        (load-domains m)))
    (setf (mind-booted m) t)
    (mind-trace-push m :boot (now-iso) *metis-version*)
    (metis-log :info "~A boot complete — ~A" (metis-version-string) (mind-status m))
    (when (get-config :verbose)
      (format t "~&~A~%" (metis-version-string))
      (format t "~A~%" (mind-status m)))
    m))

(defun reset-mind ()
  (boot :bootstrap t :reset t))

(defun production-boot (&key (api nil) (daemon nil) (society nil)
                          (port nil) (token nil))
  "Full production boot: mind + optional API/daemon/society ensemble."
  (boot :bootstrap t :reset t :domains t)
  (set-config :verbose t)
  (when society
    (society-default-ensemble)
    (metis-log :info "society ensemble online (~D minds)"
               (hash-table-count (soc-minds *society*))))
  (when daemon
    (daemon-start *mind* :interval (get-config :daemon-interval 0.25)))
  (when api
    (api-start :port (or port (get-config :api-port 7433))
               :address (get-config :api-address "127.0.0.1")
               :token (or token (get-config :api-token))))
  (list :version *metis-version*
        :mind (mind-status *mind*)
        :api (api-status)
        :daemon (daemon-status)
        :society (and *society*
                      (mapcar #'mind-name (society-minds *society*)))))

;;; ---------- public KB / frame / memory API ----------

(defun assert-fact (mind fact &key (support :asserted) (belief 1.0)
                                (forward :auto))
  "Assert FACT. FORWARD controls opportunistic inference:
   :auto  — use (get-config :auto-forward) which is :agenda | :rete | nil
   :agenda / :rete / nil — force that engine (nil = no auto forward)."
  (let ((m (ensure-mind mind)))
    (multiple-value-bind (meta new-p)
        (kb-assert (mind-kb m) fact :support support)
      (wm-add (mind-wm m) fact :source :assert)
      (when (mind-tms m)
        (tms-assert (mind-tms m) fact :informant support :belief belief))
      (when (mind-beliefs m)
        (belief-set (mind-beliefs m) fact belief))
      (when (mind-blackboard m)
        (bb-post (mind-blackboard m) :fact fact
                 :author (mind-name m) :priority 0))
      (mind-trace-push m :assert fact (if new-p :new :refresh))
      (when new-p
        (let ((eng (if (eq forward :auto)
                       (get-config :auto-forward :agenda)
                       forward)))
          (case eng
            (:agenda (run-forward (mind-kb m) :max-iterations 50))
            (:rete
             (let ((net (or (mind-rete m)
                            (setf (mind-rete m)
                                  (rete-compile (mind-kb m))))))
               (rete-assert-wme net fact)))
            (t nil))))
      meta)))

(defun retract-fact (mind fact)
  (let ((m (ensure-mind mind)))
    (prog1 (kb-retract (mind-kb m) fact)
      (when (mind-tms m)
        (tms-retract-assumption (mind-tms m) fact))
      (when (mind-beliefs m)
        (belief-set (mind-beliefs m) fact 0.0))
      ;; RETE rebuild contract: never keep stale alpha / rp-fired
      (when (mind-rete m)
        (ignore-errors (rete-retract-wme (mind-rete m) fact))
        (setf (mind-rete m) nil))
      (mind-trace-push m :retract fact))))

(defun assert-rule (mind head body &key name priority)
  (let* ((m (ensure-mind mind))
         (r (kb-add-rule (mind-kb m) head body
                         :name name
                         :priority (or priority 0)
                         :source :asserted)))
    (mind-trace-push m :assert-rule (rule-name r) head body)
    r))

(defun facts (&optional mind)
  (kb-all-facts (mind-kb (ensure-mind mind))))

(defun rules (&optional mind)
  (kb-all-rules (mind-kb (ensure-mind mind))))

(defun tell (mind &rest fact-list)
  (dolist (f fact-list) (assert-fact mind f))
  :ok)

(defun ask (mind pattern)
  "First match / proof of pattern. Returns instantiation or NIL."
  (let* ((m (ensure-mind mind))
         (matches (prove-query pattern :kb (mind-kb m))))
    (mind-trace-push m :ask pattern (length matches))
    (first matches)))

(defun ask-all (mind pattern)
  (let ((m (ensure-mind mind)))
    (prove-query pattern :kb (mind-kb m))))

(defun forward-chain (&optional mind &key (engine nil))
  "Forward chain. ENGINE is :rete, :agenda, or NIL (use config :forward-engine)."
  (let* ((m (ensure-mind mind))
         (eng (or engine (get-config :forward-engine :agenda))))
    (if (eq eng :rete)
        (let ((derived (forward-chain-rete m)))
          (mind-trace-push m :forward-rete (length derived))
          (setf (mind-last-result m) derived)
          derived)
        (multiple-value-bind (derived fe)
            (run-forward (mind-kb m))
          (declare (ignore fe))
          (mind-trace-push m :forward (length derived))
          (setf (mind-last-result m) derived)
          derived))))

(defun deframe (mind name &rest slots)
  (apply #'fs-deframe (mind-frames (ensure-mind mind)) name slots))

(defun frame-get (mind frame slot &optional default)
  (fs-get (mind-frames (ensure-mind mind)) frame slot default))

(defun frame-set (mind frame slot value)
  (fs-set (mind-frames (ensure-mind mind)) frame slot value))

(defun frame-slots (mind frame)
  (fs-slots-plist (mind-frames (ensure-mind mind)) frame))

(defun all-frames (&optional mind)
  (mapcar #'fr-name (fs-all-frames (mind-frames (ensure-mind mind)))))

(defun define-operator (mind name &key params preconds add del cost)
  (pd-define-operator (mind-domain (ensure-mind mind))
                      name
                      :params params
                      :preconds preconds
                      :add add
                      :del del
                      :cost cost))

(defun plan (mind goals &key (execute nil))
  (let* ((m (ensure-mind mind))
         (goals (cond
                  ((null goals) nil)
                  ;; single literal (on a b)
                  ((and (consp goals) (symbolp (car goals)))
                   (list goals))
                  ;; list of literals ((on a b) (clear c))
                  (t (ensure-list goals))))
         ;; state = all ground facts currently held
         (state-facts (remove-if-not #'groundp (kb-all-facts (mind-kb m)))))
    (multiple-value-bind (steps final-state nodes)
        (plan-search (mind-domain m) state-facts goals)
      (declare (ignore final-state))
      (mind-trace-push m :plan goals (when steps (plan-to-sexps steps)) nodes)
      (if steps
          (progn
            (when (meta-should-compile-plan-p m steps goals)
              (learn-from-plan m steps goals))
            (when execute
              (execute-grounded-plan (mind-kb m) steps)
              (forward-chain m)
              (dolist (s steps)
                (dolist (a (getf s :add))
                  (when (mind-tms m)
                    (tms-assert (mind-tms m) a :informant :plan))
                  (when (mind-beliefs m)
                    (belief-set (mind-beliefs m) a 0.95)))))
            (setf (mind-last-result m) steps)
            (list :plan (plan-to-sexps steps)
                  :steps steps
                  :nodes nodes))
          (progn
            (meta-after-outcome m :plan nil (list :goals goals :nodes nodes))
            (setf (mind-last-result m) nil)
            (list :plan nil :nodes nodes :error :no-plan))))))

(defun execute-plan (mind plan-result)
  (let ((m (ensure-mind mind))
        (steps (or (getf plan-result :steps) plan-result)))
    (when (and steps (consp steps) (getf (first steps) :name))
      (let ((log (execute-grounded-plan (mind-kb m) steps)))
        (forward-chain m)
        (meta-after-outcome m :plan t log)
        log))))

(defun remember-episode (mind &key situation goals action outcome valence tags meta)
  (em-remember (mind-em (ensure-mind mind))
               :situation situation
               :goals (or goals (mind-goals mind))
               :action action
               :outcome outcome
               :valence (or valence 0.0)
               :tags tags
               :meta meta))

(defun recall-episodes (mind &key pattern tag since limit min-valence)
  (em-recall (mind-em (ensure-mind mind))
             :pattern pattern :tag tag :since since
             :limit limit :min-valence min-valence))

(defun install-skill (mind skill)
  (pm-install (mind-pm (ensure-mind mind)) skill))

(defun find-skills (mind &key pattern kind)
  (pm-find (mind-pm (ensure-mind mind)) :pattern pattern :kind kind))

(defun working-add (mind content &key source)
  (wm-add (mind-wm (ensure-mind mind)) content :source (or source :external)))

(defun working-contents (&optional mind)
  (wm-contents (mind-wm (ensure-mind mind))))

(defun register-tool (mind name fn &rest keys)
  (apply #'tr-register (mind-tools (ensure-mind mind)) name fn keys))

(defun invoke-tool (mind name &rest args)
  (let ((m (ensure-mind mind)))
    (mind-trace-push m :tool name args)
    (apply #'tr-invoke (mind-tools m) name args)))

(defun list-tools (&optional mind)
  (tr-list (mind-tools (ensure-mind mind))))

;;; ---------- goals ----------

(defun goal-push (mind &rest goals)
  (let ((m (ensure-mind mind)))
    (dolist (g (reverse goals))
      (push g (mind-goals m))
      (wm-add (mind-wm m) (list :goal g) :source :goal))
    (mind-goals m)))

(defun goal-pop (mind)
  (pop (mind-goals (ensure-mind mind))))

(defun current-goals (&optional mind)
  (copy-list (mind-goals (ensure-mind mind))))

;;; ---------- cognitive cycle ----------

(defun perceive (mind &optional percepts)
  "Ingest percepts into WM and KB."
  (let ((m (ensure-mind mind))
        (ps (or percepts (mind-percept-buffer mind))))
    (setf (mind-percept-buffer m) nil)
    (dolist (p (ensure-list ps))
      (wm-add (mind-wm m) p :source :percept :activation 1.5)
      (when (consp p)
        (kb-assert (mind-kb m) p :support :perceived)))
    (mind-trace-push m :perceive ps)
    ps))

(defun deliberate (mind)
  (setf (mind-last-deliberation (ensure-mind mind))
        (meta-deliberate (ensure-mind mind))))

(defun %goal-literal (goal)
  (cond ((and (consp goal) (member (car goal) '(:achieve :prove :answer :do)))
         (second goal))
        (t goal)))

(defun %try-skill (mind goal)
  (let* ((lit (%goal-literal goal))
         (skills (sort (copy-list (pm-all (mind-pm mind)))
                       #'> :key #'skill-utility)))
    (dolist (sk skills nil)
      (when (or (null (skill-preconds sk))
                (every (lambda (p) (kb-holds-p (mind-kb mind) p))
                       (skill-preconds sk)))
        (let ((meta (skill-meta sk)))
          (when (getf meta :plan)
            (let ((log (execute-grounded-plan (mind-kb mind)
                                              (getf meta :plan))))
              (pm-record-outcome (mind-pm mind) (skill-name sk) t 0.1)
              (return (list :skill (skill-name sk) :log log)))))))))

(defun act (mind strategy &optional args)
  "Execute selected strategy."
  (let* ((m (ensure-mind mind))
         (goal (first (mind-goals m)))
         (lit (%goal-literal goal))
         (result nil)
         (ok nil))
    (mind-trace-push m :act strategy goal)
    (setf result
          (handler-case
              (case strategy
                (:retrieve
                 (let ((hits (wm-find (mind-wm m) (or lit goal))))
                   (setf ok (not (null hits)))
                   hits))
                (:forward
                 (let ((d (forward-chain m)))
                   (setf ok (or (null lit)
                                (kb-holds-p (mind-kb m) lit)
                                (not (null (ask m lit)))))
                   d))
                (:backward
                 (multiple-value-bind (success subst all trace)
                     (prove (or lit goal) :kb (mind-kb m))
                   (declare (ignore trace))
                   (setf ok success)
                   (list :success success
                         :subst (pretty-subst subst)
                         :answers (mapcar (lambda (s)
                                            (apply-subst (or lit goal) s))
                                          all))))
                (:plan
                 ;; lit is one literal e.g. (clear a) — must NOT ensure-list
                 ;; it into (clear a) as two goals.
                 (let* ((goals (cond ((null lit) nil)
                                     ((and (consp lit)
                                           (symbolp (car lit)))
                                      (list lit))
                                     ((and (consp lit)
                                           (consp (car lit)))
                                      lit)
                                     (t (ensure-list lit))))
                        (pr (plan m goals :execute t)))
                   (setf ok (not (null (getf pr :plan))))
                   pr))
                (:skill
                 (let ((r (%try-skill m goal)))
                   (setf ok (not (null r)))
                   r))
                (:htn
                 (let ((pr (htn-plan m (or lit goal) :execute t)))
                   (setf ok (eq (getf pr :status) :ok))
                   pr))
                (:tool
                 (let* ((name (or (first args)
                                  (and (consp lit) (car lit))))
                        (targs (or (rest args)
                                   (and (consp lit) (cdr lit))))
                        (r (apply #'invoke-tool m name targs)))
                   (setf ok t)
                   r))
                (:llm
                 (if (llm-enabled-p)
                     (let ((r (llm-reason m
                                          (format nil "Goal: ~S~%Facts: ~S"
                                                  goal
                                                  (subseq (facts m) 0
                                                          (min 40 (length (facts m))))))))
                       (dolist (form (getf r :forms))
                         (ignore-errors (interpret m form)))
                       (setf ok t)
                       r)
                     (progn (setf ok nil)
                            '(:error :llm-disabled))))
                (:reflect
                 (setf ok t)
                 (reflect m lit))
                (:give-up
                 (setf ok nil)
                 (list :gave-up goal))
                (t
                 (setf ok nil)
                 (list :unknown-strategy strategy)))
            (error (e)
              (setf ok nil)
              (list :error (princ-to-string e)))))
    (meta-after-outcome m strategy ok result)
    (setf (mind-last-result m) result)
    (when (and ok goal
               (member strategy '(:plan :skill :backward :forward))
               (or (null lit)
                   (kb-holds-p (mind-kb m) lit)
                   (and (consp result) (eq (getf result :success) t))))
      (goal-pop m)
      (wm-add (mind-wm m) (list :achieved goal) :source :cycle))
    (values result ok)))

(defun cognitive-cycle (mind)
  "One full perceive → deliberate → act → encode loop."
  (let ((m (ensure-mind mind)))
    (incf (mind-cycle m))
    (perceive m)
    (unless (mind-goals m)
      (mind-trace-push m :cycle-idle)
      (return-from cognitive-cycle (list :cycle (mind-cycle m) :idle t)))
    (let* ((delib (deliberate m))
           (strategy (getf delib :strategy)))
      (multiple-value-bind (result ok)
          (act m strategy)
        (list :cycle (mind-cycle m)
              :strategy strategy
              :goal (first (mind-goals m)) ; may have been popped
              :ok ok
              :result result
              :status (mind-status m))))))

(defun pursue (mind goals &key (max-cycles 32))
  "Push goals and run cognitive cycles until goals cleared or max-cycles."
  (let ((m (ensure-mind mind)))
    (apply #'goal-push m (ensure-list goals))
    (let ((history nil))
      (loop for i from 1 to max-cycles
            while (mind-goals m)
            do (push (cognitive-cycle m) history))
      (list :remaining-goals (copy-list (mind-goals m))
            :history (nreverse history)
            :success (null (mind-goals m))
            :status (mind-status m)))))

(defun run-once (&optional mind)
  (cognitive-cycle (ensure-mind mind)))

(defun run (&optional mind)
  "Interactive REPL entry."
  (let ((m (or mind (boot))))
    (metis-repl m)))
