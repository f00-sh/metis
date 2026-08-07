;;;; epoch.lisp — EPOCH: Enduring Process of Open Cognitive Homotopy (Metis 3.0)
;;;;
;;;; Post-ARC thesis: ARC is a single-session continuum cycle. EPOCH is a
;;;; multi-session open-ended pursuit that (1) suspends open goals + mind image
;;;; to durable LMDB, (2) resumes across process boundaries, (3) treats the
;;;; system's own code/package surface as cognitive material, and (4) performs
;;;; guarded self-modification of skills/rules only while TMS integrity holds.
;;;;
;;;; No prior open Common Lisp stack ships multi-session open goal resume +
;;;; code-as-cognition + TMS-guarded self-mod as one obligatory unit on top of
;;;; RETE + JTMS + durable continuum.
(in-package :metis)

(defparameter *epoch-thesis*
  "EPOCH (Enduring Process of Open Cognitive Homotopy): multi-session open
pursuit where durable continuum state, live introspective use of the mind's
own code as cognitive material, and TMS-guarded self-modification cohere
into one process that can suspend, restart, and resume past any single
ARC cycle — going farther than Metis 2.0 ARC as an obligatory cognitive unit.")

(defstruct (epoch-state (:conc-name epx-))
  id
  mind
  (open-goals nil)
  (steps 0)
  (session 1)
  (status :open)          ; :open | :suspended | :complete | :failed
  (arc nil)
  (last-report nil)
  (self-mods 0)
  (code-facts 0)
  (history nil)
  (durable-key nil)
  (durable-path nil))

(defvar *epoch* nil)

(defun epoch-thesis ()
  *epoch-thesis*)

(defun epoch-default-path ()
  (or (get-config :epoch-durable-path)
      (merge-pathnames "epoch/"
                       (uiop:ensure-directory-pathname
                        (durable-default-path)))))

(defun %epoch-key (id suffix)
  (format nil "epoch/~A/~A" id suffix))

(defun epoch-open (mind goals &key (id nil) (durable-path nil))
  "Open a new EPOCH with OPEN goals. Does not complete them — suspendable."
  (let* ((m (ensure-mind mind))
         (id (or id (format nil "ep-~D" (get-universal-time))))
         (path (uiop:ensure-directory-pathname
                (or durable-path (epoch-default-path))))
         (st (make-epoch-state
              :id id
              :mind m
              ;; each element is one goal literal, e.g. (clear a)
              :open-goals (copy-tree (ensure-list goals))
              :steps 0
              :session 1
              :status :open
              :durable-key id
              :durable-path path)))
    (ensure-directories-exist path)
    (set-config :durable-path path)
    (durable-close)
    (durable-open path)
    ;; seed goals on mind
    (setf (mind-goals m) nil)
    (dolist (g (epx-open-goals st))
      (goal-push m g))
    (setf (epx-arc st) (arc-boot m :durable-key (%epoch-key id "arc")))
    ;; arc-boot may re-point LMDB; pin back to EPOCH store
    (durable-close)
    (durable-open path)
    (setf *epoch* st)
    (epoch-ingest-self-code m st)
    (metis-log :info "EPOCH open id=~A goals=~S thesis=~A"
               id (epx-open-goals st) (epoch-thesis))
    st))

(defun epoch-ingest-self-code (mind &optional st)
  "Treat the mind's own exported code surface as cognitive material (facts)."
  (let ((m (ensure-mind mind))
        (n 0))
    (dolist (sym (mind-package-symbols))
      (let ((src (ignore-errors (mind-function-source sym))))
        (when src
          (assert-fact m
                       (list 'self-code
                             (symbol-name (getf src :name sym))
                             (getf src :type :function))
                       :support :epoch-introspect
                       :forward nil)
          (incf n))))
    (assert-fact m
                 (list 'epoch-thesis-loaded (epoch-thesis))
                 :support :epoch
                 :forward nil)
    (when st
      (setf (epx-code-facts st) n))
    n))

(defun %epoch-ensure-mind-tms (mind)
  (let ((m (ensure-mind mind)))
    (unless (mind-tms m)
      (setf (mind-tms m) (make-empty-tms)))
    (mind-tms m)))

(defun %epoch-mind-tms-integrity (mind marker)
  "Integrity checks against the mind's LIVE TMS (not a fresh empty instance).
   MARKER must be IN with a valid justification; scratch retract/reinstate works."
  (let ((tms (%epoch-ensure-mind-tms mind)))
    (unless (tms-in-p tms marker)
      (error 'metis-error
             :message (format nil "mind TMS: marker ~S not IN" marker)))
    (unless (tms-why tms marker)
      (error 'metis-error
             :message (format nil "mind TMS: marker ~S has no valid why" marker)))
    ;; live retract/reinstate on THIS tms
    (let ((scratch (list 'epoch-integrity-scratch (get-universal-time))))
      (tms-assert tms scratch :informant :epoch-integrity)
      (unless (tms-in-p tms scratch)
        (error 'metis-error :message "mind TMS: cannot assert scratch"))
      (tms-retract-assumption tms scratch)
      (when (tms-in-p tms scratch)
        (error 'metis-error :message "mind TMS: scratch still IN after retract"))
      (tms-assert tms scratch :informant :epoch-integrity)
      (unless (tms-in-p tms scratch)
        (error 'metis-error :message "mind TMS: cannot reinstate scratch")))
    t))

(defun %epoch-restore-skill (pm name old-skill)
  (if old-skill
      (pm-install pm old-skill)
      (remhash name (pmem-skills pm))))

(defun epoch-guarded-self-mod (mind name head body &key (kind :rule))
  "Install a rule/skill only if the mind's LIVE TMS integrity holds after.
   Rolls back KB, skill table, and TMS marker on failure.
   Returns (values ok detail)."
  (let* ((m (ensure-mind mind))
         (kb (mind-kb m))
         (tms (%epoch-ensure-mind-tms m))
         (marker (list 'self-mod-ok name))
         (snap (kb-snapshot kb))
         (old-skill (when (eq kind :skill)
                      (pm-get (mind-pm m) name)))
         (had-marker (tms-in-p tms marker))
         (ok nil)
         (detail nil))
    (handler-case
        (progn
          (ecase kind
            (:rule
             (rewrite-rule m name head body :priority 1))
            (:skill
             (synthesize-skill m name body :preconds nil)))
          (tms-assert tms marker :informant :epoch-self-mod)
          (%epoch-mind-tms-integrity m marker)
          ;; RETE rebuild must succeed
          (forward-chain-rete m)
          (setf ok t
                detail (list :installed name :kind kind :tms-marker marker)))
      (error (e)
        (kb-restore kb snap)
        (when (eq kind :skill)
          (%epoch-restore-skill (mind-pm m) name old-skill))
        (when (and (mind-tms m) (not had-marker))
          (ignore-errors (tms-retract-assumption (mind-tms m) marker)))
        (when (mind-rete m) (setf (mind-rete m) nil))
        (setf ok nil
              detail (list :rolled-back (princ-to-string e)))))
    (when (and ok *epoch*)
      (incf (epx-self-mods *epoch*)))
    (values ok detail)))

(defun %epoch-goal-lit (goal)
  (cond ((and (consp goal) (member (car goal) '(:achieve :prove :answer)))
         (second goal))
        (t goal)))

(defun %epoch-try-achieve (mind goal)
  "Achieve GOAL via already-true / HTN / STRIPS / pursue. Returns T if KB holds goal."
  (let* ((m (ensure-mind mind))
         (lit (%epoch-goal-lit goal))
         (kb (mind-kb m)))
    (when (kb-holds-p kb lit)
      (return-from %epoch-try-achieve t))
    ;; HTN for (clear x)
    (when (and (consp lit) (eq (car lit) 'clear) (second lit))
      (ignore-errors
        (htn-plan m (list 'clear-rec (second lit)) :execute t))
      (when (kb-holds-p kb lit)
        (return-from %epoch-try-achieve t)))
    ;; STRIPS
    (ignore-errors (plan m lit :execute t))
    (when (kb-holds-p kb lit)
      (return-from %epoch-try-achieve t))
    ;; pursue fallback
    (ignore-errors (pursue m lit :max-cycles 12))
    (and (kb-holds-p kb lit) t)))

(defun epoch-step (st &optional percepts)
  "One EPOCH step: ARC cycle + achieve open goals + record history."
  (unless (eq (epx-status st) :open)
    (return-from epoch-step (epx-last-report st)))
  (let* ((m (epx-mind st))
         (arc-report (when (epx-arc st)
                       (arc-cycle (epx-arc st) percepts)))
         (remaining nil)
         (achieved nil))
    (incf (epx-steps st))
    (dolist (g (copy-list (epx-open-goals st)))
      (if (%epoch-try-achieve m g)
          (push g achieved)
          (push g remaining)))
    (setf (epx-open-goals st) (nreverse remaining))
    (when (null (epx-open-goals st))
      (setf (epx-status st) :complete))
    (let ((report
           (list :epoch t
                 :id (epx-id st)
                 :session (epx-session st)
                 :step (epx-steps st)
                 :status (epx-status st)
                 :achieved (nreverse achieved)
                 :remaining (epx-open-goals st)
                 :arc arc-report
                 :self-mods (epx-self-mods st)
                 :code-facts (epx-code-facts st)
                 :thesis (epoch-thesis))))
      (setf (epx-last-report st) report)
      (push report (epx-history st))
      report)))

(defun epoch-suspend (st)
  "Suspend EPOCH to durable LMDB (survives process exit)."
  (let* ((m (epx-mind st))
         (id (epx-id st))
         (path (epx-durable-path st)))
    (set-config :durable-path path)
    (durable-close)
    (durable-open path)
    (durable-save-mind m (%epoch-key id "mind"))
    (durable-put (%epoch-key id "meta")
                 (list :epoch-meta 1
                       :id id
                       :open-goals (epx-open-goals st)
                       :steps (epx-steps st)
                       :session (epx-session st)
                       :status :suspended
                       :self-mods (epx-self-mods st)
                       :code-facts (epx-code-facts st)
                       :saved (now-iso)
                       :thesis (epoch-thesis)
                       :version *metis-version*))
    (setf (epx-status st) :suspended)
    (metis-log :info "EPOCH suspend id=~A goals=~S" id (epx-open-goals st))
    (list :suspended t :id id :goals (epx-open-goals st) :path (namestring path))))

(defun epoch-resume (id &key (durable-path nil) (mind nil))
  "Resume EPOCH from durable store — works after process restart.
   Creates a fresh mind image, loads saved KB/goals, opens new session."
  (let* ((path (uiop:ensure-directory-pathname
                (or durable-path (epoch-default-path))))
         (m (or mind
                (progn
                  (boot :bootstrap t :reset t :domains t)
                  *mind*))))
    (set-config :durable-path path)
    (durable-close)
    (durable-open path)
    (let ((meta (durable-get (%epoch-key id "meta"))))
      (unless (and meta (eq (first meta) :epoch-meta))
        (error 'metis-error
               :message (format nil "no suspended epoch ~A at ~A" id path)))
      (unless (durable-load-mind m (%epoch-key id "mind"))
        (error 'metis-error :message "epoch mind image missing"))
      (let ((st (make-epoch-state
                 :id id
                 :mind m
                 :open-goals (getf meta :open-goals)
                 :steps (or (getf meta :steps) 0)
                 :session (1+ (or (getf meta :session) 1))
                 :status :open
                 :self-mods (or (getf meta :self-mods) 0)
                 :code-facts (or (getf meta :code-facts) 0)
                 :durable-key id
                 :durable-path path)))
        (setf (mind-goals m) nil)
        (dolist (g (epx-open-goals st))
          (goal-push m g))
        (setf (epx-arc st) (arc-boot m :durable-key (%epoch-key id "arc")))
        (durable-close)
        (durable-open path)
        (epoch-ingest-self-code m st)
        (setf *epoch* st)
        (metis-log :info "EPOCH resume id=~A session=~A goals=~S"
                   id (epx-session st) (epx-open-goals st))
        st))))

(defun epoch-run (st &key (max-steps 16) (suspend-each nil) (hybrid t))
  "Run EPOCH steps until complete, failed, or max-steps.
   When HYBRID is true (default), each step also runs the CLS cognitive unit
   (encode → optional consolidate → TMS re-check)."
  (loop for i from 1 to max-steps
        while (eq (epx-status st) :open)
        do (if (and hybrid (fboundp 'epoch-cognitive-step))
               (epoch-cognitive-step st)
               (epoch-step st))
           (when suspend-each
             (epoch-suspend st)
             (setf (epx-status st) :open)))
  (when (and (eq (epx-status st) :open)
             (plusp (length (epx-open-goals st))))
    (epoch-suspend st))
  (epx-last-report st))

(defun epoch-status (&optional st)
  (let ((st (or st *epoch*)))
    (when st
      (list :id (epx-id st)
            :session (epx-session st)
            :steps (epx-steps st)
            :status (epx-status st)
            :open-goals (epx-open-goals st)
            :self-mods (epx-self-mods st)
            :code-facts (epx-code-facts st)
            :thesis (epoch-thesis)))))

(defun epoch-flagship (&key
                         (durable-path nil)
                         (id "flagship")
                         ;; (clear b) is true in bootstrap — completes immediately;
                         ;; (clear a) requires HTN/STRIPS unstack and also completes.
                         (goals '((clear b) (clear a)))
                         (max-steps 12)
                         (resume nil)
                         (self-mod t))
  "Primary flagship program entry: open or resume EPOCH, optional guarded
   self-mod, run cognitive loop, report. Launched by bin/epoch."
  (format t "~%╔══════════════════════════════════════════════════════════╗~%")
  (format t "║  METIS 3.0 — EPOCH FLAGSHIP                              ║~%")
  (format t "║  Enduring Process of Open Cognitive Homotopy             ║~%")
  (format t "╚══════════════════════════════════════════════════════════╝~%")
  (format t "~A~%" (metis-version-string))
  (format t "~A~%~%" (epoch-thesis))
  (let* ((path (uiop:ensure-directory-pathname
                (or durable-path
                    (uiop:getenv "METIS_EPOCH_PATH")
                    (epoch-default-path))))
         (st (if resume
                 (progn
                   (boot :bootstrap t :reset t :domains t)
                   (epoch-resume id :durable-path path))
                 (progn
                   (boot :bootstrap t :reset t :domains t)
                   (epoch-open *mind* goals :id id :durable-path path)))))
    (when self-mod
      (multiple-value-bind (ok detail)
          (epoch-guarded-self-mod
           (epx-mind st)
           'epoch-flagship-rule
           '(epoch-flagship-marker ?x)
           '((true))
           :kind :rule)
        (format t "guarded-self-mod: ~S ~S~%" ok detail)
        (unless ok
          (format t ";; self-mod failed (integrity gate): ~S~%" detail))))
    (let ((report (epoch-run st :max-steps max-steps)))
      (format t "~%=== EPOCH FLAGSHIP REPORT ===~%")
      (format t "status=~S session=~S steps=~S remaining=~S achieved=~S~%"
              (epx-status st)
              (epx-session st)
              (epx-steps st)
              (epx-open-goals st)
              (getf report :achieved))
      (format t "self-mods=~S code-facts=~S~%"
              (epx-self-mods st) (epx-code-facts st))
      (format t "mind: ~A~%" (mind-status (epx-mind st)))
      (unless (eq (epx-status st) :complete)
        (epoch-suspend st)
        (format t "suspended for multi-session resume (id=~A path=~A)~%"
                id (namestring path)))
      (when (eq (epx-status st) :complete)
        (format t "EPOCH COMPLETE — goals achieved.~%"))
      (list :flagship t
            :version *metis-version*
            :codename *metis-codename*
            :report report
            :status (epoch-status st)
            :complete (eq (epx-status st) :complete)))))

(defun epoch-leap-resume-demo (path &key (id "leap-demo"))
  "Prove multi-session leap: open → suspend → NEW mind → resume → continue.
   PATH should be under a writable durable directory (e.g. SCRATCH)."
  (let ((path (uiop:ensure-directory-pathname path)))
    (ensure-directories-exist path)
    ;; Session 1
    (boot :bootstrap t :reset t :domains t)
    (set-config :auto-forward nil)
    (let ((st (epoch-open *mind* '((clear a)) :id id :durable-path path)))
      ;; Do not finish goals — force open state for resume proof
      (setf (epx-open-goals st) '((clear a)))
      (setf (mind-goals (epx-mind st)) '((clear a)))
      (epoch-suspend st)
      (durable-close))
    ;; Session 2 — simulate process restart: fresh boot + resume
    (boot :bootstrap t :reset t :domains t)
    (let* ((st2 (epoch-resume id :durable-path path))
           (goals-before (copy-tree (epx-open-goals st2)))
           (session (epx-session st2))
           (report (epoch-run st2 :max-steps 10)))
      (list :leap t
            :session session
            :goals-restored goals-before
            :final-status (epx-status st2)
            :report report
            :session-gt-1 (> session 1)
            :goals-were-open (not (null goals-before))))))
