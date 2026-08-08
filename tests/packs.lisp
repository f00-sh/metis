;;;; packs.lisp — open-knowledge hybrid symbol packs + TUI key path tests
(in-package :metis/tests)

(def-suite :metis-packs
  :description "Hybrid symbol packs A1/B1/C1/E1 + open catalog + TUI keys")
(in-suite :metis-packs)

(defparameter *packs-scratch*
  #P"/tmp/grok-goal-0d8e7011fb43/implementer/packs-test/")

(test pack-manifest-a1-e1
  "Hybrid pack manifest validates open provenance fields (shipped API)."
  (let ((man (metis:make-symbol-pack-manifest
              :id "test-pack"
              :name "Test"
              :license "CC0-1.0"
              :sources (list (list :url "https://example.invalid/x"
                                   :license "CC0-1.0"
                                   :date "2026"
                                   :content-hash "abc"
                                   :note "pin"))
              :weights-policy :reproducible-from-data
              :repro-level :best-effort)))
    (is-true (metis:symbol-pack-validate-manifest man))
    (is (equal "test-pack" (getf man :id)))
    (is (equal "CC0-1.0" (getf man :license)))
    (is (getf man :sources))
    (is (getf man :build-recipe))
    (is (eq :reproducible-from-data (getf man :weights-policy)))))

(test pack-write-load-roundtrip
  "Write pack dir and load facts into mind via shipped load entry."
  (metis:boot :bootstrap t :reset t)
  (let* ((dir (merge-pathnames "mini/" *packs-scratch*))
         (man (metis:make-symbol-pack-manifest
               :id "mini-pack"
               :license "MIT"
               :sources (list (list :url "local://mini"
                                    :license "MIT"
                                    :date "2026"
                                    :content-hash "mini"
                                    :note "test"))
               :weights-policy :reproducible-from-data))
         (unique (list 'unique-pack-fact (get-universal-time) "packs-test")))
    (ensure-directories-exist dir)
    (metis:symbol-pack-write! dir man
                              :facts (list unique '(animal "okapi" "mammal"))
                              :rules '(((animalp ?a) ((animal ?a ?t)))))
    (let ((stats (metis:symbol-pack-load-into-mind! metis:*mind* dir)))
      (is (equal "mini-pack" (getf stats :id)))
      (is (>= (getf stats :facts) 2))
      (is (find unique (metis:facts metis:*mind*) :test #'equal)))))

(test pack-export-import-b1
  "Export mind snapshot and import into fresh mind — distinctive fact restored."
  (metis:boot :bootstrap t :reset t)
  (let* ((marker (list 'export-marker (get-universal-time) "b1"))
         (exdir (merge-pathnames "export-b1/" *packs-scratch*)))
    (metis:assert-fact metis:*mind* marker :support :test :forward nil)
    (ensure-directories-exist exdir)
    (let ((ex (metis:symbol-export-snapshot! metis:*mind* exdir :label "b1")))
      (is-true (getf ex :exported))
      (is (probe-file (merge-pathnames "manifest.lisp" exdir))))
    (let ((m2 (metis::make-fresh-mind)))
      (metis::init-mind-subsystems m2)
      (metis:symbol-import-snapshot! m2 exdir)
      (is (find marker (metis:facts m2) :test #'equal)))))

(test pack-layers-c1
  "Permanent enable/disable retracts pack facts; overlay unload removes them."
  (metis:boot :bootstrap t :reset t)
  (metis:symbol-pack-ensure-seeds!)
  (metis:symbol-pack-clear-layers!)
  (let* ((cat (metis:symbol-pack-catalog))
         (seeds (getf cat :catalog)))
    (is (>= (getf cat :count) 3))
    (flet ((fact-in-mind-p (pred-name second-val)
             (some (lambda (f)
                     (and (consp f) (symbolp (first f))
                          (string-equal (symbol-name (first f)) pred-name)
                          (equal (second f) second-val)))
                   (metis:facts metis:*mind*))))
      (let* ((dict (find "dict-en-lite" seeds
                         :key (lambda (e) (getf e :id)) :test #'string-equal))
             (path (getf dict :path)))
        (metis:symbol-pack-install! path :id "dict-en-lite")
        (let ((en (metis:symbol-pack-enable! "dict-en-lite" :mind metis:*mind*)))
          (is-true (getf en :enabled))
          (is-true (fact-in-mind-p "WORD-DEF" "cat"))
          (multiple-value-bind (hit layer kind)
              (metis:symbol-pack-query
               (list (intern "WORD-DEF" :metis) "cat"
                     "a small domesticated carnivorous mammal")
               :mind metis:*mind*)
            (is (and hit (consp hit)))
            (is (string-equal layer "dict-en-lite"))
            (is (eq kind :registry))))
        (let ((dis (metis:symbol-pack-disable! "dict-en-lite" :mind metis:*mind*)))
          (is-false (getf dis :enabled))
          (is (getf dis :retract))
          (is-false (fact-in-mind-p "WORD-DEF" "cat"))
          (is-false (metis:symbol-pack-query
                     (list (intern "WORD-DEF" :metis) "cat"
                           "a small domesticated carnivorous mammal")
                     :mind metis:*mind*))))
      (let* ((an (find "animals-lite" seeds
                       :key (lambda (e) (getf e :id)) :test #'string-equal))
             (ov (metis:symbol-pack-install! (getf an :path)
                                             :id "animals-lite"
                                             :temporary t
                                             :mind metis:*mind*)))
        (is-true (getf ov :temporary))
        (is-true (fact-in-mind-p "ANIMAL" "dolphin"))
        (multiple-value-bind (hit layer kind)
            (metis:symbol-pack-query
             (list (intern "ANIMAL" :metis) "dolphin" "mammal")
             :mind metis:*mind*)
          (is (and hit (consp hit)))
          (is (string-equal layer "animals-lite"))
          (is (eq kind :overlay)))
        (let ((un (metis:symbol-pack-overlay-unload! "animals-lite"
                                                     :mind metis:*mind*)))
          (is-true (getf un :unloaded))
          (is (getf un :retract))
          (is-false (find "animals-lite" metis:*symbol-pack-overlays*
                          :key (lambda (x) (getf x :id)) :test #'string-equal))
          (is-false (fact-in-mind-p "ANIMAL" "dolphin"))
          (is-false (metis:symbol-pack-query
                     (list (intern "ANIMAL" :metis) "dolphin" "mammal")
                     :mind metis:*mind*)))))))

(test pack-multi-owner-retract
  "Matrix: unique pack, registry+overlay share, base+overlay, base+permanent, live query."
  (metis:boot :bootstrap t :reset t)
  (metis:symbol-pack-clear-layers!)
  (let* ((dir (merge-pathnames "multi-owner/" *packs-scratch*))
         (pred (intern "MO-FACT" :metis))
         (unique (list pred "unique" "only-pack"))
         (shared (list pred "shared" "payload"))
         (base-f (list pred "base-pre" "from-base")))
    (ensure-directories-exist dir)
    (flet ((write-pack (sub id fact)
             (let ((p (merge-pathnames sub dir)))
               (metis:symbol-pack-write!
                p
                (metis:make-symbol-pack-manifest
                 :id id :license "MIT"
                 :sources (list (list :url (format nil "local://~A" id)
                                      :license "MIT" :date "2026"
                                      :content-hash id :note "t"))
                 :weights-policy :reproducible-from-data)
                :facts (list fact))
               p)))
      ;; --- (a) unique pack fact: enable→present, disable→gone ---
      (let ((p (write-pack "a/" "mo-unique" unique)))
        (metis:symbol-pack-install! p :id "mo-unique")
        (metis:symbol-pack-enable! "mo-unique" :mind metis:*mind*)
        (is (find unique (metis:facts metis:*mind*) :test #'equal)
            "a: unique fact present after enable")
        (metis:symbol-pack-disable! "mo-unique" :mind metis:*mind*)
        (is-false (find unique (metis:facts metis:*mind*) :test #'equal)
                  "a: unique fact gone after disable"))

      ;; --- (b) registry+overlay same F ---
      (let ((pr (write-pack "b-reg/" "mo-share-reg" shared))
            (po (write-pack "b-ov/" "mo-share-ov" shared)))
        (metis:symbol-pack-install! pr :id "mo-share-reg")
        (metis:symbol-pack-enable! "mo-share-reg" :mind metis:*mind*)
        (metis:symbol-pack-install! po :id "mo-share-ov" :temporary t
                                    :mind metis:*mind*)
        (is (= 2 (gethash shared metis:*symbol-pack-fact-refcount*)))
        (metis:symbol-pack-overlay-unload! "mo-share-ov" :mind metis:*mind*)
        (is (find shared (metis:facts metis:*mind*) :test #'equal)
            "b: unload overlay keeps registry-owned F")
        (multiple-value-bind (hit layer kind)
            (metis:symbol-pack-query shared :mind metis:*mind*)
          (is (equal hit shared))
          (is (string-equal layer "mo-share-reg"))
          (is (eq kind :registry)))
        (metis:symbol-pack-disable! "mo-share-reg" :mind metis:*mind*)
        (is-false (find shared (metis:facts metis:*mind*) :test #'equal)
                  "b: disable last owner removes F"))

      ;; --- (c) base-preexist + overlay same F: unload keeps base ---
      (metis:assert-fact metis:*mind* base-f :support :base-test :forward nil)
      (is (find base-f (metis:facts metis:*mind*) :test #'equal))
      (let ((po (write-pack "c-ov/" "mo-base-ov" base-f)))
        (metis:symbol-pack-install! po :id "mo-base-ov" :temporary t
                                    :mind metis:*mind*)
        (is-true (gethash base-f metis:*symbol-pack-base-pins*)
                 "c: base pin set when pack claims pre-existing F")
        (metis:symbol-pack-overlay-unload! "mo-base-ov" :mind metis:*mind*)
        (is (find base-f (metis:facts metis:*mind*) :test #'equal)
            "c: unload overlay must keep base F"))

      ;; --- (d) base-preexist + permanent enable: disable keeps base ---
      (let ((pr (write-pack "d-reg/" "mo-base-reg" base-f)))
        (metis:symbol-pack-install! pr :id "mo-base-reg")
        (metis:symbol-pack-enable! "mo-base-reg" :mind metis:*mind*)
        (is-true (gethash base-f metis:*symbol-pack-base-pins*))
        (metis:symbol-pack-disable! "mo-base-reg" :mind metis:*mind*)
        (is (find base-f (metis:facts metis:*mind*) :test #'equal)
            "d: disable pack must keep base F"))

      ;; --- (e) after shared unload, query is live-only (no ghost) ---
      (let ((pr (write-pack "e-reg/" "mo-live-reg" shared))
            (po (write-pack "e-ov/" "mo-live-ov" shared)))
        (metis:symbol-pack-install! pr :id "mo-live-reg")
        (metis:symbol-pack-enable! "mo-live-reg" :mind metis:*mind*)
        (metis:symbol-pack-install! po :id "mo-live-ov" :temporary t
                                    :mind metis:*mind*)
        (metis:symbol-pack-overlay-unload! "mo-live-ov" :mind metis:*mind*)
        (multiple-value-bind (hit layer kind)
            (metis:symbol-pack-query shared :mind metis:*mind*)
          (is (equal hit shared))
          (is (string-equal layer "mo-live-reg"))
          (is (eq kind :registry))
          (is (find shared (metis:facts metis:*mind*) :test #'equal)
              "e: query hit must still be in KB"))))))

(test pack-layered-query-precedence
  "Overlay beats registry when both match the same pattern family."
  (metis:boot :bootstrap t :reset t)
  (metis:symbol-pack-clear-layers!)
  (let* ((dir (merge-pathnames "prec/" *packs-scratch*))
         (topic (intern "TOPIC" :metis))
         (base-fact (list topic "water" "registry-definition"))
         (ov-fact (list topic "water" "overlay-definition"))
         (pat (list topic "water" (intern "?X" :metis))))
    (ensure-directories-exist dir)
    (metis:symbol-pack-write!
     (merge-pathnames "reg/" dir)
     (metis:make-symbol-pack-manifest
      :id "prec-reg" :license "MIT"
      :sources (list (list :url "local://prec-reg" :license "MIT"
                           :date "2026" :content-hash "r" :note "t"))
      :weights-policy :reproducible-from-data)
     :facts (list base-fact))
    (metis:symbol-pack-install! (merge-pathnames "reg/" dir) :id "prec-reg")
    (metis:symbol-pack-enable! "prec-reg" :mind metis:*mind*)
    (metis:symbol-pack-write!
     (merge-pathnames "ov/" dir)
     (metis:make-symbol-pack-manifest
      :id "prec-ov" :license "MIT"
      :sources (list (list :url "local://prec-ov" :license "MIT"
                           :date "2026" :content-hash "o" :note "t"))
      :weights-policy :reproducible-from-data)
     :facts (list ov-fact))
    (metis:symbol-pack-install! (merge-pathnames "ov/" dir)
                                :id "prec-ov" :temporary t
                                :mind metis:*mind*)
    (multiple-value-bind (hit layer kind)
        (metis:symbol-pack-query pat :mind metis:*mind*)
      (is (equal hit ov-fact))
      (is (string-equal layer "prec-ov"))
      (is (eq kind :overlay)))
    (metis:symbol-pack-overlay-unload! "prec-ov" :mind metis:*mind*)
    (multiple-value-bind (hit layer kind)
        (metis:symbol-pack-query pat :mind metis:*mind*)
      (is (equal hit base-fact))
      (is (string-equal layer "prec-reg"))
      (is (eq kind :registry)))
    (metis:symbol-pack-disable! "prec-reg" :mind metis:*mind*)
    (is-false (metis:symbol-pack-query pat :mind metis:*mind*))))

(test pack-marketplace-open
  "Open catalog has seeds, no payments; install by id."
  (metis:boot :bootstrap t :reset t)
  (metis:symbol-pack-ensure-seeds!)
  (let ((m (metis:symbol-marketplace-catalog)))
    (is-true (getf m :marketplace))
    (is-false (getf m :payments))
    (is (>= (getf m :count) 3))
    (is (equal "symbols" (getf m :unit)))
    (is-false (find "gpu-nn" (getf m :packages)
                    :key (lambda (p) (getf p :id)) :test #'string-equal)))
  (let ((r (metis:symbol-pack-catalog-install "cl-docs-lite")))
    (is-true (getf r :installed))))

(test tui-keys-tab-ctrl-csi
  "Shipped TUI key helpers: Tab is data; Ctrl+T symbols; CSI not garbage text."
  (is (equal (metis::%tui-byte-event 9)
             (list :insert (string #\Tab))))
  (is (eq (metis::%tui-byte-event 20) :focus-toggle))
  (is (eq (metis::%tui-byte-event 18) :popup-repl))
  (is (eq (metis::%tui-byte-event 19) :popup-settings))
  (is (eq (metis::%tui-csi-event "27;2;13~") :newline))
  (is (eq (metis::%tui-csi-event "27;1;13~") :enter))
  (let ((app (metis::make-tui-app)))
    (metis::%tui-input-append app "ab")
    (metis::%tui-input-append app (string #\Tab))
    (is (= 9 (char-code (char (metis::tui-input app) 2))))
    (metis::%tui-backspace! app)
    (is (string= "ab" (metis::tui-input app)))
    (metis::%tui-set-input! app "a[27;2;13~a")
    (is (string= "aa" (metis::tui-input app)))
    (setf (metis::tui-focus app) :chat)
    (metis::%tui-focus-toggle! app)
    (is (eq :symbols (metis::tui-focus app)))
    (metis::%tui-popup-open! app :settings)
    (is (eq :settings (metis::tui-popup app)))
    (metis::%tui-popup-close! app)
    (is-false (metis::tui-popup app))))

(test symbol-runtime-capabilities
  "Default symbols boot: math/NL/local-user gate freeform; NL varies."
  (metis:boot :bootstrap t :reset t)
  (is-true (metis:symbol-capability-enabled-p :math))
  (is-true (metis:symbol-capability-enabled-p :nl))
  (is-true (metis:symbol-capability-enabled-p :local-user))
  (let ((tree (metis:symbol-tree-model)))
    (is (consp tree))
    (is (>= (length tree) 1)))
  (let ((m (metis:symbol-math-answer "what is 2+2")))
    (is (consp m))
    (is (eq :math (getf m :freeform))))
  (metis:symbol-toggle! "math" :mind metis:*mind*)
  (is-false (metis:symbol-capability-enabled-p :math))
  (is-false (metis:symbol-math-answer "2+2"))
  ;; re-enable
  (metis:symbol-toggle! "math" :mind metis:*mind*)
  (is-true (metis:symbol-capability-enabled-p :math))
  (let ((a (metis:symbol-nl-chitchat "hello" metis:*mind*))
        (b (metis:symbol-nl-pick "hello" :salt 1))
        (c (metis:symbol-nl-pick "hello" :salt 2)))
    (is (consp a))
    (is (stringp (getf a :reply-text)))
    (is (stringp b))
    (is (stringp c)))
  (metis:set-config :local-learning nil)
  (is-false (metis:symbol-local-learning-p))
  (metis:set-config :local-learning t)
  (is-true (metis:symbol-local-learning-p))
  (is (find "math" (metis:symbol-loaded-summary) :test #'string-equal)))
