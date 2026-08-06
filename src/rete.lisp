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
  (negations nil)   ; list of (not lit) with same alpha-rename as head
  (fired (make-hash-table :test #'equal)))

(defstruct (rete-network (:conc-name rn-))
  kb
  (alphas nil)
  (root nil)
  (prods nil)
  (next-id 0)
  (derived 0)
  (compiled-rules 0)
  (trace nil)
  (last-derived nil))   ; list of heads fired since last clear

(defun %rete-new-id (net)
  (incf (rn-next-id net)))

(defun %rete-find-or-make-alpha (net pattern)
  (or (find pattern (rn-alphas net) :key #'ra-pattern :test #'equal)
      (let ((a (make-rete-alpha :id (%rete-new-id net) :pattern pattern)))
        (push a (rn-alphas net))
        a)))

(defun rete-compile (kb &key (seed t) (fire t))
  "Compile KB rules into a RETE network.
   SEED: load current facts into alpha memories.
   FIRE: after seeding, run beta/production propagation (may derive)."
  (let* ((net (make-rete-network :kb kb))
         (root (make-rete-beta :id (%rete-new-id net) :left nil :right nil)))
    (setf (rn-root net) root)
    (setf (gethash "ROOT" (rb-tokens root)) +no-bindings+)
    (dolist (rule (kb-rules kb))
      (%rete-compile-rule net rule))
    (setf (rn-compiled-rules net) (length (kb-rules kb)))
    (when seed
      (dolist (f (kb-all-facts kb))
        (%rete-alpha-insert net f :propagate nil))
      (when fire
        (%rete-full-propagate net)))
    net))

(defun %rete-compile-rule (net rule)
  "Compile RULE: positive body lits → alpha/beta chain; (not …) kept on prod for NAF."
  (let* ((ren (rename-variables (cons (rule-head rule) (rule-body rule))))
         (head (car ren))
         (body (or (cdr ren) '((true))))
         (neg (remove-if-not
               (lambda (lit) (and (consp lit) (eq (car lit) 'not)))
               body))
         (pos (remove-if
               (lambda (lit) (and (consp lit) (eq (car lit) 'not)))
               body))
         (parent (rn-root net)))
    (when (null pos)
      (setf pos '((true))))
    (dolist (lit pos)
      (let* ((alpha (%rete-find-or-make-alpha net lit))
             (beta (make-rete-beta :id (%rete-new-id net)
                                   :left parent
                                   :right alpha)))
        (push beta (ra-betas alpha))
        (push beta (rb-children parent))
        (setf parent beta)))
    (let ((prod (make-rete-prod :rule rule
                                :head head
                                :beta parent
                                :negations neg)))
      (push prod (rb-productions parent))
      (push prod (rn-prods net))
      prod)))

(defun %rete-join-tokens (left-subst pattern fact)
  (unify (apply-subst pattern left-subst) fact left-subst))

(defun %rete-token-key (subst)
  (prin1-to-string (pretty-subst subst)))

(defun %rete-naf-ok-p (kb subst neg-lit)
  "Negation-as-failure for (not INNER) under SUBST against KB facts.
   Ground INNER: fail NAF if KB holds it.
   Open INNER: fail NAF if any KB fact unifies with INNER."
  (unless (and (consp neg-lit) (eq (car neg-lit) 'not))
    (return-from %rete-naf-ok-p t))
  (let ((inner (apply-subst (second neg-lit) subst)))
    (if (groundp inner)
        (not (kb-holds-p kb inner))
        (not (some (lambda (f)
                     (not (unify-fail-p (unify inner f subst))))
                   (kb-candidates kb inner))))))

(defun %rete-negations-satisfied-p (net subst negations)
  (every (lambda (n) (%rete-naf-ok-p (rn-kb net) subst n))
         negations))

(defun %rete-fire-productions (net beta)
  "Fire production nodes on BETA; enforce NAF on stored (not …) body lits."
  (let ((derived nil))
    (dolist (prod (rb-productions beta))
      (maphash
       (lambda (k subst)
         (declare (ignore k))
         (let* ((head (apply-subst (rp-head prod) subst))
                (fk (%rete-token-key subst)))
           (when (and (groundp head)
                      (not (kb-holds-p (rn-kb net) head))
                      (not (gethash fk (rp-fired prod)))
                      (%rete-negations-satisfied-p net subst
                                                   (rp-negations prod)))
             (setf (gethash fk (rp-fired prod)) t)
             (kb-assert (rn-kb net) head :support :rete)
             (incf (rn-derived net))
             (incf (rule-times-fired (rp-rule prod)))
             (push head derived)
             (push head (rn-last-derived net))
             (push (list :rete-fire (rule-name (rp-rule prod)) head)
                   (rn-trace net))
             ;; feed head as WME for multi-hop chain
             (%rete-alpha-insert net head :propagate t))))
       (rb-tokens beta)))
    derived))

(defun %rete-propagate-beta (net beta)
  "Recompute beta tokens from left ⋈ right; fire productions; cascade children."
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
    (setf derived (nconc derived (%rete-fire-productions net beta)))
    (dolist (child (rb-children beta))
      (setf derived (nconc derived (%rete-propagate-beta net child))))
    derived))

(defun %rete-full-propagate (net)
  (let ((derived nil))
    (dolist (alpha (rn-alphas net))
      (dolist (beta (ra-betas alpha))
        (setf derived (nconc derived (%rete-propagate-beta net beta)))))
    derived))

(defun %rete-alpha-insert (net fact &key (propagate t))
  "Insert FACT into matching alpha memories; optionally propagate."
  (let ((derived nil)
        (touched nil))
    (dolist (alpha (rn-alphas net))
      (when (not (unify-fail-p (unify (ra-pattern alpha) fact +no-bindings+)))
        (unless (gethash fact (ra-memory alpha))
          (setf (gethash fact (ra-memory alpha)) t)
          (push alpha touched))))
    (when propagate
      (dolist (alpha touched)
        (dolist (beta (ra-betas alpha))
          (setf derived (nconc derived (%rete-propagate-beta net beta))))))
    derived))

(defun rete-assert-wme (net fact)
  "Assert a working-memory element into the RETE network; return derived heads.
   Always re-propagates matching alphas (even if fact was already seeded)."
  (setf (rn-last-derived net) nil)
  (let ((matched nil)
        (derived nil))
    (dolist (alpha (rn-alphas net))
      (when (not (unify-fail-p (unify (ra-pattern alpha) fact +no-bindings+)))
        (setf (gethash fact (ra-memory alpha)) t)
        (push alpha matched)))
    (dolist (alpha matched)
      (dolist (beta (ra-betas alpha))
        (setf derived (nconc derived (%rete-propagate-beta net beta)))))
    (remove-duplicates
     (append derived (copy-list (rn-last-derived net)))
     :test #'equal)))

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
  "Compile (or reuse) RETE network and run full propagation.
   Re-seeds all KB facts into alpha memories so post-compile asserts are seen.
   Returns (values derived-facts network count)."
  (declare (ignore max-iterations))
  (let* ((net (or network (rete-compile kb :seed t :fire nil)))
         (before (kb-count-facts kb)))
    ;; Ensure every current KB fact is in alpha (handles asserts after compile).
    (dolist (f (kb-all-facts kb))
      (%rete-alpha-insert net f :propagate nil))
    (setf (rn-last-derived net) nil)
    (let ((derived (%rete-full-propagate net)))
      (values (remove-duplicates
               (append derived (copy-list (rn-last-derived net)))
               :test #'equal)
              net
              (- (kb-count-facts kb) before)))))

(defun forward-chain-rete (mind)
  "Public RETE forward-chain entry point. Returns list of newly derived facts
   (support :rete). Does not use agenda forward."
  (let* ((m (ensure-mind mind))
         (kb (mind-kb m))
         (before (let ((h (make-hash-table :test #'equal)))
                   (dolist (f (kb-all-facts kb)) (setf (gethash f h) t))
                   h)))
    (multiple-value-bind (derived net n)
        (run-forward-rete kb :network (mind-rete m))
      (declare (ignore n))
      (setf (mind-rete m) net)
      (let* ((new-facts (loop for f in (kb-all-facts kb)
                              unless (gethash f before)
                              collect f))
             (out (remove-duplicates (append derived new-facts) :test #'equal)))
        (mind-trace-push m :rete-forward (length out) (rn-compiled-rules net))
        (dolist (f out)
          (when (mind-tms m)
            (tms-assert (mind-tms m) f :informant :rete))
          (when (mind-beliefs m)
            (belief-set (mind-beliefs m) f 0.9)))
        out))))

(defun rete-assert-fact (mind fact)
  "Pure RETE path: kb-assert without agenda auto-forward, then rete-assert-wme.
   Returns list of facts derived solely by RETE."
  (let* ((m (ensure-mind mind))
         (kb (mind-kb m)))
    (kb-assert kb fact :support :asserted)
    (let ((net (or (mind-rete m)
                   (setf (mind-rete m)
                         (rete-compile kb :seed t :fire nil)))))
      (wm-add (mind-wm m) fact :source :rete-assert)
      (rete-assert-wme net fact))))
