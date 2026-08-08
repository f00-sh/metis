(in-package :cl-user)
(metis.symbols:register-symbol!
 :id "domain-kinship"
 :name "Kinship Domain Pack"
 :version "0.1.0"
 :description "Kinship facts/rules + couple-templates for hybrid accept gate."
 :capabilities (quote (:domain-pack :couple-templates))
 :priority 5
 :hooks (metis.symbols:define-symbol-hooks
          :activate (lambda (r)
                      (declare (ignore r))
                      (when (find-package :metis)
                        (let* ((root (asdf:system-source-directory :metis))
                               (pack (merge-pathnames
                                      "symbols/domain-kinship/pack.lisp" root))
                               (m (and (boundp 'metis:*mind*) metis:*mind*)))
                          (when (and m (probe-file pack))
                            (metis:domain-pack-load m pack))))
                      t)
          :deactivate (lambda (r) (declare (ignore r)) t)))
