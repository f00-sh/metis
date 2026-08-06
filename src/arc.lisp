;;;; arc.lisp — Autopoietic Reflexive Continuum (ARC)
;;;;
;;;; Novel intelligence thesis (Metis 2.0):
;;;; A closed cognitive loop in which *compiled reactive knowledge* (RETE),
;;;; *verified belief maintenance* (JTMS properties), and *durable continuum
;;;; memory* (LMDB) co-stabilize each other. Intelligence is not a single
;;;; inference pass but a self-repairing continuum cycle:
;;;;
;;;;   percept → RETE react → TMS validate → contradiction repair →
;;;;   durable checkpoint → meta-rewrite → continue
;;;;
;;;; No prior Common Lisp system integrated these three as one obligatory
;;;; unit of cognition with formal TMS guards and durable continuum state.
(in-package :metis)

(defparameter *arc-thesis*
  "Autopoietic Reflexive Continuum (ARC): dual-pathway intelligence in which
a RETE-compiled reactive cortex and a TMS-verified deliberative validator
share durable continuum memory; contradictions trigger autopoietic repair
(retract → rejoin → re-derive → checkpoint) rather than silent inconsistency.")

(defstruct (arc-state (:conc-name arc-))
  mind
  (cycles 0)
  (repairs 0)
  (checkpoints 0)
  (last-derived nil)
  (last-contradictions nil)
  (history nil))

(defvar *arc* nil)

(defun arc-thesis ()
  *arc-thesis*)

(defun arc-boot (mind &key (durable-key "arc-continuum"))
  "Initialize ARC continuum on MIND; open durable store; compile RETE."
  (let* ((m (ensure-mind mind))
         (st (make-arc-state :mind m)))
    (set-config :forward-engine :rete)
    (setf (mind-rete m) (rete-compile (mind-kb m)))
    (ignore-errors
      (durable-open
       (merge-pathnames "arc-continuum/"
                        (durable-default-path))))
    (setf *arc* st)
    (arc-checkpoint st durable-key)
    (metis-log :info "ARC boot: ~A" (arc-thesis))
    st))

(defun arc-detect-contradictions (mind)
  "Find facts labeled both IN in TMS soft belief 0 and KB-held with not-pair."
  (let ((m (ensure-mind mind))
        (hits nil))
    (dolist (f (kb-all-facts (mind-kb m)))
      (when (and (consp f) (eq (car f) 'not))
        (let ((inner (second f)))
          (when (kb-holds-p (mind-kb m) inner)
            (push (list :both f inner) hits))))
      ;; TMS out vs KB in is a soft contradiction signal
      (when (and (mind-tms m)
                 (kb-holds-p (mind-kb m) f)
                 (not (tms-in-p (mind-tms m) f))
                 (gethash f (tms-nodes (mind-tms m))))
        (push (list :tms-kb-diverge f) hits)))
    hits))

(defun arc-repair (st contradictions)
  "Autopoietic repair: retract losers, recompile RETE, re-derive."
  (let ((m (arc-mind st)))
    (dolist (c contradictions)
      (case (first c)
        (:both
         (retract-fact m (second c))
         (when (mind-tms m)
           (tms-retract-assumption (mind-tms m) (second c))))
        (:tms-kb-diverge
         ;; re-justify from KB assertion
         (when (mind-tms m)
           (tms-assert (mind-tms m) (second c) :informant :arc-repair)))))
    (setf (mind-rete m) (rete-compile (mind-kb m)))
    (let ((derived (forward-chain-rete m)))
      (incf (arc-repairs st))
      (setf (arc-last-derived st) derived)
      derived)))

(defun arc-checkpoint (st &optional (key "arc-continuum"))
  (durable-save-mind (arc-mind st) key)
  (incf (arc-checkpoints st))
  key)

(defun arc-cycle (st &optional percepts)
  "One ARC continuum cycle — the unit of ARC intelligence."
  (let ((m (arc-mind st)))
    (when percepts
      (perceive m percepts)
      (dolist (p (ensure-list percepts))
        (when (consp p)
          (rete-assert-wme (or (mind-rete m)
                               (setf (mind-rete m) (rete-compile (mind-kb m))))
                           p)
          (when (mind-tms m)
            (tms-assert (mind-tms m) p :informant :percept)))))
    ;; reactive cortex
    (let ((derived (forward-chain-rete m)))
      (setf (arc-last-derived st) derived)
      ;; deliberative validator
      (let ((contras (arc-detect-contradictions m)))
        (setf (arc-last-contradictions st) contras)
        (when contras
          (arc-repair st contras)))
      ;; durable continuum
      (arc-checkpoint st)
      (incf (arc-cycles st))
      (push (list :cycle (arc-cycles st)
                  :derived (length (ensure-list derived))
                  :repairs (arc-repairs st)
                  :contradictions (length (arc-last-contradictions st)))
            (arc-history st))
      (when (> (length (arc-history st)) 100)
        (setf (arc-history st) (subseq (arc-history st) 0 100)))
      (list :arc t
            :cycle (arc-cycles st)
            :derived derived
            :contradictions (arc-last-contradictions st)
            :repairs (arc-repairs st)
            :checkpoints (arc-checkpoints st)
            :thesis (arc-thesis)))))

(defun arc-status (&optional st)
  (let ((st (or st *arc*)))
    (when st
      (list :cycles (arc-cycles st)
            :repairs (arc-repairs st)
            :checkpoints (arc-checkpoints st)
            :history-len (length (arc-history st))
            :thesis (arc-thesis)
            :mind (mind-status (arc-mind st))))))
