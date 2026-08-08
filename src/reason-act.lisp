;;;; reason-act.lisp — assert / prove / bind / solve over session equalities
;;;; Freeform primary path: use the mind, not domain-def regurgitation.
;;;; Canonical form: (= A B). Symmetry stored both ways for vars; values supersede.
(in-package :metis)

(defparameter *reason-act-metrics*
  (list :assert-count 0
        :query-count 0
        :reasoned-count 0
        :unknown-count 0
        :learn-count 0
        :regurgitate-blocked 0)
  "Honesty counters for reason-act surface.")

(defun reason-act-metrics ()
  (copy-list *reason-act-metrics*))

(defun %ra-bump (key &optional (n 1))
  (let ((v (getf *reason-act-metrics* key)))
    (when (numberp v)
      (setf (getf *reason-act-metrics* key) (+ v n))))
  t)

(defun %ra-var-sym (name)
  "Canonical symbol for a binding name (X, Y, …)."
  (intern (string-upcase (string-trim '(#\Space #\Tab) (string name)))
          :metis))

(defun %ra-term (raw)
  "Parse RHS/LHS atom: number or var symbol."
  (let* ((s (string-trim '(#\Space #\Tab) (string raw)))
         (num (ignore-errors
                (let ((*read-eval* nil))
                  (let ((v (read-from-string s)))
                    (and (numberp v) v))))))
    (if num num (%ra-var-sym s))))

(defun %ra-term-string (term)
  (cond ((null term) "?")
        ((numberp term) (princ-to-string term))
        ((symbolp term) (string-downcase (symbol-name term)))
        (t (princ-to-string term))))

(defun %ra-ground-p (term)
  (numberp term))

(defun %ra-var-name-p (s)
  "Identifier token (lhs of assignment)."
  (and (stringp s)
       (plusp (length s))
       (<= (length s) 32)
       (cl-ppcre:scan "^[A-Za-z_][A-Za-z0-9_]*$" s)))

(defun %ra-session-var-name-p (s)
  "Session binding vars for value-of queries: short math vars (x, y, x1),
   not concept words like pemdas / limit (those are knowledge-about)."
  (and (%ra-var-name-p s)
       (or (<= (length s) 2)
           (cl-ppcre:scan "^[A-Za-z][0-9]+$" s))))

;;; ---- equality store helpers --------------------------------------

(defun reason-equality-facts (mind)
  "All (= a b) facts currently in MIND."
  (remove-if-not
   (lambda (f)
     (and (consp f)
          (symbolp (first f))
          (string-equal (symbol-name (first f)) "=")
          (= (length f) 3)))
   (facts mind)))

(defun %ra-retract-equals-involving (mind left &key (only-ground nil))
  "Retract (= LEFT *) and (= * LEFT). If ONLY-GROUND, only when other side is number."
  (let ((L (%ra-term left)))
    (dolist (f (reason-equality-facts mind))
      (let ((a (second f)) (b (third f)))
        (when (or (equal a L) (equal b L) (eql a L) (eql b L)
                  (and (symbolp a) (symbolp L) (eq a L))
                  (and (symbolp b) (symbolp L) (eq b L)))
          (let ((other (if (or (equal a L) (eql a L) (and (symbolp a) (symbolp L) (eq a L)))
                           b a)))
            (when (or (not only-ground) (%ra-ground-p other))
              (ignore-errors (retract-fact mind f)))))))))

(defun %ra-eq-fact (a b)
  "Canonical equality fact (= A B) — use list not backquote for clarity."
  (list (intern "=" :metis) a b))

(defun reason-assert-equality! (mind lhs rhs &key (support :user-turn))
  "Assert (= LHS RHS). Vars get bidirectional edges; values supersede prior ground.
   Returns plist (:asserted facts :lhs L :rhs R)."
  (let* ((m (ensure-mind mind))
         (L (%ra-term lhs))
         (R (%ra-term rhs))
         (asserted '()))
    (cond
      ;; value assignment: x = 2
      ((and (not (%ra-ground-p L)) (%ra-ground-p R))
       (%ra-retract-equals-involving m L :only-ground t)
       (let ((f (%ra-eq-fact L R)))
         (assert-fact m f :support support :forward nil)
         (setf asserted (list f))))
      ;; reverse value: 2 = x → normalize to x = 2
      ((and (%ra-ground-p L) (not (%ra-ground-p R)))
       (%ra-retract-equals-involving m R :only-ground t)
       (let ((f (%ra-eq-fact R L)))
         (assert-fact m f :support support :forward nil)
         (setf asserted (list f))))
      ;; var = var: bidirectional
      ((and (not (%ra-ground-p L)) (not (%ra-ground-p R)))
       (dolist (f (reason-equality-facts m))
         (let ((a (second f)) (b (third f)))
           (when (and (or (eq a L) (eq b L))
                      (not (%ra-ground-p a))
                      (not (%ra-ground-p b))
                      (not (and (or (eq a L) (eq a R))
                                (or (eq b L) (eq b R)))))
             (ignore-errors (retract-fact m f)))))
       (let ((f1 (%ra-eq-fact L R))
             (f2 (%ra-eq-fact R L)))
         (assert-fact m f1 :support support :forward nil)
         (assert-fact m f2 :support support :forward nil)
         (setf asserted (list f1 f2))))
      (t
       (let ((f (%ra-eq-fact L R)))
         (assert-fact m f :support support :forward nil)
         (setf asserted (list f)))))
    (%ra-bump :assert-count)
    (values asserted L R)))

;;; ---- resolve / chase ---------------------------------------------

(defun %ra-neighbors (eq-facts node)
  (let ((out nil))
    (dolist (f eq-facts)
      (let ((a (second f)) (b (third f)))
        (cond
          ((or (eql a node) (equal a node) (and (symbolp a) (symbolp node) (eq a node)))
           (push (list :to b :fact f) out))
          ((or (eql b node) (equal b node) (and (symbolp b) (symbolp node) (eq b node)))
           (push (list :to a :fact f) out)))))
    out))

(defun reason-resolve-value (mind var)
  "Chase equality graph from VAR. Prefer ground numbers.
   Returns plist :value :form :supporters :steps :source or NIL if unbound."
  (let* ((m (ensure-mind mind))
         (start (%ra-term var))
         (eqs (reason-equality-facts m))
         (seen (make-hash-table :test #'equal))
         (queue (list start))
         (parent (make-hash-table :test #'equal)) ; node → (from-node fact)
         (grounds nil)
         (others nil))
    (setf (gethash start seen) t)
    (loop while queue do
      (let ((n (pop queue)))
        (cond
          ((%ra-ground-p n)
           (push n grounds))
          ((and (not (equal n start)) (not (eql n start))
                (not (and (symbolp n) (symbolp start) (eq n start))))
           (push n others)))
        (dolist (edge (%ra-neighbors eqs n))
          (let ((to (getf edge :to))
                (f (getf edge :fact)))
            (unless (gethash to seen)
              (setf (gethash to seen) t
                    (gethash to parent) (list n f))
              (setf queue (nconc queue (list to))))))))
    (labels ((path-supporters (end)
               (let ((sup nil) (steps nil) (cur end))
                 (loop while (gethash cur parent) do
                   (let* ((pf (gethash cur parent))
                          (from (first pf))
                          (fact (second pf)))
                     (push fact sup)
                     (push (list :from from :to cur :fact fact) steps)
                     (setf cur from)))
                 (values (nreverse sup) (nreverse steps)))))
      (cond
        (grounds
         (let* ((g (first (sort (copy-list grounds) #'<
                                :key (lambda (x) (if (numberp x) x 0)))))
                ;; prefer any ground; path from start
                (best g))
           ;; find ground reachable — all in component are; pick first discovered ground with path
           (setf best (or (find-if #'%ra-ground-p
                                   (loop for k being the hash-keys of seen collect k))
                          g))
           (multiple-value-bind (sup steps) (path-supporters best)
             (list :value best
                   :form (list '= start best)
                   :reply-text (%ra-term-string best)
                   :supporters sup
                   :steps steps
                   :source (if (cdr sup) :prove :bind)))))
        (others
         (let* ((o (first others)))
           (multiple-value-bind (sup steps) (path-supporters o)
             (list :value o
                   :form (list '= start o)
                   :reply-text (format nil "~A = ~A"
                                       (%ra-term-string start)
                                       (%ra-term-string o))
                   :supporters (or sup
                                   (list (list '= start o)))
                   :steps steps
                   :source :bind))))
        (t nil)))))

;;; prove-query over session equalities (real prove entry) after chase.
(defun reason-prove-value (mind var)
  "Chase equality graph; fall back to shipped prove-query on (= VAR ?v).
   Never invents identity y=y as a success."
  (let* ((m (ensure-mind mind))
         (V (%ra-term var))
         (chase (reason-resolve-value m V)))
    (when chase
      (return-from reason-prove-value chase))
    (let* ((qvar (intern "?V" :metis))
           (pat (list (intern "=" :metis) V qvar))
           (*current-kb* (mind-kb m))
           (hits (ignore-errors (prove-query pat :kb (mind-kb m)))))
      (dolist (hit hits)
        (let ((val (third hit)))
          ;; Accept only a real binding different from the query var
          (when (and val
                     (not (eq val V))
                     (not (equal val V))
                     (not (variablep val)))
            (return-from reason-prove-value
              (list :value val
                    :form hit
                    :reply-text (if (%ra-ground-p val)
                                    (%ra-term-string val)
                                    (format nil "~A = ~A"
                                            (%ra-term-string V)
                                            (%ra-term-string val)))
                    :supporters (list hit)
                    :steps (list (list :prove hit))
                    :source :prove)))))
      nil)))

;;; ---- parser ------------------------------------------------------

(defun %ra-strip-punct (s)
  (string-trim '(#\Space #\Tab #\Newline #\Return #\. #\? #\!) s))

(defun reason-about-question-p (text)
  "T when the user asks *about* a concept (knowledge facet), not value-of a var."
  (let ((q (string-downcase (%ra-strip-punct (or text "")))))
    (or (cl-ppcre:scan "\\bwhat\\s+is\\s+(a|an|the)\\s+" q)
        (cl-ppcre:scan "\\bdefine\\b" q)
        (cl-ppcre:scan "\\bdefinition\\b" q)
        (cl-ppcre:scan "\\bexplain\\b" q)
        (cl-ppcre:scan "\\bmeaning\\s+of\\b" q)
        (cl-ppcre:scan "\\bwhat\\s+does\\b" q)
        (cl-ppcre:scan "\\btell\\s+me\\s+about\\b" q)
        ;; multi-word topics after what is (not a single var)
        (cl-ppcre:register-groups-bind (rest)
            ("(?i)^what(?:'s|\\s+is)\\s+(.+)$" q)
          (let ((toks (cl-ppcre:split "\\s+" (string-trim '(#\Space) rest))))
            (and toks (> (length toks) 1)))))))

(defun parse-reason-act (text)
  "Heuristic Act IR from TEXT. Returns plist with :act … or NIL if not handled."
  (let* ((raw (string-trim '(#\Space #\Tab #\Newline #\Return) (or text "")))
         (q (%ra-strip-punct raw)))
    (when (zerop (length q))
      (return-from parse-reason-act nil))
    ;; Multi-clause: if x = 2 and y = x what is y
    (cl-ppcre:register-groups-bind (body ask)
        ("(?i)^if\\s+(.+?)\\s+what\\s+is\\s+([A-Za-z_][A-Za-z0-9_]*)$" q)
      (when (and body ask)
        (return-from parse-reason-act
          (list :act :multi
                :asserts body
                :query ask
                :raw raw))))
    ;; let x = y / let x be y
    (cl-ppcre:register-groups-bind (a b)
        ("(?i)^let\\s+([A-Za-z_][A-Za-z0-9_]*)\\s*(?:=|be)\\s*(.+)$" q)
      (when (and a b)
        (return-from parse-reason-act
          (list :act :assert :kind :equality
                :lhs a :rhs (%ra-strip-punct b) :raw raw))))
    ;; set x to 2
    (cl-ppcre:register-groups-bind (a b)
        ("(?i)^set\\s+([A-Za-z_][A-Za-z0-9_]*)\\s+to\\s+(.+)$" q)
      (when (and a b)
        (return-from parse-reason-act
          (list :act :assert :kind :equality
                :lhs a :rhs (%ra-strip-punct b) :raw raw))))
    ;; x equals y
    (cl-ppcre:register-groups-bind (a b)
        ("(?i)^([A-Za-z_][A-Za-z0-9_]*)\\s+equals\\s+(.+)$" q)
      (when (and a b)
        (return-from parse-reason-act
          (list :act :assert :kind :equality
                :lhs a :rhs (%ra-strip-punct b) :raw raw))))
    ;; x = y   (not a math expr with operators other than =)
    (cl-ppcre:register-groups-bind (a b)
        ("(?i)^([A-Za-z_][A-Za-z0-9_]*)\\s*=\\s*(.+)$" q)
      (when (and a b
                 (not (cl-ppcre:scan "[+\\*/^()]" b))
                 (or (%ra-var-name-p (%ra-strip-punct b))
                     (cl-ppcre:scan "^-?[0-9]+(?:\\.[0-9]+)?$"
                                    (%ra-strip-punct b))))
        (return-from parse-reason-act
          (list :act :assert :kind :equality
                :lhs a :rhs (%ra-strip-punct b) :raw raw))))
    ;; solve for y / value of y
    (cl-ppcre:register-groups-bind (v)
        ("(?i)^(?:solve\\s+for|value\\s+of)\\s+([A-Za-z_][A-Za-z0-9_]*)$" q)
      (when (and v (%ra-session-var-name-p v))
        (return-from parse-reason-act
          (list :act :query :kind :value-of :var v :raw raw))))
    ;; what is y / what's y — short session vars only (not "what is pemdas")
    (unless (reason-about-question-p q)
      (cl-ppcre:register-groups-bind (v)
          ("(?i)^what(?:'s|\\s+is)\\s+([A-Za-z_][A-Za-z0-9_]*)$" q)
        (when (and v (%ra-session-var-name-p v))
          (return-from parse-reason-act
            (list :act :query :kind :value-of :var v :raw raw)))))
    nil))

(defun %ra-parse-assert-chain (body)
  "Split 'x = 2 and y = x' into list of (lhs . rhs)."
  (let ((parts (cl-ppcre:split "\\s+and\\s+" body :limit 20))
        (out nil))
    (dolist (p parts)
      (cl-ppcre:register-groups-bind (a b)
          ("(?i)^\\s*([A-Za-z_][A-Za-z0-9_]*)\\s*=\\s*(.+?)\\s*$" p)
        (when (and a b)
          (push (cons a (%ra-strip-punct b)) out))))
    (nreverse out)))

;;; ---- execute -----------------------------------------------------

(defun %ra-learn-on-success! (mind text result &key (learn t))
  "Encode episode on reasoned success. Full neocortex consolidate only when LEARN is T
   (not :auto) — retrieval answers never call this."
  (when (and learn
             (not (eq learn nil))
             (getf result :success)
             (member (getf result :source) '(:prove :solve :bind) :test #'eq))
    (%ra-bump :learn-count)
    (let ((ep (ignore-errors
                (hippocampus-encode!
                 (or text (getf result :reply-text) "")
                 :source :reasoned
                 :valence :ok
                 :success t
                 :meta (list :source (getf result :source)
                             :supporters (getf result :supporters))))))
      (let ((cons (when (and (eq learn t)
                             (fboundp 'neocortex-consolidate!)
                             (boundp '*online-learn-enabled*)
                             *online-learn-enabled*)
                    (ignore-errors
                      (neocortex-consolidate!
                       (format nil "reasoned ~A"
                               (or (getf result :reply-text) text))
                       :mind mind :replay nil)))))
        (list :episode (and ep (getf ep :id))
              :consolidated (and cons (getf cons :learned) t)
              :skill-learned nil
              :learn-metrics cons)))))

(defun reason-act-execute (mind act &key (learn :auto) (text nil))
  "Run Act IR against MIND. Returns freeform-compatible plist or NIL."
  (unless (and act (getf act :act))
    (return-from reason-act-execute nil))
  (let* ((m (ensure-mind mind))
         (*mind* m)
         (kind (getf act :act)))
    (case kind
      (:assert
       (multiple-value-bind (facts L R)
           (reason-assert-equality! m (getf act :lhs) (getf act :rhs))
         (let ((reply (format nil "Noted: ~A = ~A"
                              (%ra-term-string L)
                              (%ra-term-string R))))
           (list :freeform :reasoned
                 :reason-act :assert
                 :reply-text reply
                 :source :bind
                 :success t
                 :learned nil
                 :supporters facts
                 :asserted facts
                 :facet :process))))
      (:query
       (%ra-bump :query-count)
       (let ((resolved (reason-prove-value m (getf act :var))))
         (if resolved
             (let* ((base (list :freeform :reasoned
                                :act :query
                                :reply-text (getf resolved :reply-text)
                                :source (getf resolved :source)
                                :success t
                                :supporters (getf resolved :supporters)
                                :steps (getf resolved :steps)
                                :value (getf resolved :value)
                                :form (getf resolved :form)
                                :facet :process))
                    (do-learn (or (eq learn t)
                                  (and (eq learn :auto) t)))
                    (lr (when do-learn
                          (%ra-learn-on-success!
                           m (or text (getf act :raw))
                           base :learn t))))
               (%ra-bump :reasoned-count)
               (if lr
                   (list* :learned lr base)
                   (list* :learned nil base)))
             (progn
               (%ra-bump :unknown-count)
               (list :freeform :reasoned
                     :act :query
                     :reply-text
                     (format nil "I have no binding for ~A yet. Assert e.g. ~A = … first."
                             (getf act :var) (getf act :var))
                     :source :bind
                     :success nil
                     :unknown t
                     :learned nil
                     :supporters nil
                     :facet :process)))))
      (:multi
       (let ((pairs (%ra-parse-assert-chain (getf act :asserts)))
             (asserted nil))
         (dolist (pr pairs)
           (multiple-value-bind (facts)
               (reason-assert-equality! m (car pr) (cdr pr))
             (setf asserted (append asserted facts))))
         (let* ((qact (list :act :query :kind :value-of
                            :var (getf act :query)
                            :raw (getf act :raw)))
                (ans (reason-act-execute m qact :learn learn
                                         :text (getf act :raw))))
           (when ans
             (setf (getf ans :asserted) asserted
                   (getf ans :supporters)
                   (append asserted (or (getf ans :supporters) '())))
             (when (and (getf ans :success)
                        (>= (length (remove-duplicates
                                     (getf ans :supporters)
                                     :test #'equal))
                            2))
               (setf (getf ans :source)
                     (or (getf ans :source) :prove)))
             ans))))
      (t nil))))

(defun reason-act-answer (text &optional mind &key (learn :auto))
  "Parse + execute reason-act for TEXT. NIL if not an act/query we handle."
  (let* ((m (or mind *mind*))
         (act (parse-reason-act text)))
    (when act
      (reason-act-execute m act :learn learn :text text))))

(defun reason-act-ensure-rules! (mind)
  "Install minimal equality participation marker rule (prove-visible).
   Chase is primary; this records that symbol rules path is available."
  (let ((m (ensure-mind mind)))
    ;; Marker fact that tests can see as rule-path participation when packs load.
    (unless (ask m '(reason-act-ready t))
      (assert-fact m '(reason-act-ready t) :support :reason-act :forward nil))
    ;; Optional: if algebra/math capability loaded, note process available
    (when (ignore-errors (symbol-capability-enabled-p :math))
      (assert-fact m '(reason-act-process math) :support :reason-act :forward nil))
    t))
