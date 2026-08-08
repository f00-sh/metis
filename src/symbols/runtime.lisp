;;;; runtime.lisp — capability symbols: math / NL / local-user (game-changer layer)
;;;; Loaded packs are not kitchen-sink weights; they gate and supply knowledge.
(in-package :metis)

(defparameter *symbol-capabilities* (make-hash-table :test #'equal)
  "capability keyword/string → list of pack ids that provide it.")

(defparameter *symbol-categories*
  '((:core . "core")
    (:language . "language")
    (:reasoning . "reasoning")
    (:science . "science")
    (:reference . "reference")
    (:local . "local")
    (:user . "user-learned"))
  "Display categories for the symbols pane tree.")

(defparameter *symbol-default-ids*
  '("natural-language" "math" "local-user")
  "Default open-knowledge symbols enabled at boot.")

(defun %cap-key (c)
  (string-downcase (string c)))

(defun symbol-capability-register! (cap pack-id)
  (let* ((k (%cap-key cap))
         (cur (gethash k *symbol-capabilities*)))
    (unless (member pack-id cur :test #'string-equal)
      (setf (gethash k *symbol-capabilities*)
            (cons pack-id cur)))
    t))

(defun symbol-capability-unregister! (cap pack-id)
  (let ((k (%cap-key cap)))
    (setf (gethash k *symbol-capabilities*)
          (remove pack-id (gethash k *symbol-capabilities*)
                  :test #'string-equal))
    (unless (gethash k *symbol-capabilities*)
      (remhash k *symbol-capabilities*))
    t))

(defun symbol-capability-enabled-p (cap)
  "T if some loaded/enabled pack currently provides CAP."
  (let ((ids (gethash (%cap-key cap) *symbol-capabilities*)))
    (and ids
         (some (lambda (id)
                 (or (gethash id *symbol-pack-enabled*)
                     (find id *symbol-pack-overlays*
                           :key (lambda (x) (getf x :id))
                           :test #'string-equal)
                     (%pack-layer-get id)))
               ids))))

(defun symbol-pack-capabilities (manifest-or-id)
  "Capabilities list from a manifest plist or pack id."
  (let ((man (if (stringp manifest-or-id)
                 (ignore-errors
                   (symbol-pack-read-manifest
                    (merge-pathnames (format nil "~A/" manifest-or-id)
                                     (symbol-pack-registry-dir))))
                 manifest-or-id)))
    (or (getf man :capabilities)
        (getf man :caps)
        nil)))

;;; %symbol-register-caps-from-manifest! / %symbol-unregister-caps!
;;; defined below with dual-facet registration (product law).

;;; ---- ensure default knowledge packs exist ------------------------

(defun symbol-ensure-core-packs! ()
  "Create default capability packs (math, natural-language, local-user) if missing."
  (let ((root (symbol-pack-seed-root)))
    (ensure-directories-exist root)
    ;; math — pure capability + tiny fact seed (engine stays in interface)
    (let ((d (merge-pathnames "math/" root)))
      (unless (probe-file (merge-pathnames "manifest.lisp" d))
        (symbol-pack-write!
         d
         (make-symbol-pack-manifest
          :id "math"
          :name "Mathematics"
          :version "1.0.0"
          :description "Arithmetic & linear algebra with worked steps (PEMDAS)"
          :license "MIT"
          :sources (list (list :url "local://metis/math"
                               :license "MIT" :date (%pack-now)
                               :content-hash "math-engine"
                               :note "engine: eval-math-expression"))
          :weights-policy :reproducible-from-data
          :extra (list :category :reasoning
                       :capabilities '(:math :reasoning)))
         :facts '((capability math "arithmetic and algebra")
                  (capability pemdas "order of operations"))
         :corpus (list "Math symbol: evaluate expressions with PEMDAS."
                       "Algebra: solve linear equations in one variable."))))
    ;; natural-language — chitchat + concept English
    (let ((d (merge-pathnames "natural-language/" root)))
      (unless (probe-file (merge-pathnames "manifest.lisp" d))
        (symbol-pack-write!
         d
         (make-symbol-pack-manifest
          :id "natural-language"
          :name "Natural Language"
          :version "1.0.0"
          :description "English chitchat, identity, concepts — freeform surface"
          :license "MIT"
          :sources (list (list :url "local://metis/nl"
                               :license "MIT" :date (%pack-now)
                               :content-hash "nl-core"
                               :note "chitchat + concept lexicon"))
          :weights-policy :reproducible-from-data
          :extra (list :category :language
                       :capabilities '(:nl :chitchat :concepts :language)))
         :facts '((capability natural-language "english freeform surface")
                  (capability chitchat "greetings and identity"))
         :corpus (list "Natural language symbol provides English dialogue."
                       "Load domain symbols for specialized knowledge."))))
    ;; local-user — user-taught, not set-in-stone
    (let ((d (merge-pathnames "local-user/" root)))
      (unless (probe-file (merge-pathnames "manifest.lisp" d))
        (symbol-pack-write!
         d
         (make-symbol-pack-manifest
          :id "local-user"
          :name "Local User Knowledge"
          :version "1.0.0"
          :description "What you taught Metis (tell/context/train) — live, not frozen"
          :license "user"
          :sources (list (list :url "local://user-session"
                               :license "user" :date (%pack-now)
                               :content-hash "live"
                               :note "session + mind facts with user support"))
          :weights-policy :reproducible-from-data
          :extra (list :category :local
                       :capabilities '(:local-user :user-learned)
                       :virtual t
                       :mutable t))
         :facts '((capability local-user "user-taught knowledge layer"))
         :corpus (list "Local user knowledge grows as you teach Metis."))))
    (list :core-packs t :root (namestring root))))

(defun symbol-default-enable! (&key (mind nil))
  "Install+enable default symbols (math, NL, local-user) into MIND."
  (symbol-ensure-core-packs!)
  (symbol-pack-ensure-seeds!)
  (let ((m (or mind *mind* (boot)))
        (enabled nil))
    (dolist (id *symbol-default-ids*)
      (handler-case
          (let* ((seed (merge-pathnames (format nil "~A/" id)
                                        (symbol-pack-seed-root)))
                 (man (and (probe-file (merge-pathnames "manifest.lisp" seed))
                           (symbol-pack-read-manifest seed))))
            (when man
              (symbol-pack-install! seed :id id :mind m)
              (symbol-pack-enable! id :mind m)
              (%symbol-register-caps-from-manifest! id man)
              (push id enabled)))
        (error (e)
          (metis-log :warn "default symbol ~A: ~A" id e))))
    (list :enabled (nreverse enabled))))

;;; ---- tree model for TUI symbols pane -----------------------------

(defun symbol-tree-model ()
  "Collapsible-tree data: list of categories → symbols with status.
   (:category name :open T :items ((:id :name :desc :enabled :temporary :virtual :caps)...))"
  (symbol-ensure-core-packs!)
  (symbol-pack-ensure-seeds!)
  (let* ((cat (symbol-pack-catalog))
         (entries (getf cat :catalog))
         (by-cat (make-hash-table :test #'equal)))
    (dolist (e entries)
      (let* ((man (ignore-errors (symbol-pack-read-manifest (getf e :path))))
             (c (or (getf man :category)
                    (getf e :category)
                    (cond
                      ((string-equal (getf e :id) "local-user") :local)
                      ((string-equal (getf e :id) "math") :reasoning)
                      ((string-equal (getf e :id) "natural-language") :language)
                      ((search "dict" (or (getf e :id) "") :test #'char-equal) :reference)
                      ((search "animal" (or (getf e :id) "") :test #'char-equal) :science)
                      (t :reference))))
             (ck (string-downcase (string c)))
             (id (getf e :id))
             (enabled (or (gethash id *symbol-pack-enabled*)
                          (and (%pack-layer-get id) t)))
             (temp (find id *symbol-pack-overlays*
                         :key (lambda (x) (getf x :id))
                         :test #'string-equal))
             (item (list :id id
                         :name (or (getf e :name) (getf man :name) id)
                         :description (or (getf e :description)
                                          (getf man :description) "")
                         :enabled (and enabled t)
                         :temporary (and temp t)
                         :virtual (getf man :virtual)
                         :mutable (getf man :mutable)
                         :license (or (getf e :license) (getf man :license))
                         :capabilities (symbol-pack-capabilities man)
                         :path (getf e :path)
                         :source (getf e :source))))
        (push item (gethash ck by-cat))))
    ;; stable category order
    (let ((order '("core" "language" "reasoning" "science" "reference" "local" "user-learned"))
          (out nil))
      (dolist (ck order)
        (let ((items (nreverse (gethash ck by-cat))))
          (when items
            (push (list :category ck
                        :label ck
                        :items items)
                  out)
            (remhash ck by-cat))))
      (maphash (lambda (ck items)
                 (push (list :category ck :label ck :items (nreverse items)) out))
               by-cat)
      (nreverse out))))

(defun symbol-toggle! (id &key (mind nil) (temporary nil))
  "Load/enable or unload/disable symbol ID. Returns status plist."
  (let ((m (or mind *mind* (boot)))
        (id (string id)))
    (cond
      ;; currently overlay → unload
      ((find id *symbol-pack-overlays*
             :key (lambda (x) (getf x :id)) :test #'string-equal)
       (let ((r (symbol-pack-overlay-unload! id :mind m)))
         (%symbol-unregister-caps! id)
         (list* :action :unloaded r)))
      ;; permanently enabled → disable
      ((gethash id *symbol-pack-enabled*)
       (let ((r (symbol-pack-disable! id :mind m)))
         (%symbol-unregister-caps! id)
         (list* :action :disabled r)))
      ;; installed in registry → enable
      ((probe-file (merge-pathnames
                    (format nil "~A/manifest.lisp" id)
                    (symbol-pack-registry-dir)))
       (let ((r (symbol-pack-enable! id :mind m))
             (man (symbol-pack-read-manifest
                   (merge-pathnames (format nil "~A/" id)
                                    (symbol-pack-registry-dir)))))
         (%symbol-register-caps-from-manifest! id man)
         (list* :action :enabled r)))
      ;; seed path → install then enable (or temp overlay)
      (t
       (let* ((seed (merge-pathnames (format nil "~A/" id)
                                     (symbol-pack-seed-root)))
              (man (and (probe-file (merge-pathnames "manifest.lisp" seed))
                        (symbol-pack-read-manifest seed))))
         (unless man (error "unknown symbol ~A" id))
         (if temporary
             (let ((r (symbol-pack-install! seed :id id :temporary t :mind m)))
               (%symbol-register-caps-from-manifest! id man)
               (list* :action :overlay r))
             (progn
               (symbol-pack-install! seed :id id :mind m)
               (let ((r (symbol-pack-enable! id :mind m)))
                 (%symbol-register-caps-from-manifest! id man)
                 (list* :action :enabled r)))))))))

;;; ---- NL phrase banks (data, not one-shot hardcodes) --------------
;;; Natural-language symbol owns surface variation. Banks are tables
;;; the pack can grow; selection rotates so replies feel alive without
;;; a kitchen-sink LLM.

(defparameter *nl-phrase-banks*
  '(("hello"
     . ("Hello. I'm Metis — a Common Lisp cognitive architecture. Ask anything, @ a file, or type help."
        "Hi. Metis here: hybrid symbolic + pure-CL neural mind. What should we work on?"
        "Hey. I'm Metis. Load symbols for domains; chat, teach, or @PATH to train."
        "Good to see you. Metis online — symbols on demand, not a kitchen-sink model."))
    ("thanks"
     . ("You're welcome."
        "Anytime."
        "Glad to help."
        "Happy to."))
    ("bye"
     . ("Goodbye. Type quit when you want to exit."
        "See you. /quit leaves the product cleanly."
        "Later. Your loaded symbols stay until you unload them."))
    ("howareyou"
     . ("Running. ~A Brain and session memory are up — ask a question or @ a file."
        "Solid. ~A Session live; background brain can train while we talk."
        "Here and learning. ~A Teach me facts or load a science symbol."))
    ("identity"
     . ("I'm Metis — an introspective hybrid mind in Common Lisp (symbolic reasoning + pure-CL neural training). Chat, learn from files, plan, explain."
        "Metis: open-knowledge symbols on demand, CLS-style continual learning, TMS-gated tools. Not a frozen 90B blob."
        "I am Metis. Load vetted symbols for math, language, domains; local-user holds what you teach me."))
    ("help-cap"
     . ("I can: answer in English (NL symbol); evaluate math (math symbol); recall what you taught (local-user); learn from @PATH; hard-train (/brain); reason with tell/ask/plan; external LLM if configured. Type help."
        "Surfaces track loaded symbols: NL for dialogue, math for expressions, local-user for your facts, domain packs for science. Attach files with @PATH. help lists commands."
        "Think symbols, not kitchen-sink weights. Enable what you need in the symbols pane (Ctrl+T). help for slash commands."))
    ("whoami"
     . ("I don't have a stored name for you yet. Tell me with (tell (user-name \"…\")) or /context."
        "No user-name fact yet — teach me with (tell (user-name \"…\")) when local learning is on."
        "Unknown so far. With local-user loaded and local learning on, (tell (user-name \"…\")) sticks.")))
  "Intent → list of English variants. Format ~A slots filled at pick time.")

(defun symbol-nl-bank-add! (intent phrases)
  "Extend/replace a phrase bank entry (live learning into NL surface)."
  (let* ((k (string-downcase (string intent)))
         (plist (mapcar #'identity phrases))
         (hit (assoc k *nl-phrase-banks* :test #'string=)))
    (if hit
        (setf (cdr hit) (append (cdr hit) plist))
        (push (cons k plist) *nl-phrase-banks*))
    k))

(defun symbol-nl-pick (intent &key (salt nil) (args nil))
  "Pick a variant from the NL bank. Salt rotates replies without hardcoding one line."
  (let* ((k (string-downcase (string intent)))
         (phrases (cdr (assoc k *nl-phrase-banks* :test #'string=)))
         (n (length phrases)))
    (when (plusp n)
      (let* ((idx (mod (sxhash (list k salt (floor (get-universal-time) 11)
                                     (or salt 0)))
                       n))
             (tpl (nth idx phrases)))
        (if args
            (apply #'format nil tpl args)
            tpl)))))

(defun %symbol-nl-chitchat-variants (question mind)
  "NL-symbol surface: same intents as core chat, variable English."
  (let* ((q (string-trim '(#\Space #\Tab #\Newline #\.) (or question "")))
         (qd (string-downcase q))
         (salt (sxhash qd)))
    (cond
      ((zerop (length qd)) nil)
      ((cl-ppcre:scan "^(hi|hello|hey|howdy|yo|hiya|good\\s+(morning|afternoon|evening))\\b[!?.]*$" qd)
       (list :freeform :chat
             :reply-text (or (symbol-nl-pick "hello" :salt salt)
                             "Hello. I'm Metis.")
             :source :nl-symbol))
      ((cl-ppcre:scan "^(thanks|thank you|thx|ty)\\b" qd)
       (list :freeform :chat
             :reply-text (or (symbol-nl-pick "thanks" :salt salt) "You're welcome.")
             :source :nl-symbol))
      ((cl-ppcre:scan "^(bye|goodbye|see you|later)\\b" qd)
       (list :freeform :chat
             :reply-text (or (symbol-nl-pick "bye" :salt salt) "Goodbye.")
             :source :nl-symbol))
      ((cl-ppcre:scan "how are you" qd)
       (list :freeform :chat
             :reply-text
             (or (symbol-nl-pick "howareyou" :salt salt
                                 :args (list (or (ignore-errors (metis-version-string)) "")))
                 "Running.")
             :source :nl-symbol))
      ((or (cl-ppcre:scan "what('?s| is) your name" qd)
           (cl-ppcre:scan "who are you" qd)
           (cl-ppcre:scan "what are you" qd)
           (string= qd "name"))
       (list :freeform :chat
             :reply-text (or (symbol-nl-pick "identity" :salt salt)
                             "I'm Metis.")
             :source :nl-symbol))
      ((cl-ppcre:scan "what can you (do|help)" qd)
       (list :freeform :chat
             :reply-text (or (symbol-nl-pick "help-cap" :salt salt)
                             "Type help for commands.")
             :source :nl-symbol))
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
             :reply-text (or (symbol-nl-pick "whoami" :salt salt)
                             "I don't have your name yet.")
             :source :nl-symbol))
      (t nil))))

;;; ---- local-user knowledge surface --------------------------------

(defun symbol-local-learning-p ()
  "Settings gate: local learning must be ON to use mutable user knowledge."
  (and (get-config :local-learning t) t))

(defun symbol-local-user-facts (&optional mind)
  "Facts taught by the user (supports that look like user learning)."
  (let ((m (or mind *mind*))
        (out nil))
    (when m
      (dolist (f (facts m))
        (when (and (consp f)
                   (member (first f)
                           ;; not ABOUT — those stay KB freeform priority
                           '(user-name user-fact taught note remember)
                           :test #'string-equal))
          (push f out))))
    (nreverse out)))

(defun symbol-local-user-answer (question &optional mind)
  "Answer from local-user when symbol enabled AND local learning is on."
  (unless (and (symbol-capability-enabled-p :local-user)
               (symbol-local-learning-p))
    (return-from symbol-local-user-answer nil))
  (let* ((m (or mind *mind*))
         (q (string-downcase (or question "")))
         (hits nil))
    (dolist (f (symbol-local-user-facts m))
      (let ((s (format nil "~{~A~^ ~}" f)))
        (when (some (lambda (tok)
                      (and (> (length tok) 2)
                           (search tok (string-downcase s))))
                    (cl-ppcre:split "\\s+" q))
          (push s hits))))
    (when hits
      (list :freeform :local-user
            :reply-text
            (format nil "From what you taught me:~%~{• ~A~%~}"
                    (subseq hits 0 (min 5 (length hits))))
            :source :local-user))))

;;; ---- freeform gates ----------------------------------------------

;;; ---- dual-facet product law --------------------------------------
;;; Math symbols: always (:knowledge :process)
;;; Language symbols: always (:use :about)
;;; Domain/history/etc.: default (:knowledge) only unless they ship a procedure.

(defparameter *symbol-facet-store* (make-hash-table :test #'equal)
  "pack-id → list of facet keywords currently provided by that pack.")

(defun symbol-facet-register! (id facets)
  (setf (gethash (string id) *symbol-facet-store*)
        (mapcar (lambda (f) (intern (string-upcase (string f)) :keyword))
                (or facets nil)))
  t)

(defun symbol-facet-unregister! (id)
  (remhash (string id) *symbol-facet-store*)
  t)

(defun symbol-facets-for (id)
  (gethash (string id) *symbol-facet-store*))

(defun symbol-facet-enabled-p (facet)
  "T if some loaded symbol currently provides FACET (:knowledge :process :use :about)."
  (let ((want (intern (string-upcase (string facet)) :keyword))
        (hit nil))
    (maphash
     (lambda (id facets)
       (when (and (member want facets)
                  (or (gethash id *symbol-pack-enabled*)
                      (find id *symbol-pack-overlays*
                            :key (lambda (x) (getf x :id)) :test #'string-equal)
                      (%pack-layer-get id)))
         (setf hit t)))
     *symbol-facet-store*)
    hit))

(defun symbol-default-facets-for-caps (caps)
  "Infer dual-facet product law from capability list."
  (let* ((cs (mapcar #'%cap-key (or caps nil)))
         (math-p (some (lambda (c)
                         (member c '("math" "algebra" "geometry" "trigonometry"
                                      "calculus" "statistics" "arithmetic" "reasoning")
                                 :test #'string-equal))
                       cs))
         (lang-p (some (lambda (c)
                         (member c '("nl" "chitchat" "concepts" "language" "slang")
                                 :test #'string-equal))
                       cs)))
    (cond
      (math-p '(:knowledge :process))
      (lang-p '(:use :about))
      (t '(:knowledge)))))

(defun %symbol-register-caps-from-manifest! (id man)
  (let ((caps (symbol-pack-capabilities man))
        (facets (or (getf man :facets)
                    (symbol-default-facets-for-caps
                     (symbol-pack-capabilities man)))))
    (dolist (c caps)
      (symbol-capability-register! c id))
    (symbol-facet-register! id facets)
    t))

(defun %symbol-unregister-caps! (id)
  (maphash (lambda (k ids)
             (when (member id ids :test #'string-equal)
               (symbol-capability-unregister! k id)))
           *symbol-capabilities*)
  (symbol-facet-unregister! id)
  t)

(defun symbol-math-answer (question)
  "PROCESS facet: compute only if math capability is loaded
   (math packs always register :process under dual-facet law)."
  (when (and (symbol-capability-enabled-p :math)
             (or (symbol-facet-enabled-p :process)
                 ;; no facet store yet (boot race) — capability alone
                 (null (let ((n 0))
                         (maphash (lambda (k v) (declare (ignore k v)) (incf n))
                                  *symbol-facet-store*)
                         n))))
    (%iface-math-answer question)))

(defun symbol-math-knowledge-answer (question &optional mind)
  "KNOWLEDGE facet: explain/recall from loaded math-domain facts (not compute)."
  (unless (and (symbol-capability-enabled-p :math)
               (or (symbol-facet-enabled-p :knowledge)
                   (symbol-capability-enabled-p :math)))
    (return-from symbol-math-knowledge-answer nil))
  (let* ((m (or mind *mind*))
         (q (string-downcase (or question "")))
         (hits nil))
    (when m
      (dolist (f (facts m))
        (when (and (consp f)
                   (symbolp (first f))
                   (member (string-upcase (symbol-name (first f)))
                           '("DOMAIN-DEF" "DOMAIN-IDENTITY" "CAPABILITY")
                           :test #'string=))
          (let ((s (format nil "~{~A~^ ~}" f)))
            (when (some (lambda (tok)
                          (and (> (length tok) 3)
                               (search tok (string-downcase s))))
                        (cl-ppcre:split "\\s+" q))
              (push s hits))))))
    (when hits
      (list :freeform :math-knowledge
            :reply-text
            (format nil "From loaded math symbols:~%~{• ~A~%~}"
                    (subseq hits 0 (min 5 (length hits))))
            :source :math-knowledge
            :facet :knowledge))))

(defun symbol-nl-chitchat (question mind)
  "USE facet: speak/interpret in natural language when NL symbol loaded."
  (when (and (or (symbol-capability-enabled-p :nl)
                 (symbol-capability-enabled-p :chitchat)
                 (symbol-capability-enabled-p :language))
             (or (symbol-facet-enabled-p :use)
                 (symbol-capability-enabled-p :nl)
                 (symbol-capability-enabled-p :language)))
    (or (%symbol-nl-chitchat-variants question mind)
        (%iface-chitchat question mind))))

(defun symbol-nl-concept (question)
  "ABOUT facet path for concepts when language/concepts capability loaded."
  (when (and (or (symbol-capability-enabled-p :nl)
                 (symbol-capability-enabled-p :concepts)
                 (symbol-capability-enabled-p :language))
             (or (symbol-facet-enabled-p :about)
                 (symbol-capability-enabled-p :concepts)
                 (symbol-capability-enabled-p :nl)))
    (%iface-concept-answer question)))

(defun symbol-nl-about-answer (question &optional mind)
  "ABOUT facet: metalanguage — answer questions about the language itself."
  (unless (and (or (symbol-capability-enabled-p :nl)
                   (symbol-capability-enabled-p :language)
                   (symbol-capability-enabled-p :concepts))
               (or (symbol-facet-enabled-p :about)
                   (symbol-capability-enabled-p :nl)))
    (return-from symbol-nl-about-answer nil))
  (let* ((m (or mind *mind*))
         (q (string-downcase (or question "")))
         (about-p (or (search "what is" q)
                      (search "what's" q)
                      (search "mean" q)
                      (search "define" q)
                      (search "grammar" q)
                      (search "slang" q)
                      (search "noun" q)
                      (search "verb" q)))
         (hits nil))
    (unless about-p (return-from symbol-nl-about-answer nil))
    (when m
      (dolist (f (facts m))
        (when (and (consp f)
                   (symbolp (first f))
                   (member (string-upcase (symbol-name (first f)))
                           '("WORD-DEF" "DOMAIN-DEF" "CAPABILITY")
                           :test #'string=))
          (let ((s (format nil "~{~A~^ ~}" f)))
            (when (some (lambda (tok)
                          (and (> (length tok) 2)
                               (search tok (string-downcase s))))
                        (cl-ppcre:split "\\s+" q))
              (push s hits))))))
    (or (when hits
          (list :freeform :nl-about
                :reply-text
                (format nil "About the language (loaded symbol):~%~{• ~A~%~}"
                        (subseq hits 0 (min 5 (length hits))))
                :source :nl-about
                :facet :about))
        (symbol-nl-concept question))))

(defun symbol-loaded-summary ()
  "Short list of currently loaded/enabled symbol ids for status UI."
  (let ((ids nil))
    (maphash (lambda (id on)
               (when on (push id ids)))
             *symbol-pack-enabled*)
    (dolist (o *symbol-pack-overlays*)
      (push (format nil "~A*" (getf o :id)) ids))
    (sort (delete-duplicates ids :test #'string-equal) #'string-lessp)))

(defun symbol-catalog-download! (id &key (mind nil) (enable t))
  "Install (copy seed into registry) and optionally enable — open catalog, no payment."
  (let* ((m (or mind *mind* (boot)))
         (r (symbol-pack-catalog-install id)))
    (when enable
      (handler-case (symbol-pack-enable! id :mind m)
        (error ())))
    (let ((man (ignore-errors
                 (symbol-pack-read-manifest
                  (merge-pathnames (format nil "~A/" id)
                                   (symbol-pack-registry-dir))))))
      (when man (%symbol-register-caps-from-manifest! id man)))
    (list :downloaded id :result r :enabled enable)))

(defun symbol-runtime-boot! (&key (mind nil) (defaults t))
  "Boot open-knowledge + core capability symbols (math, NL, local-user)."
  (clrhash *symbol-capabilities*)
  (clrhash *symbol-facet-store*)
  (symbol-pack-boot!)
  (symbol-ensure-core-packs!)
  (when defaults
    (symbol-default-enable! :mind (or mind *mind*)))
  t)
