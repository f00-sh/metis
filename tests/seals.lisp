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
