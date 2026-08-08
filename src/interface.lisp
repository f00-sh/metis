;;;; interface.lisp — full interactive product surface + self-accommodation
(in-package :metis)

(defparameter *iface-thesis*
  "METIS INTERFACE: multi-turn interactive cognition with first-class
file/context/photo session material and TMS-guarded self-accommodation
when the user requests an unknown capability.")

(defun iface-thesis ()
  *iface-thesis*)

(defun %iface-parse-turn (text)
  "Parse user turn into an action. Returns (values op payload)."
  (let ((s (string-trim '(#\Space #\Tab #\Newline) text)))
    (cond
      ((zerop (length s))
       (values :empty nil))
      ((char= (char s 0) #\()
       (values :form
               (let ((*package* (find-package :metis))
                     (*read-eval* nil))
                 (read-from-string s))))
      ((or (string-equal s "help") (string-equal s "?"))
       (values :help nil))
      ((or (string-equal s "quit") (string-equal s "exit")
           (string-equal s "/quit") (string-equal s "/exit")
           (string-equal s ":q") (string-equal s ":quit")
           (string-equal s ":exit"))
       (values :quit nil))
      ((or (string-equal s "status") (string-equal s "/status"))
       (values :status nil))
      ;; @path / @ path — chat drop: attach + hard train (not context-only)
      ((cl-ppcre:scan "(?i)^@\\s*(\\S+)(?:\\s+(.*))?$" s)
       (cl-ppcre:register-groups-bind (path cap)
           ("(?i)^@\\s*(\\S+)(?:\\s+(.*))?$" s)
         (values :attach-file (list path cap :hard))))
      ((cl-ppcre:scan "(?i)^/attach\\s+file\\s+(\\S+)(?:\\s+(.*))?$" s)
       (cl-ppcre:register-groups-bind (path cap)
           ("(?i)^/attach\\s+file\\s+(\\S+)(?:\\s+(.*))?$" s)
         (values :attach-file (list path cap :hard))))
      ((cl-ppcre:scan "(?i)^/attach\\s+folder\\s+(\\S+)(?:\\s+(.*))?$" s)
       (cl-ppcre:register-groups-bind (path rest)
           ("(?i)^/attach\\s+folder\\s+(\\S+)(?:\\s+(.*))?$" s)
         (values :attach-folder (list path rest))))
      ((cl-ppcre:scan "(?i)^/attach\\s+photo\\s+(\\S+)(?:\\s+(.*))?$" s)
       (cl-ppcre:register-groups-bind (path cap)
           ("(?i)^/attach\\s+photo\\s+(\\S+)(?:\\s+(.*))?$" s)
         (values :attach-photo (list path cap))))
      ;; bare /attach PATH (shortcut)
      ((cl-ppcre:scan "(?i)^/attach\\s+(\\S+)(?:\\s+(.*))?$" s)
       (cl-ppcre:register-groups-bind (path cap)
           ("(?i)^/attach\\s+(\\S+)(?:\\s+(.*))?$" s)
         (values :attach-file (list path cap :hard))))
      ((cl-ppcre:scan "(?i)^/ingest\\s+(\\S+)(?:\\s+(.*))?$" s)
       (cl-ppcre:register-groups-bind (path rest)
           ("(?i)^/ingest\\s+(\\S+)(?:\\s+(.*))?$" s)
         (values :ingest (list path rest))))
      ((cl-ppcre:scan "(?i)^/watch\\s+folder\\s+(\\S+)(?:\\s+(.*))?$" s)
       (cl-ppcre:register-groups-bind (path rest)
           ("(?i)^/watch\\s+folder\\s+(\\S+)(?:\\s+(.*))?$" s)
         (values :watch-folder (list path rest))))
      ((cl-ppcre:scan "(?i)^/watch\\s+poll\\s*$" s)
       (values :watch-poll nil))
      ((cl-ppcre:scan "(?i)^/watch\\s+stop\\s*$" s)
       (values :watch-stop nil))
      ((cl-ppcre:scan "(?i)^/brain\\s+(status|start|stop)\\s*$" s)
       (cl-ppcre:register-groups-bind (sub)
           ("(?i)^/brain\\s+(status|start|stop)\\s*$" s)
         (values :brain (string-downcase sub))))
      ((cl-ppcre:scan "(?i)^/brain\\s*$" s)
       (values :brain "status"))
      ;; /llm — status | key | model | base | clear | on | off
      ((cl-ppcre:scan "(?i)^/llm(?:\\s+(.*))?$" s)
       (cl-ppcre:register-groups-bind (rest)
           ("(?i)^/llm(?:\\s+(.*))?$" s)
         (values :llm (string-trim '(#\Space #\Tab) (or rest "")))))
      ;; open-knowledge symbol packs (catalog / install / overlay / export)
      ((cl-ppcre:scan "(?i)^/symbol-pack(?:\\s+(.*))?$" s)
       (cl-ppcre:register-groups-bind (rest)
           ("(?i)^/symbol-pack(?:\\s+(.*))?$" s)
         (values :symbol-pack
                 (string-trim '(#\Space #\Tab) (or rest "")))))
      ((cl-ppcre:scan "(?i)^/symbols\\s+catalog\\s*$" s)
       (values :symbol-pack "catalog"))
      ((cl-ppcre:scan "(?i)^/symbols\\s+pack\\s+(.*)$" s)
       (cl-ppcre:register-groups-bind (rest)
           ("(?i)^/symbols\\s+pack\\s+(.*)$" s)
         (values :symbol-pack (string-trim '(#\Space #\Tab) (or rest "")))))
      ((cl-ppcre:scan "(?i)^/context\\s+(.+)$" s)
       (cl-ppcre:register-groups-bind (ctx)
           ("(?i)^/context\\s+(.+)$" s)
         (values :attach-context ctx)))
      ((cl-ppcre:scan "(?i)^/attachments\\s*$" s)
       (values :list-attachments nil))
      ((cl-ppcre:scan "(?i)^/ask\\s+(.+)$" s)
       (cl-ppcre:register-groups-bind (q)
           ("(?i)^/ask\\s+(.+)$" s)
         (values :ask q)))
      ((cl-ppcre:scan "(?i)^/tell\\s+(.+)$" s)
       (cl-ppcre:register-groups-bind (q)
           ("(?i)^/tell\\s+(.+)$" s)
         (values :tell q)))
      ((cl-ppcre:scan "(?i)^/goal\\s+(.+)$" s)
       (cl-ppcre:register-groups-bind (q)
           ("(?i)^/goal\\s+(.+)$" s)
         (values :goal q)))
      ((cl-ppcre:scan "(?i)^/need\\s+(.+)$" s)
       (cl-ppcre:register-groups-bind (cap)
           ("(?i)^/need\\s+(.+)$" s)
         (values :need (string-trim '(#\Space) cap))))
      ((cl-ppcre:scan "(?i)^/read\\s+(\\S+)$" s)
       (cl-ppcre:register-groups-bind (id)
           ("(?i)^/read\\s+(\\S+)$" s)
         (values :read-attachment id)))
      (t
       (values :freeform s)))))

(defun %iface-capability-present-p (sess name)
  (let* ((n (string-upcase (string name)))
         (tool-sym (intern n :metis)))
    (or (member (intern n :keyword) (sess-capabilities sess))
        (find-skills (sess-mind sess) :pattern n)
        (some (lambda (r)
                (search (string-downcase n)
                        (string-downcase (symbol-name (rule-name r)))))
              (kb-all-rules (mind-kb (sess-mind sess))))
        (tr-get (mind-tools (sess-mind sess)) tool-sym))))
(defun iface-accommodate (sess capability-name &key (doc nil))
  "Self-accommodation: register skill+tool under TMS-guarded self-mod.
   Tool symbol is reader-normal (UPCASE) so (tool NAME …) resolves like core tools."
  (let* ((m (sess-mind sess))
         (cap (string-upcase (string capability-name)))
         (sym (intern (format nil "CAP-~A" cap) :metis))
         ;; Must match read-time symbols: (tool HYPER-TRANSLATOR …) → HYPER-TRANSLATOR
         (tool-sym (intern cap :metis))
         (head (list sym '?input))
         (body (list (list 'true))))
    (multiple-value-bind (mod-ok mod-detail)
        (epoch-guarded-self-mod m sym head body :kind :rule)
      (unless mod-ok
        (return-from iface-accommodate (values nil mod-detail)))
      (pm-install
       (mind-pm m)
       (make-skill
        :name sym
        :params '(input)
        :preconds '()
        :body `((list :handled t
                      :capability ',sym
                      :input input
                      :doc ,(or doc (format nil "Accommodated ~A" cap))))
        :kind :procedure
        :source :iface-accommodate
        :utility 1.0
        :meta (list :doc doc :capability cap)))
      (register-tool
       m tool-sym
       (lambda (&rest args)
         (list :ok t
               :capability tool-sym
               :args args
               :via :accommodated-tool))
       :doc (or doc (format nil "User-accommodated tool ~A" cap))
       :schema '(&rest args)
       :safe t)
      (pushnew (intern cap :keyword) (sess-capabilities sess))
      (incf (sess-accommodations sess))
      (assert-fact m
                   (list 'capability-accommodated
                         (intern (string-downcase cap) :metis))
                   :support :iface
                   :forward nil)
      (values t
              (list :accommodated cap
                    :rule sym
                    :tool tool-sym
                    :mod mod-detail)))))
(defun %iface-read-form-string (s)
  (let ((*package* (find-package :metis))
        (*read-eval* nil))
    (read-from-string s)))

;;; ------------------------------------------------------------------
;;; English freeform: keyword retrieval + TMS-gated generate reply
;;; ------------------------------------------------------------------

(defparameter *iface-stopwords*
  '("a" "an" "the" "is" "are" "was" "were" "be" "been" "being"
    "what" "who" "which" "where" "when" "why" "how" "do" "does" "did"
    "of" "to" "in" "on" "for" "with" "about" "from" "as" "at" "by"
    "and" "or" "not" "this" "that" "it" "its" "my" "your" "our"
    "can" "could" "would" "should" "me" "you" "we" "they" "i"
    "tell" "please" "into" "than" "then" "also" "just")
  "Tokens ignored when scoring freeform retrieval.")

(defparameter *iface-sketch-generate* nil
  "When T, freeform may fall back to pure-CL char-LM sketch (usually garbage).
   Default NIL — prefer real English (chat, concepts, docs, optional API LLM).")

(defun %iface-englishish-p (text)
  "T if TEXT looks like usable English (not untrained LM garbage / prompt echo)."
  (let* ((s (string-trim '(#\Space #\Tab #\Newline #\Return) (or text "")))
         (n (length s)))
    (when (and (>= n 12) (<= n 4000))
      (let* ((letters (count-if #'alpha-char-p s))
             (spaces (count #\Space s))
             (punct (count-if (lambda (c)
                                (find c ".,;:!?-'\"()"))
                              s))
             (ratio (if (plusp n) (/ (float letters) n) 0.0))
             (words (cl-ppcre:split "\\s+" s))
             (avg-w (if (plusp (length words))
                        (/ (float (reduce #'+ (mapcar #'length words)))
                           (length words))
                        99.0)))
        ;; Reject pure prompt-template echoes and nonsense letter salad.
        (and (>= ratio 0.55)
             (>= spaces 2)
             (<= avg-w 12.0)
             (not (search "Answer clearly in English" s :test #'char-equal))
             (not (cl-ppcre:scan "(?i)^\\s*nswer clearly" s))
             (or (>= punct 0)
                 t)
             ;; at least a few dictionary-ish short words
             (>= (count-if (lambda (w)
                             (and (>= (length w) 2) (<= (length w) 12)
                                  (every #'alpha-char-p w)))
                           words)
                 3))))))

(defparameter *iface-concepts*
  '(("number" . "A number is a mathematical object used to count, measure, and label. Whole numbers (0, 1, 2, …) count discrete things; integers include negatives; rationals are fractions; reals fill the continuum. Arithmetic (+ − × ÷) is the basic language of numbers.")
    ("numbers" . "Numbers are mathematical objects for counting, measuring, and ordering. They include natural numbers, integers, rationals, reals, and complexes, each extending what you can express.")
    ("integer" . "An integer is a whole number that can be positive, negative, or zero: …, −2, −1, 0, 1, 2, …. No fractional part.")
    ("math" . "Mathematics is the study of structure, quantity, space, and change — using precise definitions, proofs, and models.")
    ("mathematics" . "Mathematics is the study of structure, quantity, space, and change — using precise definitions, proofs, and models.")
    ("computer" . "A computer is a machine that stores and transforms information by executing programs. Metis itself runs as Common Lisp on a computer.")
    ("program" . "A program is a set of instructions a computer can execute. In Metis you can also speak in s-expression mind forms like (tell …) and (ask …).")
    ("ai" . "Artificial intelligence is software that performs tasks people associate with intelligence — reasoning, learning, planning, language. Metis is a hybrid cognitive architecture (symbolic + neural) in that space.")
    ("artificial intelligence" . "Artificial intelligence is software that performs tasks people associate with intelligence — reasoning, learning, planning, language. Metis is a hybrid cognitive architecture (symbolic + neural) in that space.")
    ("dolphin" . "A dolphin is a highly social marine mammal. Dolphins are cetaceans, use echolocation, live in pods, and are known for complex communication and problem-solving. Attach notes with @PATH for domain-specific dolphin material.")
    ("dolphins" . "Dolphins are highly social marine mammals (cetaceans). They use echolocation, live in pods, and show complex communication. Drop files with @PATH if you want me to train on more detail.")
    ("day" . "A day is the period of roughly 24 hours corresponding to one rotation of the Earth relative to the Sun. Calendars group days into weeks, months, and years.")
    ("time" . "Time is the dimension in which events are ordered from past to future. Clocks measure it; calendars organize days and years.")
    ("file" . "A file is a named blob of data on disk. In this chat you can drop one with @PATH or /attach PATH — I extract text and hard-train on it.")
    ("folder" . "A folder (directory) holds files. Use /ingest PATH once, or /watch folder PATH so new drops train in the background.")
    ("brain" . "Here, the brain is Metis's background learner: it watches folders, drains the train queue, and consolidates corpus text while you chat. Check it with /brain status.")
    ("metis" . "I am Metis — an introspective Common Lisp cognitive architecture. I combine a symbolic mind (KB, rules, planning, TMS) with pure-CL neural training, session memory, and a background brain that trains on files you attach.")
    ("lisp" . "Lisp is a family of programming languages built around lists and symbolic expressions. Metis is implemented in Common Lisp (SBCL); you can also type mind forms like (tell (happy metis)).")
    ("common lisp" . "Common Lisp is a powerful multi-paradigm Lisp dialect. Metis runs on SBCL and uses pure Common Lisp for its neural substrate by default."))
  "Built-in concept blurbs for clear English freeform answers.")

(defun iface-tokenize-query (text)
  "Distinctive tokens from TEXT (lowercase, length≥3, not stopwords)."
  (let* ((raw (string-downcase (or text "")))
         (parts (cl-ppcre:all-matches-as-strings "[a-z0-9][a-z0-9\\-]{2,}" raw))
         (out nil))
    (dolist (p parts)
      (unless (or (member p *iface-stopwords* :test #'string=)
                  (member p out :test #'string=))
        (push p out)))
    (nreverse out)))

(defun %iface-attachment-blob (a)
  "Searchable text for attachment A."
  (string-downcase
   (format nil "~A~%~A~%~A"
           (or (att-name a) "")
           (or (att-caption a) "")
           (or (att-text a) ""))))

(defun %iface-snippet-around (text token &key (radius 80))
  "Excerpt of TEXT around first TOKEN (case-insensitive)."
  (let* ((down (string-downcase text))
         (tok (string-downcase token))
         (pos (search tok down)))
    (if (null pos)
        (truncate-string text (* 2 radius))
        (let* ((start (max 0 (- pos radius)))
               (end (min (length text) (+ pos (length token) radius))))
          (string-trim
           '(#\Space #\Newline #\Tab)
           (subseq text start end))))))

(defun iface-split-sentences (text)
  "Split TEXT into sentence-like units (English-oriented)."
  (let* ((clean (cl-ppcre:regex-replace-all "[ \\t]+" (or text "") " "))
         (parts (cl-ppcre:split "(?<=[.!?])\\s+" clean)))
    (remove-if (lambda (s)
                 (< (length (string-trim '(#\Space #\Newline #\Tab) s)) 8))
               parts)))

(defun %iface-score-text (text tokens)
  "Score TEXT against TOKENS; returns (values score matched-tokens)."
  (let ((blob (string-downcase (or text "")))
        (matched nil)
        (score 0))
    (dolist (tok tokens)
      (when (search tok blob)
        (push tok matched)
        (incf score)
        ;; bonus for whole-word-ish presence
        (when (cl-ppcre:scan (format nil "\\b~A\\b" (cl-ppcre:quote-meta-chars tok))
                             blob)
          (incf score))))
    (values score (nreverse matched))))

(defun iface-retrieve-attachments (sess query &key (min-score 1) (limit 5))
  "Score session attachments by keyword overlap with QUERY.
   Returns list of plists (:attachment :score :tokens :snippet :text :sentences)
   sorted by score desc. Does NOT require the full question as a substring."
  (let* ((tokens (iface-tokenize-query query))
         (hits nil))
    (when (null tokens)
      (return-from iface-retrieve-attachments nil))
    (maphash
     (lambda (_ a)
       (declare (ignore _))
       (let ((blob (%iface-attachment-blob a)))
         (multiple-value-bind (score matched)
             (%iface-score-text blob tokens)
           (when (and (att-text a)
                      (search (string-downcase query) blob :test #'char-equal))
             (incf score 3))
           (when (>= score min-score)
             (let* ((text (or (att-text a) (att-caption a) ""))
                    (sents (iface-rank-sentences text tokens :limit 8))
                    (snippet
                     (if sents
                         (format nil "~{~A~^ ~}" (mapcar (lambda (s) (getf s :text)) sents))
                         (if (and matched (plusp (length text)))
                             (%iface-snippet-around text (first matched) :radius 160)
                             (truncate-string text 320)))))
               (push (list :attachment a
                           :id (att-id a)
                           :kind (att-kind a)
                           :name (att-name a)
                           :score score
                           :tokens matched
                           :snippet snippet
                           :sentences sents
                           :text text)
                     hits))))))
     (sess-attachments sess))
    (subseq (sort hits #'> :key (lambda (h) (getf h :score)))
            0 (min limit (length hits)))))

(defun iface-rank-sentences (text tokens &key (limit 6) (min-score 1))
  "Rank sentences in TEXT by query token overlap. Returns scored plists."
  (let ((scored nil))
    (dolist (sent (iface-split-sentences text))
      (multiple-value-bind (score matched)
          (%iface-score-text sent tokens)
        (when (>= score min-score)
          (push (list :text (string-trim '(#\Space #\Newline #\Tab) sent)
                      :score score
                      :tokens matched)
                scored))))
    (subseq (sort scored #'> :key (lambda (s) (getf s :score)))
            0 (min limit (length scored)))))

(defun iface-extractive-answer (sess query &key (max-sentences 6))
  "Build a real English answer from document sentences matching QUERY.
   Returns (:reply-text … :sentences … :matches …) or NIL."
  (let* ((tokens (iface-tokenize-query query))
         (hits (iface-retrieve-attachments sess query :min-score 1 :limit 8))
         (all-sents nil))
    (when (null hits)
      (return-from iface-extractive-answer nil))
    (dolist (h hits)
      (let ((sents (or (getf h :sentences)
                       (iface-rank-sentences (getf h :text) tokens :limit 8))))
        (dolist (s sents)
          (push (list* :source (getf h :name)
                       :id (getf h :id)
                       s)
                all-sents))))
    (setf all-sents
          (subseq (sort all-sents #'> :key (lambda (s) (getf s :score)))
                  0 (min max-sentences (length all-sents))))
    (when (null all-sents)
      (return-from iface-extractive-answer nil))
    ;; de-dupe sentence text
    (let* ((seen (make-hash-table :test #'equal))
           (unique nil))
      (dolist (s all-sents)
        (let ((tx (getf s :text)))
          (unless (gethash (string-downcase tx) seen)
            (setf (gethash (string-downcase tx) seen) t)
            (push s unique))))
      (setf unique (nreverse unique))
      (let* ((body (format nil "~{~A~^ ~}"
                           (mapcar (lambda (s) (getf s :text)) unique)))
             (sources (remove-duplicates
                       (mapcar (lambda (s) (or (getf s :source) (getf s :id)))
                               unique)
                       :test #'equal))
             (reply
              (format nil "~A~%~%Sources: ~{~A~^, ~}."
                      body sources)))
        (list :reply-text reply
              :sentences unique
              :matches hits
              :tokens tokens
              :source :extractive)))))

(defun %iface-default-lm-name ()
  "Pick a registered LM for freeform generate fallback."
  (cond
    ((and (boundp '*online-lm-name*)
          (metis.nn:nn-registry-get *online-lm-name*))
     *online-lm-name*)
    ((metis.nn:nn-registry-get "session-lm") "session-lm")
    ((metis.nn:nn-registry-get "online-lm") "online-lm")
    (t (first (metis.nn:nn-registry-list)))))

(defun %iface-generate-prompt (question &optional context)
  "Prompt template for freeform neural / LLM fallback."
  (if (and context (plusp (length (string-trim '(#\Space) context))))
      (format nil
              "Answer the question using ONLY the context when possible. Be clear and complete in English.~%~%Context:~%~A~%~%Question: ~A~%Answer:"
              (truncate-string context 4000) question)
      (format nil "Answer clearly in English.~%~%Question: ~A~%Answer:" question)))

(defun %iface-kb-about (mind question)
  "Lookup (about topic …) facts by exact or loose string match on topic."
  (let* ((m (ensure-mind mind))
         (q (string-trim '(#\Space #\Tab #\Newline) (or question "")))
         (qd (string-downcase q)))
    (or (ignore-errors (ask m (list 'about q)))
        (ignore-errors (ask m (list 'about q '?x)))
        (dolist (f (kb-all-facts (mind-kb m)))
          (when (and (consp f)
                     (symbolp (first f))
                     (string-equal (symbol-name (first f)) "ABOUT")
                     (stringp (second f)))
            (let ((topic (string-downcase (second f))))
              (when (or (string= topic qd)
                        (search topic qd)
                        (search qd topic))
                (return (or (third f) (second f))))))))))

(defun %iface-kb-english-facts (mind question &key (limit 12))
  "Render related KB facts as English lines matching query tokens."
  (let* ((m (ensure-mind mind))
         (tokens (iface-tokenize-query question))
         (lines nil))
    (when (null tokens)
      (return-from %iface-kb-english-facts nil))
    (dolist (f (kb-all-facts (mind-kb m)))
      (when (consp f)
        (let ((blob (string-downcase (format nil "~{~A~^ ~}" f))))
          (multiple-value-bind (score matched)
              (%iface-score-text blob tokens)
            (when (and (plusp score)
                       (not (member (first f)
                                    '(episode episode-key self-code epoch-thesis-loaded
                                      capability-accommodated hybrid-mode learn-rate
                                      consolidation-batches neocortex-consolidated)
                                    :test #'eq)))
              (push (list :score score
                          :tokens matched
                          :fact f
                          :line (format nil "~{~A~^ ~}." f))
                    lines))))))
    (when lines
      (setf lines (subseq (sort lines #'> :key (lambda (x) (getf x :score)))
                          0 (min limit (length lines))))
      (format nil "From what I know:~%~{• ~A~%~}"
              (mapcar (lambda (x) (getf x :line)) lines)))))

(defun %iface-llm-answer (mind question &key context)
  "TMS-gated OpenAI-compatible LLM answer when enabled + key present."
  (unless (and (fboundp 'llm-enabled-p) (llm-enabled-p))
    (return-from %iface-llm-answer nil))
  (unless (nn-path-allowed-p mind)
    (return-from %iface-llm-answer
      (list :freeform :refuse
            :refused t
            :reason "TMS nn-path-enabled is OUT"
            :reply-text
            "I can't call the language model: neural path is disabled (TMS OUT). Use /nn enable."
            :source :tms-out)))
  (handler-case
      (let* ((prompt (%iface-generate-prompt question context))
             (system "You are Metis, a careful assistant. Answer in clear English. Prefer the provided context when present. If context is insufficient, say what is missing.")
             (text (llm-complete prompt :system system :max-tokens 1024)))
        (list :freeform :llm
              :prompt prompt
              :text text
              :reply-text (if (and text (plusp (length (string-trim '(#\Space) text))))
                              text
                              "I had no text from the language model.")
              :source :llm))
    (error (e)
      (list :freeform :refuse
            :refused t
            :reason (princ-to-string e)
            :reply-text (format nil "Language model error: ~A" e)
            :source :llm-error))))

(defun %iface-looks-english-p (text)
  "Heuristic: reject pure-CL sketch garbage (*[]| spam, tiny alpha ratio)."
  (let* ((s (or text ""))
         (n (length s)))
    (when (< n 12) (return-from %iface-looks-english-p nil))
    (let ((letters 0) (bad 0) (spaces 0))
      (loop for c across s do
        (cond
          ((alpha-char-p c) (incf letters))
          ((member c '(#\* #\[ #\] #\| #\^ #\{ #\} #\\) :test #'char=) (incf bad))
          ((member c '(#\Space #\Newline #\Tab) :test #'char=) (incf spaces))))
      (and (>= (/ letters (float n)) 0.45)
           (<= (/ bad (float (max 1 n))) 0.05)
           (>= spaces 2)
           (not (cl-ppcre:scan "(?i)\\[local model sketch" s))))))

(defun %iface-chitchat (question &optional mind)
  "Greetings, identity, capability — real English, never NIL or sketch garbage."
  (let* ((q (string-trim '(#\Space #\Tab #\Newline #\.) (or question "")))
         (qd (string-downcase q)))
    (cond
      ((zerop (length qd)) nil)
      ((cl-ppcre:scan "^(hi|hello|hey|howdy|yo|hiya|good\\s+(morning|afternoon|evening))\\b[!?.]*$" qd)
       (list :freeform :chat
             :reply-text
             "Hello. I'm Metis — a Common Lisp cognitive architecture. Ask me anything, drop a file with @PATH, or type help for commands."
             :source :chat))
      ((cl-ppcre:scan "^(thanks|thank you|thx|ty)\\b" qd)
       (list :freeform :chat
             :reply-text "You're welcome."
             :source :chat))
      ((cl-ppcre:scan "^(bye|goodbye|see you|later)\\b" qd)
       (list :freeform :chat
             :reply-text "Goodbye. Type quit when you want to exit."
             :source :chat))
      ((cl-ppcre:scan "how are you" qd)
       (list :freeform :chat
             :reply-text
             (format nil "Running. ~A Brain and session memory are up — ask a question or @ a file to train."
                     (ignore-errors (metis-version-string)))
             :source :chat))
      ((or (cl-ppcre:scan "what('?s| is) your name" qd)
           (cl-ppcre:scan "who are you" qd)
           (cl-ppcre:scan "what are you" qd)
           (string= qd "name"))
       (list :freeform :chat
             :reply-text
             "I'm Metis — an introspective hybrid mind in Common Lisp (symbolic reasoning + pure-CL neural training). I can chat, learn from files you attach, watch folders, plan, and explain."
             :source :identity))
      ((cl-ppcre:scan "what can you (do|help)" qd)
       (list :freeform :chat
             :reply-text
             "I can: answer in English; learn from @PATH / /ingest / /watch folder; hard-train in the background (/brain status); reason with (tell)/(ask)/(plan); and use an external LLM if METIS_LLM_API_KEY is set. Type help for the full command list."
             :source :chat))
      ((cl-ppcre:scan "what day is it|what('?s| is) (the )?date|today('?s)? date" qd)
       (multiple-value-bind (s m h day mon year)
           (decode-universal-time (get-universal-time) 0)
         (declare (ignore s m h))
         (list :freeform :chat
               :reply-text
               (format nil "On this machine's clock (UTC): ~4,'0D-~2,'0D-~2,'0D."
                       year mon day)
               :source :time)))
      ((and mind (cl-ppcre:scan "who am i|what is my name" qd))
       (list :freeform :chat
             :reply-text "I don't have a stored name for you yet. Tell me with (tell (user-name \"…\")) or /context."
             :source :chat))
      (t nil))))

(defun %iface-concept-topic (question)
  "Extract topic for 'what is X' / 'what are X' / 'define X' / bare concept."
  (let ((q (string-trim '(#\Space #\Tab #\Newline #\? #\. #\!)
                        (string-downcase (or question "")))))
    (or (cl-ppcre:register-groups-bind (topic)
            ("(?i)^(?:what\\s+(?:is|are)|what'?s|define|explain|describe)\\s+(?:a|an|the)?\\s*(.+)$" q)
          (string-trim '(#\Space #\Tab) topic))
        (cl-ppcre:register-groups-bind (topic)
            ("(?i)^(?:tell me about|about)\\s+(?:a|an|the)?\\s*(.+)$" q)
          (string-trim '(#\Space #\Tab) topic))
        ;; bare short topic: "number" "dolphins"
        (when (and (<= (length q) 40)
                   (cl-ppcre:scan "^[a-z][a-z0-9 \\-]{1,38}$" q)
                   (null (cl-ppcre:scan "\\s" (string-trim '(#\Space) q))))
          q))))

(defun %iface-concept-answer (question)
  "Built-in English concept answers for common open questions."
  (let* ((topic (%iface-concept-topic question))
         (td (and topic (string-downcase (string-trim '(#\Space #\Tab) topic)))))
    (when (and td (plusp (length td)))
      ;; strip trailing "is" junk / articles
      (setf td (cl-ppcre:regex-replace-all "^(a|an|the)\\s+" td ""))
      (or
       (let ((hit (assoc td *iface-concepts* :test #'string=)))
         (when hit
           (list :freeform :concept
                 :topic td
                 :reply-text (cdr hit)
                 :source :concept)))
       ;; substring key match (e.g. "a number" already stripped)
       (dolist (pair *iface-concepts*)
         (when (or (search (car pair) td)
                   (search td (car pair)))
           (return
            (list :freeform :concept
                  :topic (car pair)
                  :reply-text (cdr pair)
                  :source :concept))))))))

(defun %iface-honest-unknown (question)
  (list :freeform :unknown
        :reply-text
        (format nil "I don't have a solid answer for “~A” from documents or built-in notes yet.~%~%Try: @PATH or /attach a file (I hard-train on it), /watch folder for live drops, /context TEXT, or set METIS_LLM_API_KEY for open-world English. You can also (tell (about \"topic\" \"fact…\")). Math works inline: try 2+4(56/3) or “what is 1+2”."
                (truncate-string question 80))
        :hint "attach notes, teach facts, math, or set LLM API key"
        :source :none))

;;; ------------------------------------------------------------------
;;; Math — chat + REPL scratch (infix, implicit multiply, safe eval)
;;; ------------------------------------------------------------------

(defun %math-format-number (n &key (approx t))
  "Pretty number. APPROX T adds decimal hint for ratios (final answers)."
  (cond
    ((integerp n) (format nil "~A" n))
    ((typep n 'ratio)
     (if approx
         (format nil "~A  (≈ ~,6G)" n (float n 1d0))
         (format nil "~A" n)))
    ((typep n 'complex) (format nil "~A" n))
    ((floatp n)
     (multiple-value-bind (i f) (floor n)
       (if (zerop f) (format nil "~A" i) (format nil "~,12G" n))))
    (t (prin1-to-string n))))

(defun %math-format-number-short (n)
  "Compact form for intermediate work (no ≈ clutter)."
  (%math-format-number n :approx nil))

(defun %math-strip-question (q)
  "Pull a candidate expression out of English wrappers."
  (let* ((q (string-trim '(#\Space #\Tab #\Newline #\? #\! #\.) (or q "")))
         (q (cl-ppcre:regex-replace-all "(?i)^(hey|please|um|uh)\\s+" q "")))
    (or
     (cl-ppcre:register-groups-bind (expr)
         ("(?i)^(?:what(?:\\s*is|\\s*'s|s)|whats|calculate|compute|solve|evaluate|eval|how\\s+much\\s+is|what's)\\s+(.+)$" q)
       (string-trim '(#\Space #\Tab #\? #\! #\.) expr))
     (cl-ppcre:register-groups-bind (expr)
         ("(?i)^(?:find|give\\s+me|tell\\s+me)\\s+(.+)$" q)
       (let ((e (string-trim '(#\Space #\Tab #\? #\! #\.) expr)))
         (when (cl-ppcre:scan "[0-9]" e) e)))
     q)))

(defun %math-looks-like-expr-p (s)
  "T if S is arithmetic and/or simple algebra (digits + ops + optional var/=)."
  (let* ((s (string-trim '(#\Space #\Tab #\Newline) (or s "")))
         (n (length s)))
    (and (>= n 1)
         (cl-ppcre:scan "[0-9]" s)
         ;; numbers, ops, parens, spaces, one-letter vars, =
         (cl-ppcre:scan "^[0-9A-Za-z+\\-*/^().%=\\s,]+$" s)
         ;; reject multi-letter words (prose) — only single-letter vars
         (not (cl-ppcre:scan "[A-Za-z]{2,}" s))
         (or (and (>= n 1) (every #'digit-char-p (remove #\. (remove #\Space s))))
             (cl-ppcre:scan "[+\\-*/^%()=]" s)
             (cl-ppcre:scan "[A-Za-z]" s)))))

(defun %math-normalize-expr (s)
  "Infix cleanup: spaces, commas, ^, %, implicit multiplication (incl. vars)."
  (let* ((s (string-trim '(#\Space #\Tab #\Newline) (or s "")))
         (s (cl-ppcre:regex-replace-all "," s ""))
         (s (cl-ppcre:regex-replace-all "\\s+" s ""))
         (s (cl-ppcre:regex-replace-all "\\^" s "**"))
         (s (cl-ppcre:regex-replace-all "%" s "/100"))
         ;; implicit multiply: 2( )( )2  4(56/3)  2n  n2  n(  )n  2n( 
         (s (cl-ppcre:regex-replace-all "(\\d)\\(" s "\\1*("))
         (s (cl-ppcre:regex-replace-all "\\)(\\d)" s ")*\\1"))
         (s (cl-ppcre:regex-replace-all "\\)\\(" s ")*("))
         (s (cl-ppcre:regex-replace-all "(\\d)([A-Za-z])" s "\\1*\\2"))
         (s (cl-ppcre:regex-replace-all "([A-Za-z])(\\d)" s "\\1*\\2"))
         (s (cl-ppcre:regex-replace-all "([A-Za-z])\\(" s "\\1*("))
         (s (cl-ppcre:regex-replace-all "\\)([A-Za-z])" s ")*\\1"))
         (s (cl-ppcre:regex-replace-all "\\*\\*" s "^")))
    s))

(defun %math-unary-context-p (toks)
  "T if next +/- is unary (start, after '(', or after another operator)."
  (or (null toks)
      (let ((p (car toks)))
        (and (eq (first p) :op)
             (member (second p) '("(" "+" "-" "*" "/" "^" "u-" "u+")
                     :test #'string=)))))

(defun %math-tokenize (s)
  "Tokenize normalized infix. Unary ± become u+/u-. Single letters → :var."
  (let ((s (%math-normalize-expr s))
        (i 0)
        (n 0)
        (toks nil))
    (setf n (length s))
    (loop while (< i n) do
      (let ((c (char s i)))
        (cond
          ((or (digit-char-p c) (char= c #\.))
           (let ((j i))
             (loop while (and (< j n)
                              (or (digit-char-p (char s j))
                                  (char= (char s j) #\.)))
                   do (incf j))
             (push (list :num (read-from-string (subseq s i j))) toks)
             (setf i j)))
          ((alpha-char-p c)
           (push (list :var (string-downcase (string c))) toks)
           (incf i))
          ((member c '(#\+ #\- #\* #\/ #\^ #\( #\)) :test #'char=)
           (cond
             ((and (or (char= c #\-) (char= c #\+))
                   (%math-unary-context-p toks))
              (push (list :op (if (char= c #\-) "u-" "u+")) toks))
             (t
              (push (list :op (string c)) toks)))
           (incf i))
          (t (error "bad math char ~A" c)))))
    (nreverse toks)))

(defun %math-parse-expr (tokens)
  "Shunting-yard with full order of operations (PEMDAS):
   parentheses → unary ± → ^ (right-assoc) → * / → + - (left-assoc)."
  (let ((out nil)
        (ops nil)
        (prec '(("u-" . 5) ("u+" . 5)
                ("^" . 4)
                ("*" . 3) ("/" . 3)
                ("+" . 2) ("-" . 2))))
    (labels ((p (op) (or (cdr (assoc op prec :test #'string=)) 0))
             (right-assoc (op)
               (or (string= op "^") (string= op "u-") (string= op "u+")))
             (unary (op) (or (string= op "u-") (string= op "u+")))
             (apply-op ()
               (let ((op (pop ops)))
                 (cond
                   ((unary op)
                    (let ((a (pop out)))
                      (unless a (error "arity"))
                      (push (if (string= op "u-") (- a) a) out)))
                   (t
                    (let ((b (pop out))
                          (a (pop out)))
                      (unless (and a b) (error "arity"))
                      (push
                       (cond
                         ((string= op "+") (+ a b))
                         ((string= op "-") (- a b))
                         ((string= op "*") (* a b))
                         ((string= op "/")
                          (if (zerop b) (error "division by zero") (/ a b)))
                         ((string= op "^") (expt a b))
                         (t (error "op ~A" op)))
                       out)))))))
      (dolist (tok tokens)
        (ecase (first tok)
          (:num (push (second tok) out))
          (:var (error "bare variable in pure arithmetic"))
          (:op
           (let ((o (second tok)))
             (cond
               ((string= o "(") (push o ops))
               ((string= o ")")
                (loop while (and ops (not (string= (car ops) "(")))
                      do (apply-op))
                (when (and ops (string= (car ops) "(")) (pop ops)))
               (t
                (loop while (and ops
                                 (not (string= (car ops) "("))
                                 (let ((top (car ops)))
                                   (or (> (p top) (p o))
                                       (and (= (p top) (p o))
                                            (not (right-assoc o))))))
                      do (apply-op))
                (push o ops)))))))
      (loop while ops do
        (when (member (car ops) '("(" ")") :test #'string=)
          (error "mismatched parentheses"))
        (apply-op))
      (unless (and out (null (cdr out)))
        (error "bad expression"))
      (car out))))

;;; ---- Linear algebra (one variable): 1+n=6 , 2(n+1)=10 , 1+2(n/1) ----

(defun %math-lin (a b)
  "Linear form a·var + b as cons (a . b)."
  (cons a b))

(defun %math-lin-a (L) (car L))
(defun %math-lin-b (L) (cdr L))

(defun %math-lin-add (x y)
  (%math-lin (+ (%math-lin-a x) (%math-lin-a y))
             (+ (%math-lin-b x) (%math-lin-b y))))

(defun %math-lin-sub (x y)
  (%math-lin (- (%math-lin-a x) (%math-lin-a y))
             (- (%math-lin-b x) (%math-lin-b y))))

(defun %math-lin-mul (x y)
  "Multiply linear forms; error if product is quadratic."
  (let ((ax (%math-lin-a x)) (bx (%math-lin-b x))
        (ay (%math-lin-a y)) (by (%math-lin-b y)))
    (cond
      ((and (zerop ax) (zerop ay)) (%math-lin 0 (* bx by)))
      ((zerop ax) (%math-lin (* bx ay) (* bx by)))
      ((zerop ay) (%math-lin (* ax by) (* bx by)))
      (t (error "not linear (product of two variables)")))))

(defun %math-lin-div (x y)
  "Divide linear form by a constant linear form."
  (let ((ay (%math-lin-a y)) (by (%math-lin-b y)))
    (unless (zerop ay) (error "not linear (divide by variable)"))
    (when (zerop by) (error "division by zero"))
    (%math-lin (/ (%math-lin-a x) by) (/ (%math-lin-b x) by))))

(defun %math-lin-pow (x y)
  "Only constant^constant or (linear)^0/1 for linearity."
  (let ((ay (%math-lin-a y)) (by (%math-lin-b y)))
    (unless (zerop ay) (error "not linear (variable exponent)"))
    (cond
      ((zerop by) (%math-lin 0 1))
      ((= by 1) x)
      ((zerop (%math-lin-a x)) (%math-lin 0 (expt (%math-lin-b x) by)))
      (t (error "not linear (power of variable)")))))

(defun %math-parse-linear (tokens var)
  "Parse TOKENS as linear form in VAR → (a . b) meaning a·var + b."
  (let ((out nil)
        (ops nil)
        (prec '(("u-" . 5) ("u+" . 5)
                ("^" . 4)
                ("*" . 3) ("/" . 3)
                ("+" . 2) ("-" . 2))))
    (labels ((p (op) (or (cdr (assoc op prec :test #'string=)) 0))
             (right-assoc (op)
               (or (string= op "^") (string= op "u-") (string= op "u+")))
             (unary (op) (or (string= op "u-") (string= op "u+")))
             (apply-op ()
               (let ((op (pop ops)))
                 (cond
                   ((unary op)
                    (let ((a (pop out)))
                      (unless a (error "arity"))
                      (push (if (string= op "u-")
                                (%math-lin (- (%math-lin-a a))
                                           (- (%math-lin-b a)))
                                a)
                            out)))
                   (t
                    (let ((b (pop out))
                          (a (pop out)))
                      (unless (and a b) (error "arity"))
                      (push
                       (cond
                         ((string= op "+") (%math-lin-add a b))
                         ((string= op "-") (%math-lin-sub a b))
                         ((string= op "*") (%math-lin-mul a b))
                         ((string= op "/") (%math-lin-div a b))
                         ((string= op "^") (%math-lin-pow a b))
                         (t (error "op ~A" op)))
                       out)))))))
      (dolist (tok tokens)
        (ecase (first tok)
          (:num (push (%math-lin 0 (second tok)) out))
          (:var
           (let ((v (second tok)))
             (unless (string= v var) (error "multiple variables"))
             (push (%math-lin 1 0) out)))
          (:op
           (let ((o (second tok)))
             (cond
               ((string= o "(") (push o ops))
               ((string= o ")")
                (loop while (and ops (not (string= (car ops) "(")))
                      do (apply-op))
                (when (and ops (string= (car ops) "(")) (pop ops)))
               (t
                (loop while (and ops
                                 (not (string= (car ops) "("))
                                 (let ((top (car ops)))
                                   (or (> (p top) (p o))
                                       (and (= (p top) (p o))
                                            (not (right-assoc o))))))
                      do (apply-op))
                (push o ops)))))))
      (loop while ops do
        (when (member (car ops) '("(" ")") :test #'string=)
          (error "mismatched parentheses"))
        (apply-op))
      (unless (and out (null (cdr out)))
        (error "bad expression"))
      (car out))))

(defun %math-format-linear (L var)
  "Pretty-print a·var + b."
  (let* ((a (%math-lin-a L))
         (b (%math-lin-b L))
         (as (%math-format-number a))
         (bs (%math-format-number b)))
    (cond
      ((and (zerop a) (zerop b)) "0")
      ((zerop a) bs)
      ((zerop b)
       (cond ((= a 1) var)
             ((= a -1) (format nil "-~A" var))
             (t (format nil "~A·~A" as var))))
      ((plusp b)
       (cond ((= a 1) (format nil "~A + ~A" var bs))
             ((= a -1) (format nil "-~A + ~A" var bs))
             (t (format nil "~A·~A + ~A" as var bs))))
      (t
       (let ((absb (%math-format-number (abs b))))
         (cond ((= a 1) (format nil "~A - ~A" var absb))
               ((= a -1) (format nil "-~A - ~A" var absb))
               (t (format nil "~A·~A - ~A" as var absb))))))))

(defun %math-detect-var (s)
  "First single-letter variable in S, or NIL."
  (cl-ppcre:register-groups-bind (v)
      ("([A-Za-z])" s)
    (string-downcase v)))

(defun %math-split-equation (s)
  "Return (values lhs rhs) if S contains exactly one '=', else NIL."
  (let ((parts (cl-ppcre:split "=" (or s "") :limit 3)))
    (when (and (= (length parts) 2)
               (plusp (length (first parts)))
               (plusp (length (second parts))))
      (values (string-trim '(#\Space #\Tab) (first parts))
              (string-trim '(#\Space #\Tab) (second parts))))))

;;; ---- Worked steps (show the work) --------------------------------

(defun %math-op-glyph (op)
  (cond ((string= op "*") "×")
        ((string= op "/") "÷")
        ((string= op "+") "+")
        ((string= op "-") "−")
        ((string= op "^") "^")
        ((string= op "u-") "−")
        ((string= op "u+") "+")
        (t op)))

(defun %math-to-rpn (tokens)
  "Shunting-yard → reverse-polish token list (same ops as %math-parse-expr)."
  (let ((out nil)
        (ops nil)
        (prec '(("u-" . 5) ("u+" . 5)
                ("^" . 4)
                ("*" . 3) ("/" . 3)
                ("+" . 2) ("-" . 2))))
    (labels ((p (op) (or (cdr (assoc op prec :test #'string=)) 0))
             (right-assoc (op)
               (or (string= op "^") (string= op "u-") (string= op "u+"))))
      (dolist (tok tokens)
        (ecase (first tok)
          (:num (push tok out))
          (:var (push tok out))
          (:op
           (let ((o (second tok)))
             (cond
               ((string= o "(") (push o ops))
               ((string= o ")")
                (loop while (and ops (not (string= (car ops) "(")))
                      do (push (list :op (pop ops)) out))
                (when (and ops (string= (car ops) "(")) (pop ops)))
               (t
                (loop while (and ops
                                 (not (string= (car ops) "("))
                                 (let ((top (car ops)))
                                   (or (> (p top) (p o))
                                       (and (= (p top) (p o))
                                            (not (right-assoc o))))))
                      do (push (list :op (pop ops)) out))
                (push o ops)))))))
      (loop while ops do
        (when (member (car ops) '("(" ")") :test #'string=)
          (error "mismatched parentheses"))
        (push (list :op (pop ops)) out))
      (nreverse out))))

(defun %math-apply-binary (op a b)
  (cond
    ((string= op "+") (+ a b))
    ((string= op "-") (- a b))
    ((string= op "*") (* a b))
    ((string= op "/")
     (if (zerop b) (error "division by zero") (/ a b)))
    ((string= op "^") (expt a b))
    (t (error "op ~A" op))))

(defun %math-arith-steps (tokens)
  "Evaluate pure arithmetic TOKENS with PEMDAS steps.
   Returns (values value final-string steps) where each step is
   (:work \"a × b\" :mid \"result\")."
  (let ((rpn (%math-to-rpn tokens))
        (stack nil)
        (steps nil))
    (dolist (tok rpn)
      (ecase (first tok)
        (:num
         (let ((n (second tok)))
           (push (list :v n :s (%math-format-number-short n)) stack)))
        (:var (error "bare variable in pure arithmetic"))
        (:op
         (let ((o (second tok)))
           (cond
             ((or (string= o "u-") (string= o "u+"))
              (let* ((a (pop stack))
                     (v (if (string= o "u-") (- (getf a :v)) (getf a :v)))
                     (s (%math-format-number-short v))
                     (work (format nil "~A~A" (%math-op-glyph o) (getf a :s))))
                (unless (string= work s)
                  (push (list :work work :mid s) steps))
                (push (list :v v :s s) stack)))
             (t
              (let* ((b (pop stack))
                     (a (pop stack))
                     (v (%math-apply-binary o (getf a :v) (getf b :v)))
                     (s (%math-format-number-short v))
                     (work (format nil "~A ~A ~A"
                                   (getf a :s) (%math-op-glyph o) (getf b :s))))
                (push (list :work work :mid s) steps)
                (push (list :v v :s s) stack))))))))
    (unless (and stack (null (cdr stack)))
      (error "bad expression"))
    (let* ((top (car stack))
           (val (getf top :v))
           (final (%math-format-number val :approx t)))
      (values val final (nreverse steps)))))

(defun %math-equation-steps (lhs rhs var)
  "Linear solve with isolation steps. Returns (values sol final-str steps)."
  (let* ((Ll (%math-parse-linear (%math-tokenize lhs) var))
         (Lr (%math-parse-linear (%math-tokenize rhs) var))
         (ls (%math-format-linear Ll var))
         (rs (%math-format-linear Lr var))
         (steps nil))
    ;; work = original equation; mid = simplified form (one row is enough)
    (push (list :work (format nil "~A = ~A" lhs rhs)
                :mid (format nil "~A = ~A" ls rs))
          steps)
    (let* ((L (%math-lin-sub Ll Lr))
           (a (%math-lin-a L))
           (b (%math-lin-b L))
           (zero-form (%math-format-linear L var)))
      (push (list :work "collect terms (left − right = 0)"
                  :mid (format nil "~A = 0" zero-form))
            steps)
      (cond
        ((and (zerop a) (zerop b))
         (let ((fin (format nil "true for all ~A" var)))
           (values t fin (nreverse steps))))
        ((zerop a)
         (let ((fin (format nil "no solution")))
           (values nil fin (nreverse steps))))
        (t
         (unless (zerop b)
           (push (list :work
                       (if (plusp b)
                           (format nil "subtract ~A from both sides"
                                   (%math-format-number b))
                           (format nil "add ~A to both sides"
                                   (%math-format-number (abs b))))
                       :mid
                       (format nil "~A = ~A"
                               (%math-format-linear (%math-lin a 0) var)
                               (%math-format-number (- b))))
                 steps))
         (let ((sol (/ (- b) a))
               (rhs-s (%math-format-number (- b))))
           (unless (= a 1)
             (push (list :work (format nil "divide both sides by ~A"
                                       (%math-format-number a))
                         :mid (format nil "~A = ~A" var
                                      (%math-format-number sol)))
                   steps))
           (when (and (= a 1) (zerop b))
             ;; already n = 0 style from collect
             nil)
           (when (and (= a 1) (not (zerop b)))
             ;; mid already "n = k"
             nil)
           (let ((fin (format nil "~A = ~A" var (%math-format-number sol))))
             (values sol fin (nreverse steps)))))))))

(defun %math-simplify-steps (raw var)
  "Linear expression simplify steps (no equation)."
  (let* ((L (%math-parse-linear (%math-tokenize raw) var))
         (pretty (%math-format-linear L var))
         (steps (list (list :work (format nil "expand ~A" raw)
                            :mid pretty))))
    (if (zerop (%math-lin-a L))
        (let ((v (%math-lin-b L)))
          (values v (%math-format-number v) steps))
        (values L pretty steps))))

(defun %math-format-worked-text (steps final)
  "Plain multi-line worked solution for line/REPL mode."
  (with-output-to-string (o)
    (let ((n 0))
      (dolist (st steps)
        (incf n)
        (format o "~A~A  →  ~A"
                (if (> n 1) (string #\Newline) "")
                (getf st :work)
                (getf st :mid))))
    (format o "~%∴ ~A" final)))

(defun eval-math-expression (text)
  "Evaluate arithmetic or solve simple linear algebra with worked steps.
   Returns (values value final-string normalized-expr steps) or NIL.
   STEPS = list of (:work \"…\" :mid \"…\")."
  (handler-case
      (let* ((raw0 (%math-strip-question text))
             (raw0 (string-trim '(#\Space #\Tab #\Newline) raw0)))
        (unless (%math-looks-like-expr-p raw0)
          (return-from eval-math-expression nil))
        (multiple-value-bind (lhs rhs) (%math-split-equation raw0)
          (if lhs
              (let ((var (or (%math-detect-var raw0) "x")))
                (multiple-value-bind (sol fin steps)
                    (%math-equation-steps lhs rhs var)
                  (values sol fin raw0 steps)))
              (let ((var (%math-detect-var raw0)))
                (if var
                    (multiple-value-bind (val fin steps)
                        (%math-simplify-steps raw0 var)
                      (values val fin raw0 steps))
                    (let ((toks (%math-tokenize raw0)))
                      (multiple-value-bind (val fin steps)
                          (%math-arith-steps toks)
                        (values val fin raw0 steps))))))))
    (error () nil)))

(defun %iface-math-answer (question)
  "English freeform math — arithmetic + algebra with worked colored steps."
  (multiple-value-bind (val final expr steps) (eval-math-expression question)
    (when final
      (let* ((steps (or steps nil))
             ;; single-number input: no ops — just final
             (worked (%math-format-worked-text steps final)))
        (list :freeform :math
              :expression expr
              :value val
              :final final
              :steps steps
              :reply-text (if (and steps (plusp (length steps)))
                              worked
                              final)
              :source :math)))))

(defun iface-freeform-answer (sess question &key (mind nil) (generate-length 120))
  "English freeform pipeline (product):
   0) chitchat / identity / clock
   0b) math (1+2, 2+4(56/3), “what is …”)
   1) extractive multi-sentence answer from attachments
   2) built-in concept English
   3) KB about / English fact rendering
   4) TMS-gated external LLM if enabled
   5) optional pure-CL sketch only if *iface-sketch-generate* and text looks English
   Always returns :reply-text as user-facing English string — never garbage."
  (declare (ignore generate-length))
  (let* ((m (or mind (sess-mind sess)))
         (q (string-trim '(#\Space #\Tab #\Newline) (or question "")))
         ;; Capability symbols gate freeform surfaces (not kitchen-sink)
         (chat (if (fboundp 'symbol-nl-chitchat)
                   (symbol-nl-chitchat q m)
                   (%iface-chitchat q m)))
         (math (unless chat
                 (if (fboundp 'symbol-math-answer)
                     (symbol-math-answer q)
                     (%iface-math-answer q))))
         (math-know (unless (or chat math)
                      (and (fboundp 'symbol-math-knowledge-answer)
                           (symbol-math-knowledge-answer q m))))
         (local (unless (or chat math math-know)
                  (and (fboundp 'symbol-local-user-answer)
                       (symbol-local-user-answer q m))))
         (extractive (unless (or chat math math-know local)
                       (iface-extractive-answer sess q)))
         (nl-about (unless (or chat math math-know local extractive)
                     (and (fboundp 'symbol-nl-about-answer)
                          (symbol-nl-about-answer q m))))
         (concept (unless (or chat math math-know local extractive nl-about)
                    (if (fboundp 'symbol-nl-concept)
                        (symbol-nl-concept q)
                        (%iface-concept-answer q))))
         (kb-ans (unless (or chat math math-know local extractive nl-about concept)
                   (%iface-kb-about m q)))
         (kb-eng (unless (or chat math math-know local extractive nl-about concept kb-ans)
                   (%iface-kb-english-facts m q)))
         (ctx (ignore-errors (session-corpus sess))))
    (cond
      (chat chat)
      (math math)
      (math-know math-know)
      (local local)
      (nl-about nl-about)
      ;; 1) Real English from your documents
      (extractive
       (list* :freeform :from-attachments
              :matches (mapcar (lambda (h)
                                 (list :id (getf h :id)
                                       :kind (getf h :kind)
                                       :name (getf h :name)
                                       :score (getf h :score)
                                       :tokens (getf h :tokens)
                                       :snippet (getf h :snippet)))
                               (getf extractive :matches))
              extractive))
      (concept concept)
      ;; 2a) about-fact
      (kb-ans
       (let ((reply
              (cond
                ((and (consp kb-ans) (stringp (third kb-ans))) (third kb-ans))
                ((and (consp kb-ans) (stringp (second kb-ans)))
                 (format nil "~A" (or (third kb-ans) (second kb-ans))))
                (t (format nil "~A" kb-ans)))))
         (list :freeform :kb
               :answer kb-ans
               :reply-text reply
               :source :kb)))
      ;; 2b) related KB facts as English
      (kb-eng
       (list :freeform :kb-facts
             :reply-text kb-eng
             :source :kb-facts))
      ;; 3) External LLM when configured (TMS-gated inside)
      ((and (fboundp 'llm-enabled-p) (llm-enabled-p))
       (or (%iface-llm-answer m q :context ctx)
           (%iface-honest-unknown q)))
      ;; 4) Neural path OUT → explicit refuse (not silent unknown)
      ((not (nn-path-allowed-p m))
       (list :freeform :refuse
             :refused t
             :reason "TMS nn-path-enabled is OUT"
             :reply-text
             "I can't generate: neural path is disabled (TMS OUT). Use /nn enable, or attach notes / teach facts."
             :source :tms-out))
      ;; 5) Pure-CL sketch ONLY when explicitly enabled — never dump untrained LM garbage.
      ((and *iface-sketch-generate*
            (%iface-default-lm-name))
       (let* ((model (%iface-default-lm-name))
              (prompt (%iface-generate-prompt q ctx))
              (gen (handler-case
                       (nn-generate model :prompt prompt :length 120 :mind m)
                     (error () nil)))
              (clean (and gen (%iface-englishish-p gen))))
         (if clean
             (list :freeform :generate
                   :model model
                   :prompt prompt
                   :text gen
                   :reply-text gen
                   :source :generate)
             (%iface-honest-unknown q))))
      (t (%iface-honest-unknown q)))))

(defun %iface-format-reply (op result)
  "Human-readable string for the user line; keep structured :result separately."
  (cond
    ((and (consp result) (stringp (getf result :reply-text)))
     (getf result :reply-text))
    ((and (eq op :freeform) (consp result) (eq (getf result :freeform) :from-attachments))
     (format nil "From attachments: ~A"
             (or (getf (first (getf result :matches)) :snippet)
                 (prin1-to-string (getf result :matches)))))
    ((and (eq op :freeform) (consp result) (eq (getf result :freeform) :kb))
     (format nil "~A" (getf result :answer)))
    ((and (eq op :freeform) (consp result) (eq (getf result :freeform) :generate))
     (or (getf result :text) (getf result :reply-text) ""))
    ((and (eq op :freeform) (consp result) (eq (getf result :freeform) :refuse))
     (or (getf result :reply-text)
         (format nil "Refused: ~A" (getf result :reason))))
    ((and (eq op :freeform) (consp result) (eq (getf result :freeform) :unknown))
     (or (getf result :reply-text)
         (format nil "Unknown. ~A" (or (getf result :hint) ""))))
    ((and (consp result) (eq (getf result :error) (getf result :error))
          (getf result :error)
          (stringp (getf result :error)))
     (format nil "Error: ~A" (getf result :error)))
    (t (prin1-to-string result))))

(defun %iface-llm-command (payload)
  "Handle /llm … slash commands. Never echo full API keys."
  (let* ((rest (string-trim '(#\Space #\Tab #\Newline) (or payload "")))
         (parts (if (zerop (length rest))
                    nil
                    (cl-ppcre:split "\\s+" rest :limit 2)))
         (sub (string-downcase (or (first parts) "status")))
         (arg (second parts)))
    (handler-case
        (cond
          ((member sub '("" "status" "stat" "info") :test #'string=)
           (let ((st (llm-status)))
             (list :llm st
                   :reply-text
                   (format nil "LLM ~A~%  provider ~A~%  model    ~A~%  base     ~A~%  key      ~A~%~%Set: /llm key <API_KEY>   model: /llm model grok-3   clear: /llm clear"
                           (if (getf st :enabled) "ON" "OFF")
                           (getf st :provider)
                           (getf st :model)
                           (getf st :base-url)
                           (getf st :key-mask)))))
          ((member sub '("key" "set-key" "setkey" "apikey" "api-key") :test #'string=)
           (unless (and arg (plusp (length arg)))
             (return-from %iface-llm-command
               (list :error "usage"
                     :reply-text "Usage: /llm key <API_KEY>   (saved to ~/.metis/llm.key)")))
           (let ((r (llm-save-key! arg :persist t)))
             (list :llm r
                   :reply-text
                   (format nil "LLM key saved (~A). ~A~%File: ~A"
                           (getf r :key)
                           (getf (getf r :status) :summary)
                           (or (getf r :path) "runtime only")))))
          ((member sub '("clear" "unset" "delete" "rm") :test #'string=)
           (let ((r (llm-clear-key!)))
             (list :llm r
                   :reply-text
                   (format nil "LLM key cleared. ~A"
                           (getf (getf r :status) :summary)))))
          ((member sub '("off" "disable") :test #'string=)
           (set-config :llm-enabled nil)
           (list :llm (llm-status)
                 :reply-text "LLM disabled for this session (key kept). /llm on to re-enable."))
          ((member sub '("on" "enable") :test #'string=)
           (configure-llm!)
           (if (get-config :llm-api-key)
               (progn
                 (set-config :llm-enabled t)
                 (list :llm (llm-status)
                       :reply-text
                       (format nil "LLM enabled. ~A" (getf (llm-status) :summary))))
               (list :error "no-key"
                     :reply-text "No key set. Use: /llm key <API_KEY>")))
          ((member sub '("model") :test #'string=)
           (unless (and arg (plusp (length arg)))
             (return-from %iface-llm-command
               (list :error "usage" :reply-text "Usage: /llm model grok-3")))
           (let ((r (llm-set-model! arg)))
             (list :llm r
                   :reply-text (format nil "Model set to ~A. ~A"
                                       arg (getf (getf r :status) :summary)))))
          ((member sub '("base" "url" "base-url" "baseurl") :test #'string=)
           (unless (and arg (plusp (length arg)))
             (return-from %iface-llm-command
               (list :error "usage"
                     :reply-text "Usage: /llm base https://api.x.ai/v1")))
           (let ((r (llm-set-base-url! arg)))
             (list :llm r
                   :reply-text (format nil "Base URL set. ~A"
                                       (getf (getf r :status) :summary)))))
          ((member sub '("help" "?") :test #'string=)
           (list :reply-text
                 "/llm status
/llm key <API_KEY>     save to ~/.metis/llm.key + enable
/llm model <name>      e.g. grok-3
/llm base <url>        e.g. https://api.x.ai/v1
/llm on | off
/llm clear             remove key file"))
          (t
           ;; bare /llm <key> if it looks like a key
           (if (and (plusp (length rest))
                    (or (eql 0 (search "xai-" rest))
                        (eql 0 (search "sk-" rest))
                        (> (length rest) 20)))
               (%iface-llm-command (format nil "key ~A" rest))
               (list :error "unknown"
                     :reply-text
                     (format nil "Unknown /llm subcommand ~A. Try /llm help" sub)))))
      (error (e)
        (list :error (princ-to-string e)
              :reply-text (format nil "LLM command failed: ~A" e))))))

(defun %iface-dispatch (sess op payload)
  "Execute one parsed op; returns result object."
  (let ((m (sess-mind sess)))
    (case op
      (:empty (list :ok t :note :empty))
      (:quit (list :quit t
                   :reply-text "Goodbye. (quit / exit / /quit / Esc)"))
      (:symbol-pack
       (or (%iface-symbol-pack-command
            (format nil "/symbol-pack~@[ ~A~]" payload))
           (list :error "bad-symbol-pack"
                 :reply-text "Usage: /symbol-pack catalog|install|enable|disable|export|import|overlay|unload")))
      (:help
       (list :help
             '("@PATH                 (drop file in chat → extract + HARD train)"
               "/attach file PATH     (same: train for real, background brain)"
               "/attach PATH          (shortcut)"
               "/attach folder PATH   (all files; recursive train)"
               "/attach photo PATH [caption]"
               "/ingest PATH          (file or folder; extract+train)"
               "/watch folder PATH    (background brain trains new drops immediately)"
               "/watch poll | /watch stop"
               "/brain | /brain status | start | stop"
               "/llm | status | key KEY | model NAME | base URL | clear | on | off"
               "/context TEXT         (attach + hard train)"
               "/attachments"
               "/read ATT-ID"
               "/ask PATTERN"
               "/tell FACT"
               "/goal GOAL"
               "/need CAPABILITY"
               "/train text CORPUS    (hard continuous train)"
               "/train file PATH [name]"
               "/train attachments [name]"
               "/generate MODEL [prompt]"
               "/nn list | /nn enable | /nn disable"
               "/symbols list | info ID | enable ID | disable ID | backend"
               "/symbols catalog            (open knowledge packs, no payments)"
               "/symbol-pack catalog|install ID|enable|disable|export|import|overlay|unload"
               "/marketplace list | install PATH_OR_URL [id]  (open knowledge + signed code packs)"
               "/learn TEXT  (on-the-fly neocortex consolidate + replay)"
               "plain English: retrieve from attachments, else generate if path IN"
               "(lisp forms…)"
               "quit | exit | /quit | /exit | :q"
               "status | help")))
      (:status
       (append (session-status sess)
               (list :brain (brain-status))))
      (:attach-file
       (destructuring-bind (path &optional cap intensity) payload
         (let* ((intensity (or intensity :hard))
                (a (session-attach-file sess path :caption cap
                                        :train t :async t
                                        :intensity intensity))
                (tr (getf (att-meta a) :train)))
           (list :attached :file
                 :id (att-id a)
                 :size (att-size a)
                 :has-text (and (att-text a) t)
                 :method (getf (att-meta a) :extract-method)
                 :trained t
                 :train tr
                 :brain (brain-status)
                 :reply-text
                 (format nil "Attached ~A (~A chars). HARD train queued on brain (queue=~A)."
                         (att-name a)
                         (if (att-text a) (length (att-text a)) 0)
                         (brain-queue-depth))))))
      (:attach-folder
       (destructuring-bind (path &optional rest) payload
         (declare (ignore rest))
         (let ((r (session-attach-folder sess path :train t :async t
                                         :intensity :hard)))
           (list* :attached :folder
                  :reply-text
                  (format nil "Attached folder ~A: ~A files, ~A training (brain queue=~A)."
                          (getf r :folder) (getf r :attached) (getf r :trained)
                          (brain-queue-depth))
                  r))))
      (:ingest
       (destructuring-bind (path &optional rest) payload
         (declare (ignore rest))
         (let ((r (session-ingest-path sess path :train t :async t
                                       :intensity :hard)))
           (list* :ingested t
                  :reply-text
                  (format nil "Ingested ~A — train=HARD on brain. corpus-chars=~A queue=~A"
                          path (or (getf r :corpus-chars) 0) (brain-queue-depth))
                  r))))
      (:watch-folder
       (destructuring-bind (path &optional rest) payload
         (declare (ignore rest))
         (let ((r (session-watch-folder sess path :train t :async t
                                        :intensity :hard :auto-brain t)))
           (list :watching (getf r :watching)
                 :initial r
                 :brain (brain-status)
                 :reply-text
                 (format nil "Watching ~A — brain LIVE. New drops train immediately (no poll needed). Initial ~A file(s)."
                         (or (getf r :watching) (getf r :folder))
                         (or (getf r :attached) 0))))))
      (:watch-poll
       (let ((ev (session-watch-poll! sess)))
         (list :events ev
               :count (length ev)
               :brain (brain-status)
               :reply-text
               (format nil "Poll: ~A new file(s) ingested/trained. brain jobs-done=~A"
                       (length ev) (getf (brain-status) :jobs-done)))))
      (:watch-stop
       (remhash (sess-id sess) *session-folder-watches*)
       (list :watch-stopped t
             :reply-text (format nil "Stopped watching for session ~A." (sess-id sess))))
      (:brain
       (let ((sub (or payload "status")))
         (cond
           ((string= sub "start")
            (let ((r (brain-start!)))
              (list* :brain r
                     (list :reply-text
                           (format nil "Brain started. queue=~A" (brain-queue-depth))))))
           ((string= sub "stop")
            (let ((r (brain-stop!)))
              (list* :brain r
                     (list :reply-text "Brain stopped."))))
           (t
            (let ((st (brain-status)))
              (list :brain st
                    :reply-text
                    (format nil "Brain running=~A queue=~A jobs-done=~A watches=~A cycle=~A"
                            (getf st :running) (getf st :queue) (getf st :jobs-done)
                            (getf st :watches) (getf st :cycle))))))))
      (:llm
       (%iface-llm-command payload))
      (:attach-photo
       (destructuring-bind (path &optional cap) payload
         (let ((a (session-attach-photo sess path :caption cap)))
           (list :attached :photo
                 :id (att-id a)
                 :media-type (att-media-type a)
                 :size (att-size a)
                 :path (att-path a)))))
      (:attach-context
       (let ((a (session-attach-context sess payload :train t :async t
                                        :intensity :hard)))
         (list :attached :context
               :id (att-id a)
               :size (att-size a)
               :train (getf (att-meta a) :train)
               :reply-text
               (format nil "Context attached (~A chars). HARD train queued."
                       (att-size a)))))
      (:list-attachments
       (session-list-attachments sess))
      (:read-attachment
       (let ((a (session-get-attachment sess payload)))
         (if a
             (list :id (att-id a)
                   :kind (att-kind a)
                   :text (att-text a)
                   :path (att-path a)
                   :media-type (att-media-type a)
                   :caption (att-caption a))
             (list :error :unknown-attachment :id payload))))
      (:ask
       (let* ((pat (handler-case (%iface-read-form-string payload)
                     (error () payload)))
              (ans (if (stringp pat)
                       (ask m (list 'about pat))
                       (ask m pat))))
         (list :ask pat :answer ans
               :reply-text (if ans
                               (format nil "~A" ans)
                               "No answer found."))))
      (:tell
       (let ((fact (%iface-read-form-string payload)))
         (tell m fact)
         (list :told fact
               :reply-text (format nil "Noted: ~A" fact))))
      (:goal
       (let* ((g (%iface-read-form-string payload))
              (ok (%epoch-try-achieve m g)))
         (list :goal g :achieved ok
               :holds (and (kb-holds-p (mind-kb m) g) t)
               :reply-text (format nil "Goal ~A — achieved=~A" g ok))))
      (:need
       (if (%iface-capability-present-p sess payload)
           (list :already payload
                 :reply-text (format nil "Already have ~A" payload))
           (multiple-value-bind (ok detail)
               (iface-accommodate sess payload)
             (list :accommodated ok
                   :detail detail
                   :present-after
                   (%iface-capability-present-p sess payload)
                   :reply-text
                   (if ok
                       (format nil "Accommodated capability ~A" payload)
                       (format nil "Could not accommodate ~A" payload))))))
      (:form
       (let ((r (interpret m payload)))
         (list :form payload :result r
               :reply-text (format nil "~A" r))))
      (:freeform
       (iface-freeform-answer sess payload :mind m))
      (t (list :error :unknown-op op)))))

(defun iface-turn (sess text)
  "One interactive turn. Multi-turn: call repeatedly on same SESS."
  (bt:with-recursive-lock-held ((sess-lock sess))
    (incf (sess-turn-count sess))
    (let* ((m (sess-mind sess))
           (pre-facts (kb-count-facts (mind-kb m)))
           (result nil)
           (reply nil)
           (nn-cmd (ignore-errors (%iface-nn-commands sess text)))
           (sym-cmd (unless nn-cmd
                      (ignore-errors (%iface-symbol-commands text)))))
      (push (list :role :user :text text :time (now-iso))
            (sess-turns sess))
      (multiple-value-bind (op payload)
          (cond (nn-cmd (values :nn nn-cmd))
                (sym-cmd (values :symbols sym-cmd))
                (t (%iface-parse-turn text)))
        (setf result
              (handler-case
                  (cond
                    ((eq op :nn)
                     (case (first payload)
                       (:train-file
                        (let* ((path (second payload))
                               (name (or (third payload) "session-lm"))
                               (body (uiop:read-file-string path))
                               (q (session-train-on-text! sess body
                                                          :name name
                                                          :async t
                                                          :intensity :hard
                                                          :source :train-file)))
                          (list :train-file path :name name :queued q
                                :brain (brain-status)
                                :reply-text
                                (format nil "HARD train queued for ~A (~A chars)."
                                        path (length body)))))
                       (:train-text
                        (let ((q (session-train-on-text! sess (second payload)
                                                         :name "session-lm"
                                                         :async t
                                                         :intensity :hard
                                                         :source :train-text)))
                          (list :train-text t :queued q :brain (brain-status)
                                :reply-text
                                (format nil "HARD train queued (~A chars)."
                                        (length (second payload))))))
                       (:train-attachments
                        (let* ((name (or (second payload) "session-lm"))
                               (corpus (session-corpus sess))
                               (q (session-train-on-text! sess corpus
                                                          :name name
                                                          :async t
                                                          :intensity :hard
                                                          :source :train-attachments)))
                          (list :train-attachments name :queued q
                                :chars (length corpus)
                                :brain (brain-status)
                                :reply-text
                                (format nil "HARD train on attachments queued (~A chars)."
                                        (length corpus)))))
                       (:generate
                        (list :text
                              (nn-generate (second payload)
                                           :prompt (or (third payload) "")
                                           :length 200
                                           :mind m)))
                       (:nn-list (list :models (metis.nn:nn-registry-list)))
                       (:nn-enable (list :enabled (nn-enable-path m)))
                       (:nn-disable (list :disabled (nn-disable-path m)))
                       (t (list :error :bad-nn-cmd payload))))
                    ((eq op :symbols)
                     (case (first payload)
                       (:symbols-list (list :symbols (symbol-list-info)))
                       (:symbol-info (list :symbol (symbol-info (second payload))))
                       (:symbol-enable (enable-symbol! (second payload)))
                       (:symbol-disable (disable-symbol! (second payload)))
                       (:symbol-install
                        (install-symbol! (second payload)
                                         :id (third payload)))
                       (:marketplace-list
                        (symbol-marketplace-catalog))
                       (:marketplace-install
                        ;; External/remote installs require signature (signed norm).
                        (let ((src (second payload))
                              (id (third payload)))
                          (if (and (stringp src)
                                   (or (eql 0 (search "http://" src))
                                       (eql 0 (search "https://" src))
                                       (eql 0 (search "file://" src))
                                       (eql 0 (search "git" src))))
                              (install-symbol! src :id id :enable t
                                               :require-signature t
                                               :trust-remote t)
                              ;; Local path: require signature for marketplace path
                              (install-symbol! src :id id :enable t
                                               :require-signature t))))
                       (:nn-backend (list :backend (nn-backend-status)))
                       (t (list :error :bad-symbol-cmd payload))))
                    (t (%iface-dispatch sess op payload)))
                (error (e)
                  (list :error (princ-to-string e)
                        :reply-text (format nil "Error: ~A" e)))))
        (setf reply (%iface-format-reply op result))
        (push (list :role :assistant
                    :text reply
                    :result result
                    :time (now-iso)
                    :facts-delta (- (kb-count-facts (mind-kb m)) pre-facts))
              (sess-turns sess))
        ;; On-the-fly CLS: always attach hybrid explain + metrics on default path
        (let* ((hybrid
                (when (fboundp 'cognitive-unit)
                  (handler-case
                      (cognitive-unit m text
                                      :session sess
                                      :skip-act t
                                      :learn :auto
                                      :force-learn
                                      (or (and (consp result)
                                               (member (getf result :freeform)
                                                       '(:unknown) :test #'eq))
                                          (and (stringp text)
                                               (or (eql 0 (search "/learn" text
                                                                  :test #'char-equal))
                                                  (eql 0 (search "/teach" text
                                                                 :test #'char-equal))))))
                    (error (e)
                      (list :decision :error
                            :explain (when (fboundp 'make-explain-object)
                                       (make-explain-object
                                        :decision :error
                                        :supporters nil
                                        :tms-label (if (nn-path-allowed-p m) :in :out)
                                        :why (list (princ-to-string e))))
                            :metrics (when (fboundp 'hybrid-metrics)
                                       (ignore-errors (hybrid-metrics))))))))
               (explain (or (and (consp hybrid) (getf hybrid :explain))
                            (when (fboundp 'make-explain-object)
                              (make-explain-object
                               :decision (and (consp hybrid) (getf hybrid :decision))
                               :tms-label (if (nn-path-allowed-p m) :in :out)
                               :why (list "default iface hybrid attach")))))
               (metrics (or (and (consp hybrid) (getf hybrid :metrics))
                            (when (fboundp 'hybrid-metrics)
                              (ignore-errors (hybrid-metrics))))))
          (list :reply reply
                :result result
                :hybrid hybrid
                :explain explain
                :metrics metrics
                :turn (sess-turn-count sess)
                :session (session-status sess)
                :facts-delta (- (kb-count-facts (mind-kb m)) pre-facts)))))))

(defun iface-drive (turns &key (session nil))
  "Drive multi-turn without REPL. TURNS is list of user strings."
  (let ((s (or session (session-ensure))))
    (mapcar (lambda (turn) (iface-turn s turn)) turns)))

(defun iface-repl (&optional session)
  "Full interactive interface REPL (multi-turn, same process)."
  (let ((s (or session (session-ensure)))
        (*package* (find-package :metis)))
    (brain-start!)
    (format t "~%╔══════════════════════════════════════════════════════════╗~%")
    (format t "║  METIS INTERACTIVE INTERFACE                             ║~%")
    (format t "╚══════════════════════════════════════════════════════════╝~%")
    (format t "~A~%" (metis-version-string))
    (format t "~A~%~%" (iface-thesis))
    (format t "Session ~A — brain LIVE. @file trains hard; /watch folder for drops.~%~%"
            (sess-id s))
    (loop
      (format t "you> ")
      (finish-output)
      (let ((line (read-line *standard-input* nil :eof)))
        (when (or (eq line :eof) (null line))
          (return :eof))
        (let ((resp (iface-turn s line)))
          (format t "metis> ~A~%" (getf resp :reply))
          (when (and (consp (getf resp :result))
                     (getf (getf resp :result) :quit))
            (format t "Goodbye.~%")
            (return :quit)))))))

(defun iface-flagship (&key (turns nil))
  "Non-interactive multi-turn demo for logs/CI."
  (boot :bootstrap t :reset t)
  (let* ((s (session-create))
         (script (or turns
                     (list "help"
                           "status"
                           "(tell (iface-demo alive))"
                           "(ask (iface-demo ?x))"
                           "/need translator"
                           "/need translator"))))
    (format t "~%=== METIS IFACE FLAGSHIP ===~%")
    (format t "~A~%~%" (iface-thesis))
    (let ((out (iface-drive script :session s)))
      (dolist (r out)
        (format t "turn ~A: ~A~%" (getf r :turn) (getf r :reply)))
      (format t "session: ~S~%" (session-status s))
      (list :iface-flagship t
            :turns (length out)
            :session (session-status s)
            :responses out))))
