;;;; chat-spine.lisp — house base LM freeform + symbol model packages
(in-package :metis/tests)

(def-suite :metis-chat-spine
  :description "House chat spine; symbols as model conditioners; no external LLM freeform")
(in-suite :metis-chat-spine)

(defun %cs-open-residual (text)
  "Open residual freeform unlikely to hit reason-act/math/extractive/about."
  text)

(test chat-spine-house-generate-residual
  "Residual freeform uses in-process house-chat path (not :llm / not math-knowledge dump)."
  (metis:boot :bootstrap t :reset t)
  (metis:nn-enable-path metis:*mind*)
  (metis:symbol-model-clear!)
  (let* ((ens (metis:house-chat-ensure!
               :force t
               :corpus (format nil "~{~A ~}"
                               (loop repeat 40
                                     collect "hello metis house chat spine pure common lisp generate."))
               :epochs 2 :hidden 32 :seq-len 24 :depth 2 :max-batches 30))
         (s (metis:session-create :id "cs-gen" :boot nil))
         (q (%cs-open-residual "please invent a short greeting about pure lisp minds"))
         (out (metis:iface-turn s q))
         (res (getf out :result))
         (src (getf res :source)))
    (is-true (getf ens :ready))
    (is-true (metis:house-chat-available-p))
    (is (eq src :house-chat)
        (format nil "expected :house-chat got ~A full=~S" src res))
    (is-false (eq src :llm))
    (is-false (eq src :math-knowledge))
    (is-false (search "from loaded math symbols"
                      (string-downcase (or (getf out :reply) ""))
                      :test #'char-equal))
    (is (stringp (getf out :reply)))
    (is (plusp (length (getf out :reply))))
    (is (or (getf res :house-spine) (eq (getf res :freeform) :house-chat)))))

(test chat-spine-symbol-model-package-condition
  "Attach domain model package → conditions house generate; detach removes it."
  (metis:boot :bootstrap t :reset t)
  (metis:nn-enable-path metis:*mind*)
  (metis:symbol-model-clear!)
  (metis:house-chat-ensure!
   :force t
   :corpus "adapter test corpus for symbol model package conditioning. "
   :epochs 1 :hidden 24 :seq-len 16 :depth 2 :max-batches 15)
  (is-false (metis:symbol-model-active "demo-calc-adapter"))
  (let ((att (metis:symbol-model-attach!
              "demo-calc-adapter"
              :prompt-prefix "[demo-calc weights sieve ACTIVE]"
              :kind :weights
              :meta (list :fixture t))))
    (is-true (getf att :active))
    (is-true (metis:symbol-model-active "demo-calc-adapter"))
    (let* ((g (metis:house-chat-generate
               "say hello about rates of change"
               :mind metis:*mind* :ensure nil :length 40))
           (conds (getf g :conditioned-by))
           (pref (getf g :condition-prefix)))
      (is (eq (getf g :source) :house-chat))
      (is (member "demo-calc-adapter" conds :test #'string-equal))
      (is (search "demo-calc" (string-downcase (or pref "")) :test #'char-equal)))
    (metis:symbol-model-detach! "demo-calc-adapter")
    (is-false (metis:symbol-model-active "demo-calc-adapter"))
    (let ((g2 (metis:house-chat-generate "say hello again"
                                         :mind metis:*mind* :ensure nil :length 20)))
      (is (eq (getf g2 :source) :house-chat))
      (is-false (member "demo-calc-adapter" (getf g2 :conditioned-by)
                        :test #'string-equal)))))

(test chat-spine-not-rag-first-open-chat
  "Residual open chat is house-spine; about-Q with DOMAIN-DEF uses knowledge facet."
  (metis:boot :bootstrap t :reset t)
  (metis:nn-enable-path metis:*mind*)
  (metis:symbol-model-clear!)
  (metis:assert-fact metis:*mind*
                     '(domain-def "math" "pemdas" "order of operations trivia dump")
                     :forward nil)
  (metis:assert-fact metis:*mind*
                     '(domain-def "calculus" "limit"
                       "value a function approaches as input approaches a point")
                     :forward nil)
  (ignore-errors (metis::symbol-capability-register! :math "math"))
  (metis:house-chat-ensure!
   :force t
   :corpus "open residual chat about the weather of minds. "
   :epochs 1 :hidden 24 :seq-len 16 :depth 2 :max-batches 12)
  (let* ((s (metis:session-create :id "cs-rag" :boot nil))
         (out (metis:iface-turn s "share a brief thought about creativity"))
         (src (getf (getf out :result) :source))
         (reply (string-downcase (or (getf out :reply) ""))))
    (is (eq src :house-chat)
        (format nil "open residual must be house-chat not ~A" src))
    (is-false (search "from loaded math symbols" reply :test #'char-equal))
    (is-false (search "order of operations trivia dump" reply :test #'char-equal)))
  ;; Dual-facet: about-Q with DOMAIN-DEF present → knowledge, not house residual
  (let* ((s2 (metis:session-create :id "cs-about" :boot nil))
         (about (metis:iface-turn s2 "what is a limit?"))
         (asrc (getf (getf about :result) :source))
         (areply (string-downcase (or (getf about :reply) "")))
         (direct (metis:symbol-math-knowledge-answer "what is a limit?"
                                                     (metis::sess-mind s2))))
    (is (eq (getf direct :source) :math-knowledge)
        "shipped symbol-math-knowledge-answer must hit DOMAIN-DEF limit")
    (is (search "limit" (string-downcase (or (getf direct :reply-text) ""))
                :test #'char-equal))
    (is (eq asrc :math-knowledge)
        (format nil "about-Q iface must be :math-knowledge got ~A" asrc))
    (is (search "limit" areply :test #'char-equal))
    (is-false (eq asrc :house-chat))))

(test chat-spine-no-external-llm-freeform
  "Even with llm-enabled config, freeform residual is not :source :llm."
  (metis:boot :bootstrap t :reset t)
  (metis:nn-enable-path metis:*mind*)
  (metis:symbol-model-clear!)
  (metis:house-chat-ensure!
   :force t
   :corpus "no external llm freeform product path. "
   :epochs 1 :hidden 24 :seq-len 16 :depth 2 :max-batches 10)
  ;; Simulate product config that would have enabled external LLM
  (metis:set-config :llm-enabled t)
  (metis:set-config :llm-api-key "sk-test-fake-not-used")
  (is-true (metis:llm-enabled-p)
           "config pretends LLM is enabled")
  (is-false metis:*product-freeform-external-llm*)
  (let* ((s (metis:session-create :id "cs-nolm" :boot nil))
         (out (metis:iface-turn s "ramble about starlight briefly"))
         (src (getf (getf out :result) :source)))
    (is-false (eq src :llm))
    (is (eq src :house-chat)
        (format nil "must be house-chat not llm; got ~A" src)))
  (metis:set-config :llm-enabled nil)
  (metis:set-config :llm-api-key nil))

(test chat-spine-tool-sieves-regression
  "reason-act, process math, extractive still win on their cases."
  (metis:boot :bootstrap t :reset t)
  (metis:nn-enable-path metis:*mind*)
  (let ((s (metis:session-create :id "cs-tools" :boot nil)))
    (metis:iface-turn s "x = y")
    (let* ((q (metis:iface-turn s "what is y"))
           (src (getf (getf q :result) :source)))
      (is (member src '(:bind :prove :solve) :test #'eq))
      (is (search "x" (string-downcase (or (getf q :reply) "")))))
    (let* ((m (metis:iface-turn s "2+2"))
           (src (getf (getf m :result) :source)))
      (is (or (eq src :math)
              (eq (getf (getf m :result) :freeform) :math)
              (search "4" (or (getf m :reply) ""))))))
  ;; extractive
  (let* ((dir (uiop:ensure-directory-pathname
               (merge-pathnames "metis-cs-peng/" (uiop:temporary-directory))))
         (s (metis:session-create :id "cs-peng" :boot nil)))
    (ensure-directories-exist dir)
    (with-open-file (out (merge-pathnames "p.txt" dir)
                         :direction :output :if-exists :supersede)
      (write-string "Penguins are flightless birds that swim in cold seas." out))
    (metis:session-ingest-path s dir :train nil :async nil)
    (let ((o (metis:iface-turn s "tell me about penguins")))
      (is (search "penguin" (string-downcase (or (getf o :reply) ""))
                  :test #'char-equal)))
    (ignore-errors (metis:brain-stop!))))

(test chat-spine-wiring-static
  "Freeform residual invokes house-chat; no llm-complete as product default."
  (let* ((iface (merge-pathnames "src/interface.lisp"
                                 (asdf:system-source-directory :metis)))
         (spine (merge-pathnames "src/chat-spine.lisp"
                                 (asdf:system-source-directory :metis)))
         (si (uiop:read-file-string iface))
         (ss (uiop:read-file-string spine)))
    (is-true (probe-file spine))
    (is (search "house-chat-generate" si :test #'char-equal))
    (is (search "house-chat" ss :test #'char-equal))
    (is (search "symbol-model-attach" ss :test #'char-equal))
    (is (search "never" (string-downcase si)))
    ;; product freeform must not call %iface-llm-answer in residual cond
    (is (not (search "(%iface-llm-answer" si))
        "freeform residual must not call %iface-llm-answer")))
