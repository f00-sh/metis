;;;; introspection.lisp — the mind examining and rewriting itself
(in-package :metis)

(defun mind-package-symbols (&optional (package :metis))
  (let ((out nil))
    (do-external-symbols (s package)
      (push s out))
    (sort out #'string< :key #'symbol-name)))

(defun mind-function-source (name)
  "Best-effort function description."
  (let ((s (if (symbolp name) name (find-symbol (string name) :metis))))
    (cond ((null s) nil)
          ((fboundp s)
           (list :name s
                 :type (cond ((special-operator-p s) :special)
                             ((macro-function s) :macro)
                             (t :function))
                 :lambda-list (or (ignore-errors
                                   (closer-mop:generic-function-lambda-list
                                    (symbol-function s)))
                                  :unknown)
                 :documentation (documentation s 'function)))
          (t nil))))

(defun self-model (mind)
  "Structured model of Metis' own state and capabilities."
  (list
   :identity "Metis"
   :kind "introspective cognitive architecture"
   :booted (and mind (mind-booted mind))
   :cycles (and mind (mind-cycle mind))
   :knowledge
   (list :facts (and mind (kb-count-facts (mind-kb mind)))
         :rules (and mind (length (kb-rules (mind-kb mind))))
         :frames (and mind (length (fs-all-frames (mind-frames mind)))))
   :memory
   (list :working (and mind (length (wmem-chunks (mind-wm mind))))
         :episodic (and mind (length (emem-episodes (mind-em mind))))
         :skills (and mind (hash-table-count
                            (pmem-skills (mind-pm mind)))))
   :goals (and mind (mind-goals mind))
   :tools (and mind (mapcar (lambda (x) (getf x :name))
                            (tr-list (mind-tools mind))))
   :operators (and mind
                   (mapcar #'op-name
                           (pd-operators-list (mind-domain mind))))
   :llm (llm-enabled-p)
   :version *metis-version*
   :codename *metis-codename*
   :tms-in (and mind (mind-tms mind)
                (length (tms-in-facts (mind-tms mind))))
   :htn-methods (and mind (mind-htn mind)
                     (hash-table-count (hd-methods (mind-htn mind))))
   :security (security-profile)
   :config
   (list :max-proof-depth (get-config :max-proof-depth)
         :max-plan-depth (get-config :max-plan-depth)
         :trace-reasoning (get-config :trace-reasoning)
         :safe-eval (get-config :safe-eval))
   :last-trace-length (and mind (length (mind-trace mind)))
   :exports (length (mind-package-symbols))))

(defun reason-trace (mind &optional (n 50))
  (subseq (mind-trace mind) 0 (min n (length (mind-trace mind)))))

(defun mind-trace-push (mind event &rest args)
  (when (get-config :trace-reasoning)
    (push (list* (now-iso) event args) (mind-trace mind))
    (let ((lim (get-config :trace-limit 200)))
      (when (> (length (mind-trace mind)) lim)
        (setf (mind-trace mind) (subseq (mind-trace mind) 0 lim))))))

(defun explain (mind &optional topic)
  "Natural-ish structured explanation of recent reasoning or a topic."
  (cond
    ((null topic)
     (list :type :last-reasoning
           :goals (mind-goals mind)
           :trace (reason-trace mind 30)
           :working (wm-contents (mind-wm mind))))
    ((eq topic :self)
     (self-model mind))
    ((eq topic :rules)
     (mapcar (lambda (r)
               (list (rule-name r)
                     :head (rule-head r)
                     :body (rule-body r)
                     :fired (rule-times-fired r)
                     :source (rule-source r)))
             (kb-rules (mind-kb mind))))
    ((eq topic :skills)
     (mapcar (lambda (s)
               (list (skill-name s)
                     :kind (skill-kind s)
                     :preconds (skill-preconds s)
                     :utility (skill-utility s)
                     :uses (skill-uses s)
                     :success-rate (skill-success-rate s)
                     :source (skill-source s)))
             (pm-all (mind-pm mind))))
    ((eq topic :episodes)
     (mapcar (lambda (e)
               (list :id (ep-id e)
                     :situation (ep-situation e)
                     :action (ep-action e)
                     :outcome (ep-outcome e)
                     :valence (ep-valence e)))
             (subseq (emem-episodes (mind-em mind))
                     0 (min 20 (length (emem-episodes (mind-em mind)))))))
    ((and (symbolp topic) (fs-get-frame (mind-frames mind) topic))
     (fs-describe (mind-frames mind) topic))
    ((and (symbolp topic) (fboundp topic))
     (mind-function-source topic))
    (t
     (list :topic topic
           :kb-matches (ask-all mind topic)
           :wm (wm-find (mind-wm mind) topic)))))

(defun reflect (mind &optional topic)
  "Deep introspection: explain + meta-notes + self-rewrite suggestions."
  (let* ((model (self-model mind))
         (base (explain mind topic))
         (failures
          (em-recall (mind-em mind) :tag :failure :limit 10))
         (notes nil))
    (when (zerop (getf (getf model :knowledge) :facts))
      (push "KB is empty — assert knowledge or load world." notes))
    (when (and (mind-goals mind)
               (null (reason-trace mind 1)))
      (push "Goals present but no recent reasoning — run cognitive-cycle." notes))
    (when failures
      (push (format nil "~D recent failure episodes — consider rewrite-rule or new skill."
                    (length failures))
            notes))
    (when (< (getf (getf model :memory) :skills) 1)
      (push "No procedural skills yet — successful plans can be compiled." notes))
    (list :self model
          :focus base
          :meta-notes (nreverse notes)
          :suggested-strategies
          (meta-suggest-strategies mind))))

(defun rewrite-rule (mind rule-name new-head new-body &key (priority 0))
  "Replace a rule by name — self-modification of theory."
  (let* ((kb (mind-kb mind))
         (old (find rule-name (kb-rules kb) :key #'rule-name :test #'equal)))
    (when old (kb-remove-rule kb old))
    (let ((r (kb-add-rule kb new-head (ensure-list new-body)
                          :name rule-name
                          :priority priority
                          :source :self-rewrite)))
      (mind-trace-push mind :rewrite-rule rule-name new-head new-body)
      (em-remember (mind-em mind)
                   :situation (list :rewrote-rule rule-name)
                   :action (list :install new-head new-body)
                   :outcome :ok
                   :valence 0.2
                   :tags '(:introspection :rewrite))
      r)))

(defun eval-in-mind (mind form)
  "Evaluate FORM with *mind* bound — sandboxed code-as-data by default."
  (declare (ignore mind))
  (mind-trace-push *mind* :eval form)
  (sandboxed-eval form))

(defun synthesize-skill (mind name plan-or-forms &key preconds params goals)
  "Install a new skill from a plan list or lisp body forms."
  (let ((skill
         (if (and (consp plan-or-forms)
                  (consp (first plan-or-forms))
                  (getf (first plan-or-forms) :name))
             (synthesize-skill-from-plan name plan-or-forms
                                         (or goals (mind-goals mind))
                                         (or preconds nil)
                                         :params params)
             (make-skill :name name
                         :params (or params nil)
                         :preconds (or preconds nil)
                         :body (ensure-list plan-or-forms)
                         :kind :procedure
                         :source :synthesized
                         :utility 1.0))))
    (pm-install (mind-pm mind) skill)
    (mind-trace-push mind :synthesize-skill name)
    (em-remember (mind-em mind)
                 :situation (list :learned-skill name)
                 :action plan-or-forms
                 :outcome :installed
                 :valence 0.5
                 :tags '(:learning :skill))
    skill))

(defun mind-status (mind)
  (format nil
          "Metis cycle=~A facts=~A rules=~A goals=~A wm=~A episodes=~A skills=~A llm=~A"
          (mind-cycle mind)
          (kb-count-facts (mind-kb mind))
          (length (kb-rules (mind-kb mind)))
          (length (mind-goals mind))
          (length (wmem-chunks (mind-wm mind)))
          (length (emem-episodes (mind-em mind)))
          (hash-table-count (pmem-skills (mind-pm mind)))
          (llm-enabled-p)))
