;;;; tms-formal.lisp — mechanical formal properties of shipped JTMS-lite
(in-package :metis)

;;; Named properties (checked against real TMS operations):
;;; P1 JUSTIFICATION-SOUNDNESS: if a valid just has all supporters IN, conclusion IN
;;; P2 RETRACT-PROPAGATION: retracting a supporter of a sole justification yields OUT
;;; P3 MONOTONE-ASSERT: asserting a fact yields IN
;;; P4 NO-SPONTANEOUS-IN: fresh node without just is OUT
;;; P5 REINSTATE: after retract, re-assert restores IN

(defun tms-property-justification-soundness ()
  "P1: justify C from empty supporters ⇒ C is IN."
  (let ((tms (make-empty-tms)))
    (tms-justify tms 'c-sound nil :informant :p1)
    (tms-in-p tms 'c-sound)))

(defun tms-property-retract-propagation ()
  "P2: A supports B; retract A ⇒ B OUT."
  (let ((tms (make-empty-tms)))
    (tms-assert tms 'a-prop :informant :p2)
    (tms-justify tms 'b-prop '(a-prop) :informant :p2-rule)
    (unless (tms-in-p tms 'b-prop)
      (return-from tms-property-retract-propagation nil))
    (tms-retract-assumption tms 'a-prop)
    (not (tms-in-p tms 'b-prop))))

(defun tms-property-monotone-assert ()
  "P3: assert F ⇒ F IN."
  (let ((tms (make-empty-tms)))
    (tms-assert tms 'mono-f :informant :p3)
    (tms-in-p tms 'mono-f)))

(defun tms-property-no-spontaneous-in ()
  "P4: brand-new node without just is OUT."
  (let ((tms (make-empty-tms)))
    (tms-get-node tms 'ghost-node)
    (not (tms-in-p tms 'ghost-node))))

(defun tms-property-reinstate ()
  "P5: retract then re-assert restores IN."
  (let ((tms (make-empty-tms)))
    (tms-assert tms 're-f :informant :p5)
    (tms-retract-assumption tms 're-f)
    (when (tms-in-p tms 're-f)
      (return-from tms-property-reinstate nil))
    (tms-assert tms 're-f :informant :p5-again)
    (tms-in-p tms 're-f)))

(defun tms-property-chain-retract ()
  "P6: A→B→C chain; retract A ⇒ C OUT."
  (let ((tms (make-empty-tms)))
    (tms-assert tms 'ch-a :informant :p6)
    (tms-justify tms 'ch-b '(ch-a) :informant :p6)
    (tms-justify tms 'ch-c '(ch-b) :informant :p6)
    (unless (and (tms-in-p tms 'ch-b) (tms-in-p tms 'ch-c))
      (return-from tms-property-chain-retract nil))
    (tms-retract-assumption tms 'ch-a)
    (and (not (tms-in-p tms 'ch-b))
         (not (tms-in-p tms 'ch-c)))))

(defparameter *tms-formal-properties*
  '(("P1-JUSTIFICATION-SOUNDNESS" tms-property-justification-soundness)
    ("P2-RETRACT-PROPAGATION" tms-property-retract-propagation)
    ("P3-MONOTONE-ASSERT" tms-property-monotone-assert)
    ("P4-NO-SPONTANEOUS-IN" tms-property-no-spontaneous-in)
    ("P5-REINSTATE" tms-property-reinstate)
    ("P6-CHAIN-RETRACT" tms-property-chain-retract)))

(defun tms-formal-verify ()
  "Run all named TMS formal properties against the real TMS.
   Returns (values all-ok results-alist)."
  (let ((results nil)
        (ok t))
    (dolist (entry *tms-formal-properties*)
      (destructuring-bind (name fn) entry
        (let ((pass (handler-case (funcall fn)
                      (error (e)
                        (list :error (princ-to-string e))))))
          (unless (eq pass t)
            (setf ok nil))
          (push (list :property name :pass (eq pass t) :detail pass)
                results))))
    (values ok (nreverse results))))
