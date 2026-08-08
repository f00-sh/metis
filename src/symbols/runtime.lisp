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
                       :capabilities '(:nl :chitchat :concepts :language)
                       :facets '(:use :about)))
         :facts '((capability natural-language "english freeform surface")
                  (capability chitchat "greetings identity creative play")
                  (nl-concept "noun" "A noun names a person, place, thing, or idea (cat, Metis, freedom).")
                  (nl-concept "verb" "A verb expresses action or state (run, is, load).")
                  (nl-concept "adjective" "An adjective modifies a noun (quick, sealed, dual-facet).")
                  (nl-concept "sentence" "A sentence is a complete thought, usually subject + predicate.")
                  (nl-concept "english" "English is a West Germanic language; Metis NL packs provide Use+About surfaces in English.")
                  (word-def "symbol" "in Metis: a sealed knowledge pack you load on demand")
                  (word-def "facet" "a dual surface of a symbol: e.g. use/about for language, process/knowledge for math"))
         :corpus (list "Natural language symbol: Use facet for dialogue; About for metalanguage."
                       "Richer packs: lang-en-conversation, dict-en-lite, slang-en-lite, lang-en-about."
                       "Load domain symbols for specialized knowledge; never kitchen-sink weights."))))
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
  "Load/enable or unload/disable symbol ID. Returns status plist.
   Unload uses dep refcount: shared deps of other loaded symbols stay loaded."
  (let ((m (or mind *mind* (boot)))
        (id (string id)))
    (cond
      ;; currently loaded (overlay or enabled) → refcount-safe unload
      ((or (find id *symbol-pack-overlays*
                 :key (lambda (x) (getf x :id)) :test #'string-equal)
           (gethash id *symbol-pack-enabled*))
       (let ((r (if (fboundp 'symbol-seal-unload!)
                    (symbol-seal-unload! id :mind m)
                    (progn
                      (when (find id *symbol-pack-overlays*
                                  :key (lambda (x) (getf x :id))
                                  :test #'string-equal)
                        (symbol-pack-overlay-unload! id :mind m))
                      (when (gethash id *symbol-pack-enabled*)
                        (symbol-pack-disable! id :mind m))
                      (%symbol-unregister-caps! id)
                      (list :unloaded t :id id)))))
         (list* :action :unloaded r)))
      ;; sealed package preferred when present
      ((probe-file (merge-pathnames
                    (format nil "~A/header.lisp" id)
                    (symbol-sealed-root)))
       (let ((r (symbol-seal-load!
                 (merge-pathnames (format nil "~A/" id) (symbol-sealed-root))
                 :mind m :temporary temporary)))
         (list* :action :enabled r)))
      ;; installed in registry → enable
      ((probe-file (merge-pathnames
                    (format nil "~A/manifest.lisp" id)
                    (symbol-pack-registry-dir)))
       (let ((r (symbol-pack-enable! id :mind m))
             (man (symbol-pack-read-manifest
                   (merge-pathnames (format nil "~A/" id)
                                    (symbol-pack-registry-dir)))))
         (%symbol-register-caps-from-manifest! id man)
         (symbol-mark-explicit-loaded! id)
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
               (symbol-mark-explicit-loaded! id)
               (list* :action :overlay r))
             (progn
               (symbol-pack-install! seed :id id :mind m)
               (let ((r (symbol-pack-enable! id :mind m)))
                 (%symbol-register-caps-from-manifest! id man)
                 (symbol-mark-explicit-loaded! id)
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
        "Unknown so far. With local-user loaded and local learning on, (tell (user-name \"…\")) sticks."))
    ;; --- richer USE surface (core NL pack + conversation pack) ---
    ("sing"
     . ("♪ Metis hums a little Common Lisp lullaby: cons and cdr under a silver moon, load a symbol, learn a tune. ♪ (Not a music model — just English play.)"
        "I can offer words, not a studio vocal: \"Oh give me a stack, where the lambdas run free…\" Want a poem instead, or a real domain symbol?"
        "Here's a tiny song-in-text: verse one — ask me math; verse two — @ a file; chorus — symbols on demand, never kitchen-sink blues."))
    ("joke"
     . ("Why did the Lisp programmer get lost? Too many CARs without a MAP."
        "I told my TMS a joke. It justified laughing only after checking the premises."
        "Parallel parking and parent matching: both improve with more practice and fewer free variables."))
    ("poem"
     . ("Quiet stack, open paren — / a mind of rules and replay. / Load what you need; leave the rest unseen."
        "Symbols sleep until you call them; / facts pin lightly, truth can fall. / Ask again — English answers, honest when thin."
        "Green text on a dark pane — / you type \"sing\", I answer plain. / Not a trillion weights of weather: / just the packs we load together."))
    ("story"
     . ("Short story: A researcher opened Metis empty. They loaded math, then language, then a folder of notes. By evening the mind explained their own files — and refused the rest. The end (for now)."
        "Once there was a kitchen-sink model that knew everything poorly. Metis took the other path: small sealed symbols, dual facets, and a user who chose what to load. The model stayed honest."
        "In a lab of cold CPUs, a hybrid mind waited. \"Sing,\" said the human. It sang in words. \"Prove,\" they said. It planned. Symbols, not vibes."))
    ("bored"
     . ("Try: 2+4(56/3), @PATH on a notes file, Ctrl+T for symbols, or (tell (about \"topic\" \"fact\")). Or load lang-en-conversation / dict-en-lite for richer talk."
        "Challenge mode: teach me three facts with local-user, then ask me them back. Or watch a folder with /watch folder PATH."
        "I'm not bored — I'm under-provisioned until you load packs. Algebra, animals-lite, dict-en-lite, or your own sealed domain."))
    ("sorry"
     . ("No hard feelings. Try rephrasing, attach a note, or load a richer language pack (lang-en-conversation)."
        "It's fine. If I missed context, @PATH or /context TEXT helps."
        "Apology accepted. What should we do next?"))
    ("encourage"
     . ("You've got this. Break the problem into a fact, a question, and a check."
        "Small steps: one symbol, one file, one question. Momentum follows."
        "Keep going — load what you need and ask specifically."))
    ("weather"
     . ("I don't have live weather. Attach a forecast note with @PATH, set an LLM key for open-world, or ask something I can do offline (math, your files, loaded packs)."
        "No sensors here — only symbols and session memory. Drop a weather text file if you want me to summarize it."))
    ("how-to"
     . ("General how-to: say what you want in English; for skills, type help; for math, type an expression; for your docs, @PATH; for domains, Ctrl+T and load a symbol."
        "Start with: (1) load the right symbol, (2) attach material if needed, (3) ask a concrete question. help lists slash commands."))
    ("what-should"
     . ("If you're stuck: load natural-language + math, try a simple expression, then @ a small notes file. Or open symbols and enable dict-en-lite / lang-en-conversation."
        "Good defaults: teach local-user a fact, ask it back; then try a domain pack. What goal are you aiming at?"))
    ("yes"
     . ("Understood."
        "Okay."
        "Got it."))
    ("no"
     . ("Okay — we can try another angle."
        "Alright. What instead?"
        "Fine. Tell me the better path."))
    ("laugh"
     . ("Ha. Fair."
        "Heh — noted."
        "I'll take the smile as a receipt."))
    ("love"
     . ("Appreciate the warmth. I'm software — I'll return usefulness: ask, teach, or load a pack."
        "Kind words logged. What shall we build or learn next?"))
    ("confused"
     . ("Let's simplify: one sentence for the goal, then one fact you already know. Or type help."
        "Confusion is data. Point at the last reply that didn't land, or attach the source text."
        "Try a smaller question, or load lang-en-about / dict-en-lite for definitions."))
    ("slang-hi"
     . ("Yo. Metis online — load packs, don't drown in a kitchen sink."
        "Sup. Symbols on demand; talk English, compute math, teach local-user."
        "Hey hey. Ctrl+T for the tree; ask plain or load slang-en-lite for more register.")))
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

(defun %symbol-nl-reply (intent &key salt args source)
  (list :freeform :chat
        :reply-text (or (symbol-nl-pick intent :salt salt :args args)
                        (format nil "~A" intent))
        :source (or source :nl-symbol)
        :facet :use))

(defun %symbol-nl-chitchat-variants (question mind)
  "USE facet: broad English dialogue when NL/language packs are loaded.
   Richer packs add banks via symbol-nl-ingest-pack-facts! — never letter-salad."
  (let* ((q (string-trim '(#\Space #\Tab #\Newline #\.) (or question "")))
         (qd (string-downcase q))
         (salt (sxhash qd)))
    (cond
      ((zerop (length qd)) nil)
      ;; greetings (incl. light slang)
      ((cl-ppcre:scan "^(hi|hello|hey|howdy|yo|hiya|sup|good\\s+(morning|afternoon|evening))\\b[!?.]*$" qd)
       (if (cl-ppcre:scan "^(yo|sup)\\b" qd)
           (%symbol-nl-reply "slang-hi" :salt salt :source :nl-use)
           (%symbol-nl-reply "hello" :salt salt)))
      ((cl-ppcre:scan "^(thanks|thank you|thx|ty)\\b" qd)
       (%symbol-nl-reply "thanks" :salt salt))
      ((cl-ppcre:scan "^(bye|goodbye|see you|later|cya)\\b" qd)
       (%symbol-nl-reply "bye" :salt salt))
      ((cl-ppcre:scan "how are you|how('?s| is) it going|how you doing" qd)
       (%symbol-nl-reply "howareyou" :salt salt
                         :args (list (or (ignore-errors (metis-version-string)) ""))))
      ((or (cl-ppcre:scan "what('?s| is) your name" qd)
           (cl-ppcre:scan "who are you" qd)
           (cl-ppcre:scan "what are you" qd)
           (string= qd "name"))
       (%symbol-nl-reply "identity" :salt salt))
      ((cl-ppcre:scan "what can you (do|help)|help me|how do (i|you) use" qd)
       (%symbol-nl-reply "help-cap" :salt salt))
      ((cl-ppcre:scan "what day is it|what('?s| is) (the )?date|today('?s)? date" qd)
       (multiple-value-bind (s m h day mon year)
           (decode-universal-time (get-universal-time) 0)
         (declare (ignore s m h))
         (list :freeform :chat
               :reply-text
               (format nil "On this machine's clock (UTC): ~4,'0D-~2,'0D-~2,'0D."
                       year mon day)
               :source :time :facet :use)))
      ((and mind (cl-ppcre:scan "who am i|what is my name" qd))
       (%symbol-nl-reply "whoami" :salt salt))
      ;; creative / social use (richer packs amplify banks)
      ((cl-ppcre:scan "sing( a song)?|song for me|sing something" qd)
       (%symbol-nl-reply "sing" :salt salt :source :nl-use))
      ((cl-ppcre:scan "tell me a joke|make me laugh|joke\\b" qd)
       (%symbol-nl-reply "joke" :salt salt :source :nl-use))
      ((cl-ppcre:scan "write (me )?a poem|poem about|poetry" qd)
       (%symbol-nl-reply "poem" :salt salt :source :nl-use))
      ((cl-ppcre:scan "tell me a story|short story|story about" qd)
       (%symbol-nl-reply "story" :salt salt :source :nl-use))
      ((cl-ppcre:scan "i('?m| am) bored|this is boring|entertain me" qd)
       (%symbol-nl-reply "bored" :salt salt :source :nl-use))
      ((cl-ppcre:scan "^(sorry|my bad|apologies)\\b" qd)
       (%symbol-nl-reply "sorry" :salt salt))
      ((cl-ppcre:scan "encourage me|i need motivation|cheer me up" qd)
       (%symbol-nl-reply "encourage" :salt salt))
      ((cl-ppcre:scan "weather|temperature outside|forecast" qd)
       (%symbol-nl-reply "weather" :salt salt))
      ((cl-ppcre:scan "how (do|can|should) i |how to " qd)
       (%symbol-nl-reply "how-to" :salt salt))
      ((cl-ppcre:scan "what should i (do|try|ask)|i('?m| am) stuck" qd)
       (%symbol-nl-reply "what-should" :salt salt))
      ((cl-ppcre:scan "^(yes|yep|yeah|yup|ok|okay|sure)\\b[!?.]*$" qd)
       (%symbol-nl-reply "yes" :salt salt))
      ((cl-ppcre:scan "^(no|nope|nah)\\b[!?.]*$" qd)
       (%symbol-nl-reply "no" :salt salt))
      ((cl-ppcre:scan "^(lol|haha|heh|lmao)\\b" qd)
       (%symbol-nl-reply "laugh" :salt salt))
      ((cl-ppcre:scan "i love you|love ya" qd)
       (%symbol-nl-reply "love" :salt salt))
      ((cl-ppcre:scan "i('?m| am) confused|doesn'?t make sense|what does that mean\\??$" qd)
       (%symbol-nl-reply "confused" :salt salt))
      ;; bare "what" / "why" — still English, not garbage
      ((member qd '("what" "why" "how" "huh" "?" "??" "???") :test #'string=)
       (list :freeform :chat
             :reply-text
             "Need a bit more: try a full question (what is X?), a math expression, @PATH for your notes, or load dict-en-lite / lang-en-conversation for richer language."
             :source :nl-use :facet :use))
      (t nil))))

(defun symbol-nl-ingest-pack-facts! (&optional mind)
  "Pull (nl-phrase intent text) and (nl-concept topic text) from MIND into live banks.
   Language packs call this on enable so richer packs stack without kitchen-sink weights."
  (let ((m (or mind *mind*))
        (n 0))
    (when m
      (dolist (f (facts m))
        (when (and (consp f) (symbolp (first f)))
          (let ((head (string-upcase (symbol-name (first f)))))
            (cond
              ((and (string= head "NL-PHRASE")
                    (stringp (second f)) (stringp (third f)))
               (symbol-nl-bank-add! (second f) (list (third f)))
               (incf n))
              ((and (string= head "NL-CONCEPT")
                    (stringp (second f)) (stringp (third f)))
               (symbol-nl-concept-add! (second f) (third f))
               (incf n)))))))
    n))

(defparameter *nl-concept-extra* (make-hash-table :test #'equal)
  "topic → definition text contributed by loaded language packs.")

(defun symbol-nl-concept-add! (topic text)
  (setf (gethash (string-downcase (string topic)) *nl-concept-extra*)
        (or text ""))
  topic)

(defun symbol-nl-concept-lookup (topic)
  (gethash (string-downcase (string topic)) *nl-concept-extra*))

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
    ;; Language packs may contribute phrase/concept tables via pack facts.
    (when (some (lambda (c)
                  (member (%cap-key c)
                          '("nl" "chitchat" "concepts" "language" "slang")
                          :test #'string-equal))
                caps)
      (ignore-errors (symbol-nl-ingest-pack-facts! *mind*)))
    ;; Model-package / adapter conditioning on house chat spine
    (when (fboundp 'symbol-model-on-enable!)
      (ignore-errors (symbol-model-on-enable! id man)))
    t))

(defun %symbol-unregister-caps! (id)
  (maphash (lambda (k ids)
             (when (member id ids :test #'string-equal)
               (symbol-capability-unregister! k id)))
           *symbol-capabilities*)
  (symbol-facet-unregister! id)
  (when (fboundp 'symbol-model-on-disable!)
    (ignore-errors (symbol-model-on-disable! id)))
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
  "KNOWLEDGE facet: explain/recall from loaded math-domain facts (not compute).
   Matches DOMAIN-DEF / DOMAIN-IDENTITY only — not CAPABILITY meta rows.
   Only for about-questions — never a substitute for value-of / prove (reason-act)."
  (unless (and (symbol-capability-enabled-p :math)
               (or (symbol-facet-enabled-p :knowledge)
                   (symbol-capability-enabled-p :math)))
    (return-from symbol-math-knowledge-answer nil))
  ;; Refuse to regurgitate as solve: only when reason-act owns the turn as :query.
  (when (and (fboundp 'parse-reason-act)
             (let ((a (ignore-errors (parse-reason-act question))))
               (and a (eq (getf a :act) :query))))
    (return-from symbol-math-knowledge-answer nil))
  (let* ((m (or mind *mind*))
         (q (string-downcase (or question "")))
         (stop '("tell" "about" "what" "whats" "what's" "from" "loaded"
                 "please" "with" "this" "that" "have" "does" "into"
                 "symbol" "symbols" "math" "know" "knowledge" "a" "an" "the"))
         ;; Strip punctuation so "limit?" matches DOMAIN-DEF "limit"
         (tokens (remove-if
                  (lambda (tok)
                    (or (<= (length tok) 2)
                        (member tok stop :test #'string-equal)))
                  (mapcar (lambda (tok)
                            (string-trim
                             '(#\? #\! #\. #\, #\; #\: #\" #\' #\( #\) #\[ #\])
                             tok))
                          (cl-ppcre:split "\\s+" q))))
         (hits nil))
    (when m
      (dolist (f (facts m))
        (when (and (consp f)
                   (symbolp (first f))
                   (member (string-upcase (symbol-name (first f)))
                           '("DOMAIN-DEF" "DOMAIN-IDENTITY")
                           :test #'string=))
          (let ((s (string-downcase (format nil "~{~A~^ ~}" f))))
            (when (some (lambda (tok)
                          (and (plusp (length tok))
                               (search tok s)))
                        tokens)
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
    (or
     ;; pack-contributed concepts
     (let* ((toks (cl-ppcre:all-matches-as-strings
                   "[a-z][a-z\\-]{2,}" (string-downcase (or question ""))))
            (hit (dolist (t0 toks)
                   (let ((d (symbol-nl-concept-lookup t0)))
                     (when (and d (plusp (length d)))
                       (return (list :freeform :nl-concept
                                     :reply-text d
                                     :topic t0
                                     :source :nl-pack-concept
                                     :facet :about)))))))
       hit)
     (%iface-concept-answer question))))

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
                      (search "definition" q)
                      (search "grammar" q)
                      (search "slang" q)
                      (search "noun" q)
                      (search "verb" q)
                      (search "adjective" q)
                      (search "adverb" q)
                      (search "pronoun" q)
                      (search "sentence" q)
                      (search "english" q)
                      (search "language" q)
                      (search "word" q)))
         (hits nil))
    (unless about-p (return-from symbol-nl-about-answer nil))
    ;; ingest any newly loaded pack tables
    (ignore-errors (symbol-nl-ingest-pack-facts! m))
    (let ((stop '("what" "whats" "what's" "is" "are" "the" "a" "an" "of"
                  "for" "to" "in" "on" "and" "or" "how" "does" "do" "mean"
                  "define" "definition" "please" "me" "my" "your")))
      (when m
        (dolist (f (facts m))
          (when (and (consp f)
                     (symbolp (first f))
                     (member (string-upcase (symbol-name (first f)))
                             '("WORD-DEF" "DOMAIN-DEF" "NL-CONCEPT")
                             :test #'string=))
            (let* ((s (format nil "~{~A~^ ~}" f))
                   (sd (string-downcase s))
                   (toks (remove-if
                          (lambda (tok)
                            (or (<= (length tok) 2)
                                (member tok stop :test #'string-equal)))
                          (cl-ppcre:split "\\s+" q))))
              (when (and toks
                         (some (lambda (tok) (search tok sd)) toks))
                (push s hits)))))))
    (or (when hits
          (list :freeform :nl-about
                :reply-text
                (format nil "About the language (loaded symbol):~%~{• ~A~%~}"
                        (subseq hits 0 (min 6 (length hits))))
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
  "Boot open-knowledge + core capability symbols (math, NL, local-user).
   Clears pack enable/layer/dep session state so residual installs cannot
   shadow auto-loaded dep tracking across reboots."
  (clrhash *symbol-capabilities*)
  (clrhash *symbol-facet-store*)
  (when (boundp '*symbol-dep-pins*) (clrhash *symbol-dep-pins*))
  (when (boundp '*symbol-required-deps*) (clrhash *symbol-required-deps*))
  (when (boundp '*symbol-auto-loaded*) (clrhash *symbol-auto-loaded*))
  (when (boundp '*symbol-pack-enabled*) (clrhash *symbol-pack-enabled*))
  (when (fboundp 'symbol-pack-clear-layers!) (symbol-pack-clear-layers!))
  (symbol-pack-boot!)
  (symbol-ensure-core-packs!)
  (when defaults
    (symbol-default-enable! :mind (or mind *mind*)))
  t)
