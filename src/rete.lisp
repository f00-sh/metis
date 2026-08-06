;;;; rete.lisp — RETE-compiled forward inference (alpha + beta joins)
(in-package :metis)

(defstruct (rete-alpha (:conc-name ra-))
  id
  pattern
  (memory (make-hash-table :test #'equal)) ; fact -> t
  (betas nil))                             ; beta nodes using this alpha on right

(defstruct (rete-beta (:conc-name rb-))
  id
  left                 ; nil = dummy root, else rete-beta
  right                ; rete-alpha
  (tokens (make-hash-table :test #'equal)) ; key -> subst
  (children nil)       ; child betas
  (productions nil))   ; rete-prod list

(defstruct (rete-prod (:conc-name rp-))
  rule
  head
  beta
  (fired (make-hash-table :test #'equal)))

(defstruct (rete-network (:conc-name rn-))
  kb
  (alphas nil)
  (root nil)
  (prods nil)
  (next-id 0)
  (derived 0)
  (compiled-rules 0)
  (trace nil))

(defun %rete-new-id (net)
  (incf (rn-next-id net)))

(defun %rete-find-or-make-alpha (net pattern)
  (or (find pattern (rn-alphas net) :key #'ra-pattern :test #'equal)
      (let ((a (make-rete-alpha :id (%rete-new-id net) :pattern pattern)))
        (push a (rn-alphas net))
        a)))

(defun rete-compile (kb)
  "Compile KB rules into a RETE network and seed with current facts."
  (let* ((net (make-rete-network :kb kb))
         (root (make-rete-beta :id (%rete-new-id net) :left nil :right nil)))
    (setf (rn-root net) root)
    ;; root has empty token
    (setf (gethash "ROOT" (rb-tokens root)) +no-bindings+)
    (dolist (rule (kb-rules kb))
      (%rete-compile-rule net rule))
    (setf (rn-compiled-rules net) (length (kb-rules kb)))
    (dolist (f (kb-all-facts kb))
      (%rete-alpha-assert net f))
    net))

(defun %rete-compile-rule (net rule)
  (let* ((ren (rename-variables (cons (rule-head rule) (rule-body rule))))
         (head (car ren))
         (body (or (cdr ren) '((true))))
         (parent (rn-root net)))
    (dolist (lit body)
      (let* ((alpha (%rete-find-or-make-alpha net lit))
             (beta (make-rete-beta :id (%rete-new-id net)
                                   :left parent
                                   :right alpha)))
        (push beta (ra-betas alpha))
        (push beta (rb-children parent))
        (setf parent beta)))
    (let ((prod (make-rete-prod :rule rule :head head :beta parent)))
      (push prod (rb-productions parent))
      (push prod (rn-prods net))
      prod)))

(defun %rete-join-tokens (left-subst pattern fact)
  (unify (apply-subst pattern left-subst) fact left-subst))

(defun %rete-token-key (subst)
  (prin1-to-string (pretty-subst subst)))

(defun %rete-propagate-beta (net beta)
  "Recompute beta tokens from left tokens ⋈ right alpha; fire productions."
  (let ((new (make-hash-table :test #'equal))
        (derived nil)
        (left (rb-left beta))
        (alpha (rb-right beta)))
    (when (and left alpha)
      (maphash
       (lambda (lk lsubst)
         (declare (ignore lk))
         (maphash
          (lambda (fact present)
            (declare (ignore present))
            (let ((s2 (%rete-join-tokens lsubst (ra-pattern alpha) fact)))
              (unless (unify-fail-p s2)
                (setf (gethash (%rete-token-key s2) new) s2))))
          (ra-memory alpha)))
       (rb-tokens left)))
    (setf (rb-tokens beta) new)
    ;; children
    (dolist (child (rb-children beta))
      (setf derived (nconc derived (%rete-propagate-beta net child))))
    ;; productions
    (dolist (prod (rb-productions beta))
      (maphash
       (lambda (k subst)
         (declare (ignore k))
         (let* ((head (apply-subst (rp-head prod) subst))
                (fk (%rete-token-key subst)))
           (when (and (groundp head)
                      (not (kb-holds-p (rn-kb net) head))
                      (not (gethash fk (rp-fired prod))))
             (setf (gethash fk (rp-fired prod)) t)
             (kb-assert (rn-kb net) head :support :rete)
             (incf (rn-derived net))
             (incf (rule-times-fired (rp-rule prod)))
             (push head derived)
             (push (list :rete-fire (rule-name (rp-rule prod)) head)
                   (rn-trace net))
             ;; recursive WME assert for chaining
             (%rete-alpha-assert net head))))
       (rb-tokens beta)))
    derived))

(defun %rete-alpha-assert (net fact)
  (let ((derived nil))
    (dolist (alpha (rn-alphas net))
      (when (not (unify-fail-p (unify (ra-pattern alpha) fact +no-bindings+)))
        (unless (gethash fact (ra-memory alpha))
          (setf (gethash fact (ra-memory alpha)) t)
          (dolist (beta (ra-betas alpha))
            (setf derived (nconc derived (%rete-propagate-beta net beta)))))))
    derived))

(defun rete-assert-wme (net fact)
  "Assert a working-memory element into the RETE network."
  (%rete-alpha-assert net fact))

(defun rete-retract-wme (net fact)
  "Retract WME and rejoin affected beta memories."
  (let ((derived nil))
    (dolist (alpha (rn-alphas net))
      (when (gethash fact (ra-memory alpha))
        (remhash fact (ra-memory alpha))
        (dolist (beta (ra-betas alpha))
          (setf derived (nconc derived (%rete-propagate-beta net beta))))))
    derived))

(defun run-forward-rete (kb &key (network nil) (max-iterations nil))
  "Compile (or reuse) RETE network and run to quiescence.
   Returns (values derived-facts network)."
  (declare (ignore max-iterations))
  (let* ((before (kb-count-facts kb))
         (net (or network (rete-compile kb)))
         ;; force full rejoin/fire pass for rules needing multi-hop
         (extra nil))
    (dolist (prod (rn-prods net))
      (setf extra (nconc extra (%rete-propagate-beta net (rp-beta prod)))))
    (let ((after (kb-count-facts kb)))
      (values (or extra
                  (when (> after before)
                    (list :derived-count (- after before))))
              net
              (- after before)))))

(defun forward-chain-rete (mind)
  "Public RETE forward-chain entry point."
  (let ((m (ensure-mind mind)))
    (multiple-value-bind (derived net n)
        (run-forward-rete (mind-kb m) :network (mind-rete m))
      (declare (ignore derived))
      (setf (mind-rete m) net)
      (mind-trace-push m :rete-forward n (rn-compiled-rules net))
      (let ((out nil))
        ;; collect recently derived by comparing? return count list via scan
        (dolist (f (kb-all-facts (mind-kb m)))
          (let ((meta (gethash f (kb-facts (mind-kb m)))))
            (when (and meta (eq (fm-support meta) :rete))
              (push f out)
              (when (mind-tms m)
                (tms-assert (mind-tms m) f :informant :rete))
              (when (mind-beliefs m)
                (belief-set (mind-beliefs m) f 0.9)))))
        out))))
