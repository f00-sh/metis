;;;; seals.lisp — sealed symbol packages (open/private/tamper/load)
(in-package :metis/tests)

(def-suite :metis-seals
  :description "Sealed symbol format: open-sealed, private-sealed, verify, load")
(in-suite :metis-seals)

(defparameter *seal-scratch*
  #P"/tmp/grok-goal-cc94af1e1f42/implementer/seal-tests/")

(test seal-open-roundtrip-and-tamper
  "Open-sealed: seal via shipped API, opaque body, verify, load fact, refuse tamper."
  (metis:boot :bootstrap t :reset t)
  (let* ((dest (merge-pathnames "open-rt/" *seal-scratch*))
         (marker (list 'domain-def "seal-open-rt" "unit" "seal test unit fact"))
         (src (list :id "seal-open-rt"
                    :name "Seal Open RT"
                    :version "1.0.0"
                    :license "MIT"
                    :capabilities '(:test)
                    :bibliography '((:title "Fixture" :license "MIT"
                                     :url "https://example.invalid/seal"))
                    :facts (list marker '(capability test "x"))
                    :corpus '("unit: seal test unit fact"
                              "PLAINTEXT-NEEDLE-SHOULD-BE-OPAQUE"))))
    (ensure-directories-exist dest)
    (let ((seal (metis:symbol-seal! src dest :mode :open-sealed
                                    :trust-tier :community)))
      (is-true (getf seal :sealed))
      (is (equal "seal-open-rt" (getf seal :id)))
      (is-true (getf seal :opaque))
      (is-true (probe-file (merge-pathnames "body.mse" dest)))
      (is-true (probe-file (merge-pathnames "header.lisp" dest)))
      (is-true (probe-file (merge-pathnames "symbol.sig" dest))))
    (is-true (metis:symbol-seal-body-opaque-p
              dest :needles '("PLAINTEXT-NEEDLE-SHOULD-BE-OPAQUE"
                              "metis-seal-body")))
    (let ((v (metis:symbol-seal-verify dest :require t)))
      (is-true (getf v :ok))
      (is (equal "seal-open-rt" (getf v :id))))
    (let ((ld (metis:symbol-seal-load! dest :mind metis:*mind*)))
      (is-true (getf ld :loaded))
      (is (>= (getf ld :facts) 1))
      (is (find marker (metis:facts metis:*mind*) :test #'equal)))
    ;; tamper body → verify fails (shipped entry point)
    (with-open-file (out (merge-pathnames "body.mse" dest)
                         :direction :output :if-exists :append
                         :element-type '(unsigned-byte 8))
      (write-byte 255 out))
    (let ((bad (metis:symbol-seal-verify dest :require nil)))
      (is-false (getf bad :ok))
      (is (member (getf bad :reason)
                  '(:body-hash-mismatch :body-tamper :sig-mismatch)
                  :test #'eq)))
    (signals error (metis:symbol-seal-verify dest :require t))))

(test seal-private-key-gate
  "Private-sealed: wrong/missing key refuses; correct key loads."
  (metis:boot :bootstrap t :reset t)
  (let* ((dest (merge-pathnames "priv-rt/" *seal-scratch*))
         (fact (list 'secret-fact "private-only" 42))
         (src (list :id "seal-priv-rt" :version "1.0.0" :license "MIT"
                    :facts (list fact)
                    :corpus '("PRIVATE-CORPUS-NEEDLE"))))
    (ensure-directories-exist dest)
    (metis:symbol-seal! src dest :mode :private-sealed :key "correct-pass"
                        :trust-tier :unvetted)
    (is-true (getf (metis:symbol-seal-verify dest :require t) :ok))
    (is-true (metis:symbol-seal-body-opaque-p
              dest :needles '("PRIVATE-CORPUS-NEEDLE" "private-only")))
    (signals error (metis:symbol-seal-load! dest :mind metis:*mind*))
    (signals error (metis:symbol-seal-load! dest :mind metis:*mind*
                                            :key "wrong-pass"))
    (let ((ld (metis:symbol-seal-load! dest :mind metis:*mind*
                                       :key "correct-pass")))
      (is-true (getf ld :loaded))
      (is (find fact (metis:facts metis:*mind*) :test #'equal)))))

(test seal-train-build-path
  "Source kit → train → build (shipped APIs) produces loadable open-sealed pack."
  (metis:boot :bootstrap t :reset t)
  (let* ((id "seal-train-demo")
         (kit-root (merge-pathnames "kits/" *seal-scratch*))
         (new (metis:symbol-source-kit-new!
               id :root kit-root
               :description "train path fixture"
               :capabilities '(:demo)
               :bibliography '((:title "Demo" :license "MIT"
                                :url "https://example.invalid/demo"))))
         (kit (getf new :path)))
    (with-open-file (out (merge-pathnames "facts.lisp" kit)
                         :direction :output :if-exists :supersede)
      (let ((*print-pretty* t) (*package* (find-package :keyword)))
        (prin1 (list :facts
                     (list (list 'domain-def id "demo" "trained demo fact")))
               out)
        (terpri out)))
    (with-open-file (out (merge-pathnames "corpus/a.txt" kit)
                         :direction :output :if-exists :supersede)
      (format out "demo: trained demo fact~%"))
    (let ((tr (metis:symbol-train-from-kit! kit)))
      (is-true (getf tr :trained))
      (is (plusp (length (getf tr :facts)))))
    (let* ((dest (merge-pathnames (format nil "~A/" id) *seal-scratch*))
           (built (metis:symbol-build! kit :dest dest :mode :open-sealed
                                       :trust-tier :community
                                       :register-marketplace nil)))
      (is-true (getf built :built))
      (is-true (getf (metis:symbol-seal-verify dest :require t) :ok))
      (let ((ld (metis:symbol-seal-load! dest :mind metis:*mind*)))
        (is-true (getf ld :loaded))
        (is (some (lambda (f)
                    (and (consp f) (equal (second f) id)))
                  (metis:facts metis:*mind*)))))))

(test seal-math-five-shipped
  "Five math domain sealed packages exist, verify, and load domain-def facts."
  (metis:boot :bootstrap t :reset t)
  (let ((root (metis:symbol-sealed-root))
        (ids '("math" "algebra" "geometry" "trigonometry" "calculus")))
    (dolist (id ids)
      (let ((dir (merge-pathnames (format nil "~A/" id) root)))
        (is-true (probe-file (merge-pathnames "body.mse" dir))
                 (format nil "~A sealed body missing" id))
        (is-true (probe-file (merge-pathnames "header.lisp" dir)))
        (let* ((hdr (metis:symbol-seal-read-header dir))
               (bib (getf hdr :bibliography)))
          (is (equal id (getf hdr :id)))
          (is (consp bib) (format nil "~A bibliography empty" id)))
        (is-true (getf (metis:symbol-seal-verify dir :require t) :ok))
        (let ((ld (metis:symbol-seal-load! dir :mind metis:*mind*)))
          (is-true (getf ld :loaded))
          (is (some (lambda (f)
                      (and (consp f)
                           (symbolp (first f))
                           (string-equal (symbol-name (first f)) "DOMAIN-DEF")
                           (equal (second f) id)))
                    (metis:facts metis:*mind*))
              (format nil "~A domain-def not in mind after load" id)))))))

(defun %metis-symbol-cli (&rest args)
  "Drive shipped ./bin/metis symbol CLI (real path)."
  (let* ((root (asdf:system-source-directory :metis))
         (cli (namestring (merge-pathnames "bin/metis" root)))
         (cmd (append (list cli "symbol") args)))
    (multiple-value-bind (out err code)
        (uiop:run-program cmd
                          :output :string
                          :error-output :string
                          :ignore-error-status t)
      (list :code code :out out :err err :cmd cmd))))

(test seal-open-reproducible-fingerprint
  "Open-sealed: two seals of the same trained plist share body-sha256."
  (let* ((src (list :id "repro-open"
                    :version "1.0.0"
                    :license "MIT"
                    :facts '((domain-def "repro-open" "x" "stable fact one")
                             (symbol-trained "repro-open" "1.0.0" 1 1))
                    :corpus '("x: stable fact one")
                    :capabilities '(:test)))
         (d1 (merge-pathnames "repro-a/" *seal-scratch*))
         (d2 (merge-pathnames "repro-b/" *seal-scratch*)))
    (ensure-directories-exist d1)
    (ensure-directories-exist d2)
    (let ((s1 (metis:symbol-seal! src d1 :mode :open-sealed :trust-tier :community))
          (s2 (metis:symbol-seal! src d2 :mode :open-sealed :trust-tier :community)))
      (is (equal (getf s1 :body-sha256) (getf s2 :body-sha256))
          (format nil "open-sealed body hash not reproducible: ~A vs ~A"
                  (getf s1 :body-sha256) (getf s2 :body-sha256)))
      (is-true (getf (metis:symbol-seal-verify d1 :require t) :ok))
      (is-true (getf (metis:symbol-seal-verify d2 :require t) :ok)))))

(test seal-private-no-registry-plaintext
  "Private-sealed load must not leave secret facts/corpus in permanent registry."
  (metis:boot :bootstrap t :reset t)
  (let* ((dest (merge-pathnames "priv-noleak/" *seal-scratch*))
         (secret-line "TOP-SECRET-PRIVATE-CORPUS-LINE")
         (fact (list 'secret-fact "noleak" secret-line))
         (src (list :id "priv-noleak" :version "1.0.0" :license "MIT"
                    :facts (list fact)
                    :corpus (list secret-line))))
    (ensure-directories-exist dest)
    (metis:symbol-seal! src dest :mode :private-sealed :key "priv-key-99"
                        :trust-tier :unvetted)
    (let ((ld (metis:symbol-seal-load! dest :mind metis:*mind* :key "priv-key-99")))
      (is-true (getf ld :loaded))
      (is-true (getf ld :temporary))
      (is-true (getf ld :private))
      (is (find fact (metis:facts metis:*mind*) :test #'equal)))
    (let* ((reg (merge-pathnames "priv-noleak/"
                                 (metis::symbol-pack-registry-dir)))
           (pack (merge-pathnames "pack.lisp" reg))
           (corp (merge-pathnames "corpus.txt" reg)))
      (is-false (probe-file pack)
                "private-sealed must not permanent-install pack.lisp")
      (is-false (probe-file corp)
                "private-sealed must not permanent-install corpus.txt")
      (when (probe-file reg)
        (dolist (p (directory (merge-pathnames "*.*" reg)))
          (unless (uiop:directory-pathname-p p)
            (with-open-file (in p :element-type 'character :if-does-not-exist nil)
              (when in
                (let ((s (make-string (file-length in))))
                  (read-sequence s in)
                  (is-false (search secret-line s)
                            (format nil "secret leaked in ~A" p)))))))))))

(test seal-required-deps-refuse-or-autoload
  "Required depends-on: refuse when missing; auto-load from knowledge/sealed when present."
  (metis:boot :bootstrap t :reset t)
  (metis:symbol-pack-clear-layers!)
  ;; Refuse: dep id that does not exist
  (let* ((dest (merge-pathnames "needs-missing/" *seal-scratch*))
         (src (list :id "needs-missing" :version "1.0.0" :license "MIT"
                    :depends-on '((:id "totally-missing-dep-xyz" :role :required))
                    :facts '((domain-def "needs-missing" "a" "b")))))
    (ensure-directories-exist dest)
    (metis:symbol-seal! src dest :mode :open-sealed)
    (signals error
      (metis:symbol-seal-load! dest :mind metis:*mind* :auto-deps t)))
  ;; Autoload: algebra requires math; both shipped under knowledge/sealed/
  (let ((alg (merge-pathnames "algebra/" (metis:symbol-sealed-root))))
    (when (probe-file (merge-pathnames "body.mse" alg))
      (ignore-errors (metis:symbol-pack-disable! "math" :mind metis:*mind*))
      (ignore-errors (metis:symbol-pack-disable! "algebra" :mind metis:*mind*))
      (let ((ld (metis:symbol-seal-load! alg :mind metis:*mind* :auto-deps t)))
        (is-true (getf ld :loaded))
        ;; math must be present after auto-deps (enabled, overlay, or layer)
        (is-true (or (gethash "math" metis::*symbol-pack-enabled*)
                     (metis::%pack-layer-get "math")
                     (find "math" metis::*symbol-pack-overlays*
                           :key (lambda (x) (getf x :id))
                           :test #'string-equal)
                     (some (lambda (f)
                             (and (consp f)
                                  (equal (second f) "math")))
                           (metis:facts metis:*mind*))))))))

(test symbol-dep-refcount-keeps-shared-deps
  "Unload A does not unload dep shared by still-loaded B."
  (metis:boot :bootstrap t :reset t)
  (ignore-errors (metis:symbol-pack-disable! "math" :mind metis:*mind*))
  (ignore-errors (metis::%symbol-unregister-caps! "math"))
  (let* ((base (merge-pathnames "depbase/" *seal-scratch*))
         (a (merge-pathnames "depa/" *seal-scratch*))
         (b (merge-pathnames "depb/" *seal-scratch*)))
    (ensure-directories-exist base)
    (ensure-directories-exist a)
    (ensure-directories-exist b)
    ;; base dep symbol
    (metis:symbol-seal!
     (list :id "dep-base" :version "1.0.0" :license "MIT"
           :capabilities '(:math)
           :facets '(:knowledge :process)
           :facts '((domain-def "dep-base" "unit" "shared dependency unit")))
     base :mode :open-sealed)
    ;; two consumers that require dep-base
    (metis:symbol-seal!
     (list :id "dep-a" :version "1.0.0" :license "MIT"
           :capabilities '(:math)
           :depends-on '((:id "dep-base" :role :required))
           :facts '((domain-def "dep-a" "a" "consumer a")))
     a :mode :open-sealed)
    (metis:symbol-seal!
     (list :id "dep-b" :version "1.0.0" :license "MIT"
           :capabilities '(:math)
           :depends-on '((:id "dep-base" :role :required))
           :facts '((domain-def "dep-b" "b" "consumer b")))
     b :mode :open-sealed)
    ;; install base into sealed root so auto-deps can find it
    (let ((root (merge-pathnames "dep-base/" (metis:symbol-sealed-root))))
      (ensure-directories-exist root)
      (uiop:copy-file (merge-pathnames "header.lisp" base)
                      (merge-pathnames "header.lisp" root))
      (uiop:copy-file (merge-pathnames "body.mse" base)
                      (merge-pathnames "body.mse" root))
      (uiop:copy-file (merge-pathnames "symbol.sig" base)
                      (merge-pathnames "symbol.sig" root)))
    (metis:symbol-seal-load! a :mind metis:*mind*)
    (metis:symbol-seal-load! b :mind metis:*mind*)
    (is-true (metis::%seal-dep-loaded-p "dep-base"))
    (is (member "dep-a" (metis:symbol-dep-holders "dep-base") :test #'string-equal))
    (is (member "dep-b" (metis:symbol-dep-holders "dep-base") :test #'string-equal))
    ;; unload A — base must stay (B still pins it)
    (let ((u (metis:symbol-seal-unload! "dep-a" :mind metis:*mind*)))
      (is-true (getf u :unloaded))
      (is-true (metis::%seal-dep-loaded-p "dep-base")
               "shared dep-base must remain loaded while dep-b is live")
      (is (member "dep-b" (metis:symbol-dep-holders "dep-base") :test #'string-equal))
      (is-false (member "dep-a" (metis:symbol-dep-holders "dep-base")
                        :test #'string-equal)))
    ;; unload B — base may cascade if auto-loaded
    (metis:symbol-seal-unload! "dep-b" :mind metis:*mind*)
    (is-false (metis::%seal-dep-loaded-p "dep-a"))
    (is-false (metis::%seal-dep-loaded-p "dep-b"))))

(test dual-facet-math-knowledge-and-process
  "Math symbols: knowledge + process facets; unload removes both."
  (metis:boot :bootstrap t :reset t)
  ;; isolate fixture from default boot symbols
  (ignore-errors (metis:symbol-pack-disable! "math" :mind metis:*mind*))
  (ignore-errors (metis::%symbol-unregister-caps! "math"))
  (let* ((dest (merge-pathnames "df-math/" *seal-scratch*))
         (src (list :id "df-math" :version "1.0.0" :license "MIT"
                    :capabilities '(:math :reasoning)
                    :facets '(:knowledge :process)
                    :facts '((domain-def "df-math" "pemdas"
                               "parentheses exponents multiply divide add subtract")
                             (capability math "process+knowledge"))
                    :corpus '("pemdas: parentheses exponents multiply divide add subtract"))))
    (ensure-directories-exist dest)
    (metis:symbol-seal! src dest :mode :open-sealed :trust-tier :community)
    (metis:symbol-seal-load! dest :mind metis:*mind*)
    (is-true (metis:symbol-capability-enabled-p :math))
    (is-true (metis:symbol-facet-enabled-p :process))
    (is-true (metis:symbol-facet-enabled-p :knowledge))
    (let ((proc (metis:symbol-math-answer "what is 2+2")))
      (is (consp proc))
      (is (eq :math (getf proc :freeform))))
    (let ((know (metis:symbol-math-knowledge-answer "what is pemdas" metis:*mind*)))
      (is (consp know))
      (is (eq :math-knowledge (getf know :freeform)))
      (is (search "pemdas" (string-downcase (getf know :reply-text)))))
    (metis:symbol-pack-disable! "df-math" :mind metis:*mind*)
    (metis::%symbol-unregister-caps! "df-math")
    (is-false (metis:symbol-capability-enabled-p :math))
    (is-false (metis:symbol-math-answer "2+2"))
    (is-false (metis:symbol-math-knowledge-answer "pemdas" metis:*mind*))))

(test dual-facet-language-use-and-about
  "Language symbols: use + about; unload removes both."
  (metis:boot :bootstrap t :reset t)
  (ignore-errors (metis:symbol-pack-disable! "natural-language" :mind metis:*mind*))
  (ignore-errors (metis::%symbol-unregister-caps! "natural-language"))
  (let* ((dest (merge-pathnames "df-lang/" *seal-scratch*))
         (src (list :id "df-lang" :version "1.0.0" :license "MIT"
                    :capabilities '(:nl :language :concepts :chitchat)
                    :facets '(:use :about)
                    :facts '((word-def "noun" "a word that names a person place or thing")
                             (capability natural-language "use+about"))
                    :corpus '("noun: a word that names a person place or thing"))))
    (ensure-directories-exist dest)
    (metis:symbol-seal! src dest :mode :open-sealed :trust-tier :community)
    (metis:symbol-seal-load! dest :mind metis:*mind*)
    (is-true (metis:symbol-capability-enabled-p :nl))
    (is-true (metis:symbol-facet-enabled-p :use))
    (is-true (metis:symbol-facet-enabled-p :about))
    (let ((use (metis:symbol-nl-chitchat "hello" metis:*mind*)))
      (is (consp use))
      (is (stringp (getf use :reply-text))))
    (let ((about (metis:symbol-nl-about-answer "what is a noun" metis:*mind*)))
      (is (consp about))
      (is (search "noun" (string-downcase (getf about :reply-text)))))
    (metis:symbol-pack-disable! "df-lang" :mind metis:*mind*)
    (metis::%symbol-unregister-caps! "df-lang")
    (is-false (metis:symbol-capability-enabled-p :nl))
    (is-false (metis:symbol-nl-chitchat "hello" metis:*mind*))
    (is-false (metis:symbol-nl-about-answer "what is a noun" metis:*mind*))))

(test seal-cli-new-ingest-train-path
  "Shipped CLI: symbol new --name/--license, symbol ingest file.txt (guide §2–3)."
  (let* ((scratch (merge-pathnames "cli-kit/" *seal-scratch*))
         (id (format nil "cli-ingest-~A" (get-universal-time)))
         ;; place kit under default source-kit root via CLI, then ingest absolute file
         (txt (merge-pathnames "ingest-me.txt" scratch)))
    (ensure-directories-exist scratch)
    (with-open-file (out txt :direction :output :if-exists :supersede
                         :if-does-not-exist :create)
      (format out "cli-term: ingested by shipped symbol ingest CLI~%"))
    ;; new with flags advertised in help
    (let ((r (%metis-symbol-cli "new" id
                                "--name" "CLI Ingest Demo"
                                "--license" "MIT")))
      (is (zerop (getf r :code))
          (format nil "symbol new failed: ~A~%~A"
                  (getf r :out) (getf r :err)))
      (is (search id (getf r :out) :test #'char-equal)))
    (let* ((kit (merge-pathnames (format nil "~A/" id)
                                 (metis:symbol-source-kit-root)))
           (man (merge-pathnames "source-manifest.lisp" kit)))
      (is-true (probe-file man) "kit source-manifest missing after symbol new")
      ;; ingest — must not produce (list ( "path" )) illegal call
      (let ((r (%metis-symbol-cli "ingest" (namestring kit) (namestring txt))))
        (is (zerop (getf r :code))
            (format nil "symbol ingest failed: ~A~%~A"
                    (getf r :out) (getf r :err)))
        (is (search "INGESTED" (string-upcase (getf r :out)))))
      (is-true (probe-file (merge-pathnames "corpus/ingest-me.txt" kit))
               "ingest did not copy file into corpus/")
      (let ((r (%metis-symbol-cli "train" (namestring kit))))
        (is (zerop (getf r :code))
            (format nil "symbol train failed: ~A~%~A"
                    (getf r :out) (getf r :err)))
        (is (search "trained" (getf r :out) :test #'char-equal))))))
