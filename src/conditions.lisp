;;;; conditions.lisp
(in-package :metis)

(define-condition metis-error (error)
  ((message :initarg :message :reader metis-error-message))
  (:report (lambda (c s)
             (format s "Metis error: ~A" (metis-error-message c)))))

(define-condition unification-failure (metis-error) ())

(define-condition proof-failure (metis-error)
  ((goal :initarg :goal :reader proof-failure-goal))
  (:report (lambda (c s)
             (format s "Cannot prove: ~S~@[ (~A)~]"
                     (proof-failure-goal c)
                     (metis-error-message c)))))

(define-condition plan-failure (metis-error)
  ((goal :initarg :goal :reader plan-failure-goal))
  (:report (lambda (c s)
             (format s "No plan for: ~S~@[ (~A)~]"
                     (plan-failure-goal c)
                     (metis-error-message c)))))

(define-condition tool-error (metis-error)
  ((tool :initarg :tool :reader tool-error-name))
  (:report (lambda (c s)
             (format s "Tool ~A failed: ~A"
                     (tool-error-name c)
                     (metis-error-message c)))))

(define-condition llm-error (metis-error) ())

(define-condition mind-not-booted (metis-error) ()
  (:default-initargs :message "Call (metis:boot) first."))
