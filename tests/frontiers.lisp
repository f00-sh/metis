;;;; frontiers.lisp — Metis 4.2 acceptance: symbols, GPU ops, trust, deep LM, packaging
(in-package :metis/tests)

(def-suite :metis-frontiers
  :description "Frontiers 1–5: category symbols, GPU ops, remote trust, deep LM, packaging")
(in-suite :metis-frontiers)

(test frontiers-category-symbols
  "Four category symbols list, enable, and expose real capabilities."
  (metis:boot :bootstrap t :reset t)
  (dolist (id '("chat-ui" "image-ingest" "domain-pack" "curriculum"))
    (is (member id (metis:symbol-list) :test #'string=))
    (let ((info (metis:enable-symbol! id)))
      (is (getf info :enabled))))
  ;; chat-ui
  (let ((s (metis:session-create :id "fr-chat" :boot nil)))
    (metis:iface-turn s "(tell (hello-frontier))")
    (let ((sum (metis:chat-ui-summary (metis::sess-id s))))
      (is (plusp (getf sum :turns)))
      (is (equal (metis::sess-id s) (getf sum :session))))
    (let ((tr (metis:chat-ui-transcript (metis::sess-id s))))
      (is (consp (getf tr :transcript)))))
  ;; image-ingest
  (let* ((s (metis:session-create :id "fr-img" :boot nil))
         (scratch #P"/tmp/grok-goal-f1afa225d28d/implementer/fixtures/")
         (img (merge-pathnames "dot.png" scratch)))
    (ensure-directories-exist scratch)
    (with-open-file (out img :direction :output
                         :element-type '(unsigned-byte 8)
                         :if-exists :supersede)
      (let ((png #(137 80 78 71 13 10 26 10 0 0 0 13 73 72 68 82
                   0 0 0 1 0 0 0 1 8 2 0 0 0 144 119 83 222
                   0 0 0 12 73 68 65 84 8 153 99 248 15 0 1 1 1 0 24 221 141 176
                   0 0 0 0 73 69 78 68 174 66 96 130)))
        (write-sequence png out)))
    (metis:session-attach-photo s (namestring img) :caption "frontier test photo")
    (let ((r (metis:image-ingest-session (metis::sess-id s))))
      (is (plusp (getf r :ingested)))
      (is (search "frontier" (getf r :corpus) :test #'char-equal))))
  ;; domain-pack
  (let* ((pack (merge-pathnames "symbols/domain-pack/pack.lisp"
                                (asdf:system-source-directory :metis)))
         (r (metis:domain-pack-load metis:*mind* pack)))
    (is (getf r :loaded))
    (is (plusp (getf r :facts)))
    (is (plusp (getf r :rules)))
    (is (metis:ask metis:*mind* (mread "(species dolphin mammal)"))))
  ;; curriculum
  (let* ((cur (merge-pathnames "symbols/curriculum/curriculum.txt"
                               (asdf:system-source-directory :metis)))
         (r (metis:curriculum-apply cur :name "fr-curriculum"
                                    :epochs 1 :hidden 32 :seq-len 128
                                    :depth 3 :max-batches 6)))
    (is (equal "fr-curriculum" (getf r :name)))
    (is (= 3 (or (getf r :depth)
                 (metis.nn:lm-depth
                  (getf (metis.nn:nn-registry-get "fr-curriculum") :model)))))
    (is (getf r :history))))

(test frontiers-gpu-ops-beyond-gemm
  "GPU axpy+relu agree with CPU within float tolerance when CUDA present."
  (metis:symbols-boot!)
  (let ((available (ignore-errors (metis.symbols:cuda-available-p))))
    (cond
      ((not available)
       (is (fboundp 'metis.symbols:nn-backend-axpy))
       (is (fboundp 'metis.symbols:nn-backend-relu))
       (is (fboundp 'metis.symbols:cuda-available-p)))
      (t
       (metis:enable-symbol! "cpu-nn" :force t)
       (let* ((x #(1d0 -2d0 3d0 -0.5d0))
              (y #(0.5d0 0.5d0 0.5d0 0.5d0))
              (be-cpu (metis.symbols:active-nn-backend))
              (ax-cpu (metis.symbols:nn-backend-axpy be-cpu x y 4 2d0))
              (re-cpu (metis.symbols:nn-backend-relu be-cpu x 4)))
         (metis:enable-symbol! "gpu-nn")
         (is (equal "gpu-nn" (getf (metis:nn-backend-status) :id)))
         (let* ((be-gpu (metis.symbols:active-nn-backend))
                (ax-gpu (metis.symbols:nn-backend-axpy be-gpu x y 4 2d0))
                (re-gpu (metis.symbols:nn-backend-relu be-gpu x 4)))
           (dotimes (i 4)
             (is (< (abs (- (aref ax-cpu i) (aref ax-gpu i))) 1d-3))
             (is (< (abs (- (aref re-cpu i) (aref re-gpu i))) 1d-3))))
         (metis:disable-symbol! "gpu-nn")
         (is (equal "cpu-nn" (getf (metis:nn-backend-status) :id))))))))

(defun %frontiers-write-signed-symbol (scratch id)
  "Write a minimal signed symbol package at SCRATCH with id ID."
  (ensure-directories-exist scratch)
  (with-open-file (out (merge-pathnames "manifest.lisp" scratch)
                       :direction :output :if-exists :supersede)
    (write-string
     (format nil
             "(in-package :cl-user)~%~
(metis.symbols:register-symbol!~%~
 :id ~S :name ~S :version \"0.1.0\"~%~
 :description \"Signed remote install fixture\"~%~
 :capabilities (quote (:tool :demo))~%~
 :priority 1~%~
 :hooks (metis.symbols:define-symbol-hooks~%~
          :activate (lambda (r) (declare (ignore r)) t)~%~
          :deactivate (lambda (r) (declare (ignore r)) t)))~%"
             id id)
     out))
  (let ((old-sig (merge-pathnames "symbol.sig" scratch)))
    (when (probe-file old-sig) (delete-file old-sig)))
  (metis:sign-symbol-package scratch)
  scratch)

(test frontiers-install-trust
  "Signed package installs via file://, git, and HTTP tarball; unsigned/bad refused."
  (metis.symbols:ensure-default-trust-key!)
  (let* ((base #P"/tmp/grok-goal-f1afa225d28d/implementer/")
         (scratch (merge-pathnames "remote-symbol/" base)))
    (ensure-directories-exist scratch)
    (%frontiers-write-signed-symbol scratch "remote-demo")
    (delete-file (merge-pathnames "symbol.sig" scratch))
    ;; unsigned refused
    (handler-case
        (progn
          (metis:install-symbol! scratch :id "remote-demo-unsigned"
                                 :require-signature t)
          (fail "unsigned should be refused"))
      (error (e)
        (let ((msg (princ-to-string e)))
          (is (or (search "unsigned" msg :test #'char-equal)
                  (search "symbol.sig" msg :test #'char-equal)
                  (search "missing" msg :test #'char-equal))))))
    ;; file:// signed install
    (metis:sign-symbol-package scratch)
    (is (probe-file (merge-pathnames "symbol.sig" scratch)))
    (let* ((url (format nil "file://~A" (namestring (truename scratch))))
           (info (metis:install-symbol! url :id "remote-demo" :enable t)))
      (is (equal "remote-demo" (getf info :id)))
      (is (getf info :enabled))
      (is (member "remote-demo" (metis:symbol-list) :test #'string=)))
    ;; git file-remote install
    (let* ((git-src (merge-pathnames "git-symbol-src/" base))
           (git-repo (merge-pathnames "git-symbol-repo/" base)))
      (when (uiop:directory-exists-p git-src)
        (uiop:delete-directory-tree git-src :validate t :if-does-not-exist :ignore))
      (when (uiop:directory-exists-p git-repo)
        (uiop:delete-directory-tree git-repo :validate t :if-does-not-exist :ignore))
      (%frontiers-write-signed-symbol git-src "git-demo")
      (uiop:run-program
       (list "bash" "-c"
             (format nil
                     "set -e; cd ~S; git init -q; git config user.email t@t; git config user.name t; git add -A; git -c commit.gpgsign=false commit -q --no-verify -m 'chore: init symbol fixture'; git clone -q --bare . ~S"
                     (namestring git-src) (namestring git-repo)))
       :output t :error-output t)
      (let* ((git-url (format nil "file://~A" (namestring (truename git-repo))))
             (info (metis:install-symbol! git-url :id "git-demo" :enable t)))
        (is (equal "git-demo" (getf info :id)))
        (is (getf info :enabled))
        (is (member "git-demo" (metis:symbol-list) :test #'string=))))
    ;; HTTP tarball install
    (let* ((http-src (merge-pathnames "http-symbol-src/" base))
           (tarball (merge-pathnames "pkg.tar.gz" base))
           (port 8765)
           (server nil))
      (when (uiop:directory-exists-p http-src)
        (uiop:delete-directory-tree http-src :validate t :if-does-not-exist :ignore))
      (%frontiers-write-signed-symbol http-src "http-demo")
      (uiop:run-program
       (list "bash" "-c"
             (format nil "cd ~S && tar -czf ~S ."
                     (namestring http-src) (namestring tarball)))
       :output t :error-output t)
      (setf server
            (uiop:launch-program
             (list "python3" "-m" "http.server" (write-to-string port)
                   "--bind" "127.0.0.1"
                   "--directory" (namestring base))
             :output :stream :error-output :stream))
      (sleep 0.5)
      (unwind-protect
           (let* ((http-url (format nil "http://127.0.0.1:~A/pkg.tar.gz" port))
                  (info (metis:install-symbol! http-url :id "http-demo" :enable t)))
             (is (equal "http-demo" (getf info :id)))
             (is (getf info :enabled))
             (is (member "http-demo" (metis:symbol-list) :test #'string=)))
        (ignore-errors (uiop:terminate-process server :urgent t))
        (ignore-errors (uiop:wait-process server))))
    ;; bad signature refused
    (metis:sign-symbol-package scratch)
    (with-open-file (out (merge-pathnames "symbol.sig" scratch)
                         :direction :output :if-exists :supersede)
      (format out "metis-sig-v1~%metis-dev~%deadbeef~%"))
    (handler-case
        (progn
          (metis:install-symbol!
           (format nil "file://~A" (namestring (truename scratch)))
           :id "remote-bad" :require-signature t)
          (fail "bad signature should be refused"))
      (error (e)
        (is (search "mismatch" (princ-to-string e) :test #'char-equal))))))

(test frontiers-deep-lm-gpu-train
  "Deeper/longer LM train via shipped entry; GPU backend used when available."
  (metis:boot :bootstrap t :reset t)
  (metis.symbols:nn-backend-reset-op-counts!)
  (let ((cuda (ignore-errors (metis.symbols:cuda-available-p))))
    (when cuda
      (metis:enable-symbol! "gpu-nn"))
    (let* ((corpus
            (format nil "~{~A ~}"
                    (loop repeat 60
                          collect "deeper longer context windows train the metis model")))
           (r (metis:nn-train-language-model
               corpus
               :name "deep-fr-lm"
               :epochs 1
               :hidden 48
               :seq-len 128
               :depth 3
               :max-batches 8
               :lr 3d-3))
           (model (getf (metis.nn:nn-registry-get "deep-fr-lm") :model))
           (gen (metis:nn-generate "deep-fr-lm" :prompt "deeper " :length 20
                                   :mind metis:*mind*)))
      (is (= 3 (getf r :depth)))
      (is (= 128 (getf r :seq-len)))
      (is (= 3 (metis.nn:lm-depth model)))
      (is (= 128 (metis.nn:lm-seq-len model)))
      (is (getf r :history))
      (is (stringp gen))
      (is (>= (length gen) 5))
      (when cuda
        (is (equal "gpu-nn" (getf (getf r :backend) :id)))
        (let ((ops (getf r :op-counts)))
          (is (plusp
               (loop for pair in ops
                     sum (if (listp pair) (second pair) 0)))))
        (metis:disable-symbol! "gpu-nn")))))

(test frontiers-packaging-docs
  "Docs triad + release memo exist; packaging script present."
  (let* ((root (asdf:system-source-directory :metis))
         (overview (merge-pathnames "docs/overview.md" root))
         (install (merge-pathnames "docs/install.md" root))
         (develop (merge-pathnames "docs/develop.md" root))
         (memo (merge-pathnames "docs/release-memo-4.2.md" root))
         (pkg (merge-pathnames "bin/package-metis" root))
         (build-lisp (merge-pathnames "packaging/build-image.lisp" root)))
    (is (probe-file overview))
    (is (probe-file install))
    (is (probe-file develop))
    (is (probe-file memo))
    (is (probe-file pkg))
    (is (probe-file build-lisp))
    (is (> (with-open-file (in overview) (file-length in)) 200))
    (is (> (with-open-file (in install) (file-length in)) 200))
    (is (> (with-open-file (in develop) (file-length in)) 200))
    (is (search "FRONTIERS" (uiop:read-file-string memo) :test #'char-equal))
    (is (search "metis.image" (uiop:read-file-string pkg)))))

(test frontiers-multi-mind-trust
  "Multi-mind trust: establish edge, trusted-send succeeds; untrusted fails."
  (metis:boot :bootstrap t :reset t)
  (let ((soc (metis:society-default-ensemble)))
    (is (>= (length (metis::society-minds soc)) 2))
    (let ((t1 (metis:society-trust! soc "conductor" "planner" :level 1.0)))
      (is (getf t1 :trusted))
      (is (metis:society-trust-p soc "conductor" "planner")))
    (let ((sent (metis:society-trusted-send soc "conductor" "planner"
                                            '(plan-request explore))))
      (is (getf sent :sent))
      (is (getf sent :trusted)))
    (handler-case
        (progn
          (metis:society-trusted-send soc "critic" "executor" '(nope))
          (fail "untrusted send should error"))
      (error (e)
        (is (search "trust" (princ-to-string e) :test #'char-equal))))))

(test frontiers-marketplace-and-curriculum
  "Marketplace catalog lists installable packages; curriculum train runs."
  (metis:boot :bootstrap t :reset t)
  (let ((cat (metis:symbol-marketplace-catalog)))
    (is (getf cat :marketplace))
    (is (plusp (getf cat :count)))
    (is (find "curriculum" (getf cat :packages)
              :key (lambda (p) (getf p :id)) :test #'string=))
    (is (find "domain-pack" (getf cat :packages)
              :key (lambda (p) (getf p :id)) :test #'string=))
    (is (eq (getf cat :install-via) 'metis:install-symbol!)))
  (let* ((cur (merge-pathnames "symbols/curriculum/curriculum.txt"
                               (asdf:system-source-directory :metis)))
         (r (metis:curriculum-apply cur :name "fr-cur-2"
                                    :epochs 1 :hidden 32 :seq-len 128
                                    :depth 3 :max-batches 4)))
    (is (equal "fr-cur-2" (getf r :name)))
    (is (getf r :history))
    (is (= 3 (or (getf r :depth)
                 (metis.nn:lm-depth
                  (getf (metis.nn:nn-registry-get "fr-cur-2") :model)))))))



(test frontiers-marketplace-iface-signed
  "Marketplace catalog + signed external sample install; unsigned refused."
  (metis:boot :bootstrap t :reset t)
  (metis.symbols:ensure-default-trust-key!)
  (let ((cat (metis:symbol-marketplace-catalog)))
    (is (getf cat :marketplace))
    (is (plusp (getf cat :count))))
  (let* ((root (asdf:system-source-directory :metis))
         (sample (merge-pathnames "samples/external-echo/" root))
         (manifest (merge-pathnames "manifest.lisp" sample))
         (sig (merge-pathnames "symbol.sig" sample)))
    (is (probe-file manifest))
    (is (> (with-open-file (in manifest) (file-length in)) 100)
        "external-echo manifest must be non-empty")
    (is (search "register-symbol!" (uiop:read-file-string manifest)
                :test #'char-equal))
    (is (probe-file sig))
    ;; re-sign so sig matches current manifest
    (metis:sign-symbol-package sample)
    ;; unsigned refuse via API
    (let ((tmp #P"/tmp/grok-goal-53da7102af27/implementer/unsigned-echo/"))
      (ensure-directories-exist tmp)
      (uiop:copy-file manifest (merge-pathnames "manifest.lisp" tmp))
      (when (probe-file (merge-pathnames "symbol.sig" tmp))
        (delete-file (merge-pathnames "symbol.sig" tmp)))
      (handler-case
          (progn
            (metis:symbol-marketplace-install (namestring tmp)
                                              :enable t
                                              :require-signature t)
            (fail "unsigned marketplace install should fail"))
        (error (e)
          (is (or (search "unsigned" (princ-to-string e) :test #'char-equal)
                  (search "sig" (princ-to-string e) :test #'char-equal)
                  (search "missing" (princ-to-string e) :test #'char-equal)
                  (search "mismatch" (princ-to-string e) :test #'char-equal)))))
      ;; unsigned refuse via real iface /marketplace install
      (let* ((s (metis:session-create :id "mkt-unsigned" :boot nil))
             (cmd (format nil "/marketplace install ~A" (namestring tmp)))
             (out (metis:iface-turn s cmd))
             (res (getf out :result))
             (msg (princ-to-string (or res out))))
        (is (or (and (consp res) (getf res :error))
                (search "unsigned" msg :test #'char-equal)
                (search "sig" msg :test #'char-equal)
                (search "missing" msg :test #'char-equal)
                (search "mismatch" msg :test #'char-equal)
                (search "error" msg :test #'char-equal))
            "iface marketplace install unsigned must surface error, got ~A" msg)))
    ;; signed external sample installs via API
    (let* ((src (namestring (uiop:ensure-directory-pathname (truename sample))))
           (info (metis:symbol-marketplace-install src
                                                   :enable t
                                                   :require-signature t))
           (si (metis:symbol-info "external-echo")))
      (is (equal "external-echo" (getf info :id)))
      (is (member "external-echo" (metis:symbol-list) :test #'string=))
      (is (equal "1.0.0" (getf si :version)))
      (is (plusp (length (getf si :capabilities))))
      (is (member :marketplace-sample (getf si :capabilities))))
    ;; signed install via iface /marketplace install
    (let* ((s (metis:session-create :id "mkt-signed" :boot nil))
           (src (namestring (uiop:ensure-directory-pathname (truename sample))))
           (out (metis:iface-turn s (format nil "/marketplace install ~A external-echo" src)))
           (res (getf out :result)))
      (is (getf out :explain))
      (is (or (equal "external-echo" (getf res :id))
              (member "external-echo" (metis:symbol-list) :test #'string=)))))
  ;; iface /marketplace list dispatch
  (let* ((s (metis:session-create :id "mkt-iface" :boot nil))
         (out (metis:iface-turn s "/marketplace list")))
    (is (getf out :explain))
    (is (getf out :metrics))
    (is (or (getf (getf out :result) :marketplace)
            (getf out :result)))))

(test frontiers-domain-kinship-pack
  (metis:boot :bootstrap t :reset t)
  (metis:nn-enable-path metis:*mind*)
  (let* ((pack (merge-pathnames "symbols/domain-kinship/pack.lisp"
                                (asdf:system-source-directory :metis)))
         (r (metis:domain-pack-load metis:*mind* pack)))
    (is (getf r :loaded))
    (is (plusp (getf r :couple-templates)))
    (let ((acc (metis:hybrid-coupled-propose metis:*mind* '(parent alice bob))))
      (is (getf acc :accepted)))
    (let ((rej (metis:hybrid-coupled-propose metis:*mind* '(not-kin 1))))
      (is (eq (getf rej :decision) :coupled-reject)))))
