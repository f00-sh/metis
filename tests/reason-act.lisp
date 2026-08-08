;;;; reason-act.lisp — assert / prove / bind / compose; no fact regurgitation
(in-package :metis/tests)

(def-suite :metis-reason-act
  :description "Use symbols: assert equality, prove/bind values, compose, anti-regurgitate")
(in-suite :metis-reason-act)

(defun %ra-has-eq (mind a b)
  (let ((A (intern (string-upcase (string a)) :metis))
        (B (if (numberp b) b (intern (string-upcase (string b)) :metis))))
    (or (find (list '= A B) (metis:facts mind) :test #'equal)
        (find (list 'metis::= A B) (metis:facts mind) :test #'equal)
        (some (lambda (f)
                (and (consp f) (= (length f) 3)
                     (string-equal (symbol-name (first f)) "=")
                     (equal (second f) A)
                     (equal (third f) B)))
              (metis:facts mind)))))

(test reason-act-assert-equality-durable
  "NL assert x = y leaves first-class (= X Y) in the mind."
  (metis:boot :bootstrap t :reset t)
  (let* ((s (metis:session-create :id "ra-assert" :boot nil))
         (out (metis:iface-turn s "x = y"))
         (reply (getf out :reply))
         (res (getf out :result))
         (m (metis::sess-mind s)))
    (is (stringp reply))
    (is (search "x = y" (string-downcase reply) :test #'char-equal))
    (is (member (getf res :source) '(:bind :prove :solve) :test #'eq))
    (is-true (%ra-has-eq m "x" "y")
             "must assert durable (= X Y) via shipped path")
    (is-true (or (%ra-has-eq m "y" "x")
                 (metis:reason-equality-facts m))
             "symmetry edge or equality facts present")))

(test reason-act-query-bind-not-regurgitate
  "After x = y, what is y → y = x via prove/bind — not math-knowledge dump."
  (metis:boot :bootstrap t :reset t)
  (let* ((s (metis:session-create :id "ra-query" :boot nil))
         (_ (metis:iface-turn s "x = y"))
         (out (metis:iface-turn s "what is y"))
         (reply (getf out :reply))
         (res (getf out :result))
         (src (getf res :source)))
    (declare (ignore _))
    (is (member src '(:prove :solve :bind) :test #'eq)
        (format nil "source was ~A" src))
    (is-false (eq src :math-knowledge))
    (is-false (search "from loaded math symbols" (string-downcase (or reply ""))
                      :test #'char-equal))
    (is (or (search "y = x" (string-downcase reply) :test #'char-equal)
            (search "x" (string-downcase reply) :test #'char-equal)))
    (is (consp (getf res :supporters)))))

(test reason-act-compose-value-chase
  "x = y then x = 2 then what is y → 2 with multi supporters."
  (metis:boot :bootstrap t :reset t)
  (let* ((s (metis:session-create :id "ra-compose" :boot nil)))
    (metis:iface-turn s "x = y")
    (metis:iface-turn s "x = 2")
    (let* ((out (metis:iface-turn s "what is y"))
           (reply (getf out :reply))
           (res (getf out :result))
           (sup (getf res :supporters)))
      (is (member (getf res :source) '(:prove :solve :bind) :test #'eq))
      (is (search "2" (or reply "") :test #'char-equal))
      (is (>= (length (remove-duplicates (or sup '()) :test #'equal)) 1))
      ;; composition: at least path involving equality + value (2 supporters ideal)
      (is (or (>= (length (or sup '())) 2)
              (and (search "2" reply) (getf res :success)))
          "compose path should carry supporters / success"))))

(test reason-act-multi-clause-single-turn
  "if x = 2 and y = x what is y → 2"
  (metis:boot :bootstrap t :reset t)
  (let* ((s (metis:session-create :id "ra-multi" :boot nil))
         (out (metis:iface-turn s "if x = 2 and y = x what is y"))
         (reply (getf out :reply))
         (res (getf out :result)))
    (is (member (getf res :source) '(:prove :solve :bind) :test #'eq))
    (is (search "2" (or reply "") :test #'char-equal))
    (is-true (getf res :success))
    (is (>= (length (or (getf res :supporters) '())) 2)
        "multi-clause must expose ≥2 supporters")))

(test reason-act-about-vs-empty-binding
  "About-Q uses knowledge facet; empty what is y is honest unknown not domain dump."
  (metis:boot :bootstrap t :reset t)
  (let* ((s (metis:session-create :id "ra-about" :boot nil))
         (m (metis::sess-mind s)))
    ;; seed a domain-def so regurgitation would have something to grab
    (metis:assert-fact m '(domain-def "math" "y-intercept" "the y where line crosses axis")
                       :forward nil)
    (ignore-errors (metis::symbol-capability-register! :math "math"))
    (let* ((about (metis:iface-turn s "what is a limit?"))
           (empty (metis:iface-turn s "what is y"))
           (ar (getf about :result))
           (er (getf empty :result))
           (ereply (getf empty :reply)))
      ;; about may be math-knowledge or concept/unknown — not bind chase for "limit"
      (is-false (and (eq (getf ar :source) :bind)
                     (search "limit = " (string-downcase (or (getf about :reply) "")))))
      (is-true (or (getf er :unknown)
                   (search "no binding" (string-downcase (or ereply ""))
                           :test #'char-equal))
               "empty binding must be honest unknown, not y=y / dump")
      (is-false (string-equal (string-trim '(#\Space) (or ereply "")) "y = y"))
      (is-false (search "from loaded math symbols" (string-downcase (or ereply ""))
                        :test #'char-equal))
      (is-false (search "y-intercept" (string-downcase (or ereply ""))
                        :test #'char-equal)))))

(test reason-act-learn-on-success-not-retrieval
  "Reasoned success encodes episode; knowledge dump does not claim skill learn."
  (metis:boot :bootstrap t :reset t)
  (metis:hippocampus-clear!)
  (let* ((s (metis:session-create :id "ra-learn" :boot nil))
         (before (metis:hippocampus-size)))
    (metis:iface-turn s "x = y")
    (let* ((q (metis:iface-turn s "what is y"))
           (res (getf q :result))
           (learned (getf res :learned)))
      (is (member (getf res :source) '(:prove :solve :bind) :test #'eq))
      (is (or (consp learned) (getf learned :episode)
              (> (metis:hippocampus-size) before))
          "reasoned success should encode episode / learned payload")
      ;; knowledge path must not set skill-learned
      (when (eq (getf res :source) :math-knowledge)
        (is-false (getf learned :skill-learned))))))

(test reason-act-extractive-still-wins
  "Document Q&A still extractive (penguin)."
  (metis:boot :bootstrap t :reset t)
  (metis:nn-enable-path metis:*mind*)
  (let* ((dir (uiop:ensure-directory-pathname
               (merge-pathnames "metis-ra-peng/" (uiop:temporary-directory))))
         (s (metis:session-create :id "ra-peng" :boot nil)))
    (ensure-directories-exist dir)
    (with-open-file (out (merge-pathnames "p.txt" dir)
                         :direction :output :if-exists :supersede)
      (write-string "Penguins are flightless birds that swim in cold seas." out))
    (metis:session-ingest-path s dir :train nil :async nil)
    (let* ((out (metis:iface-turn s "tell me about penguins"))
           (reply (getf out :reply)))
      (is (search "penguin" (string-downcase (or reply "")) :test #'char-equal)))
    (ignore-errors (metis:brain-stop!))))

(test reason-act-api-parse-and-prove-entry
  "Shipped parse + reason-act-answer / prove-value entry points."
  (metis:boot :bootstrap t :reset t)
  (let ((a (metis:parse-reason-act "x equals y"))
        (b (metis:parse-reason-act "what is y"))
        (c (metis:parse-reason-act "what is a limit?")))
    (is (eq (getf a :act) :assert))
    (is (eq (getf b :act) :query))
    (is-false c "about-question must not parse as value-of"))
  (metis:reason-assert-equality! metis:*mind* "a" "b")
  (let ((r (metis:reason-prove-value metis:*mind* "a")))
    (is (consp r))
    (is (member (getf r :source) '(:prove :bind :solve) :test #'eq))))

(test reason-act-alternate-assert-phrasing
  "let x = y and set x to 2 work via iface-turn."
  (metis:boot :bootstrap t :reset t)
  (let ((s (metis:session-create :id "ra-alt" :boot nil)))
    (metis:iface-turn s "let x = y")
    (is-true (%ra-has-eq (metis::sess-mind s) "x" "y"))
    (metis:iface-turn s "set x to 5")
    (let* ((out (metis:iface-turn s "value of y"))
           (reply (getf out :reply)))
      (is (search "5" (or reply ""))))))
