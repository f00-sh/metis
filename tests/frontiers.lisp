;;;; frontiers.lisp — Metis 4.2 acceptance: symbols, GPU ops, trust, deep LM, packaging
(in-package :metis/tests)

(def-suite :metis-frontiers
  :description "Frontiers 1–5: category symbols, GPU ops, remote trust, deep LM, packaging")
(in-suite :metis-frontiers)

(test frontiers-category-symbols
  "Four category symbols list, enable, and expose real capabilities."
  (metis:boot :bootstrap t :reset t)
  (dolist (id '("chat-ui" "image-ingest" "domain-pack" "curriculum"))
    (is (member id (metis:symbol-list) :test #'string=)
        "symbol ~A must be discoverable" id)
    (let ((info (metis:enable-symbol! id)))
      (is (getf info :enabled) "enable ~A" id)))
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
         (_ (ensure-directories-exist scratch))
         (img (merge-pathnames "dot.png" scratch)))
    (declare (ignore _))
    ;; minimal PNG (1x1) via printf/base64 or write bytes
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
    (if (not available)
        (is t) ;; environment without CUDA: still pass; code path exists
        (progn
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

(test frontiers-install-trust
  "Signed package installs; unsigned remote refused."
  (metis.symbols:ensure-default-trust-key!)
  (let* ((scratch #P"/tmp/grok-goal-f1afa225d28d/implementer/remote-symbol/")
         (_ (ensure-directories-exist scratch))
         (manifest (merge-pathnames "manifest.lisp" scratch)))
    (declare (ignore _))
    (with-open-file (out manifest :direction :output :if-exists :supersede)
      (write-string
       "(in-package :cl-user)
(metis.symbols:register-symbol!
 :id \"remote-demo\"
 :name \"Remote Demo\"
 :version \"0.1.0\"
 :description \"Signed remote install fixture\"
 :capabilities (quote (:tool :demo))
 :priority 1
 :hooks (metis.symbols:define-symbol-hooks
          :activate (lambda (r) (setf (getf (metis.symbols:sr-meta r) :activated) t) t)
          :deactivate (lambda (r) (declare (ignore r)) t)))
"
       out))
    (let ((old-sig (merge-pathnames "symbol.sig" scratch)))
      (when (probe-file old-sig) (delete-file old-sig)))
    ;; unsigned local with require-signature → refuse
    (handler-case
        (progn
          (metis:install-symbol! scratch :id "remote-demo-unsigned"
                                 :require-signature t)
          (fail "unsigned should be refused"))
      (error (e)
        (is (or (search "unsigned" (princ-to-string e) :test #'char-equal)
                (search "symbol.sig" (princ-to-string e) :test #'char-equal)
                (search "missing" (princ-to-string e) :test #'char-equal)))))
    ;; sign and install via file://
    (metis:sign-symbol-package scratch)
    (is (probe-file (merge-pathnames "symbol.sig" scratch)))
    (let* ((url (format nil "file://~A" (namestring (truename scratch))))
           (info (metis:install-symbol! url :id "remote-demo" :enable t)))
      (is (equal "remote-demo" (getf info :id)))
      (is (getf info :enabled))
      (is (member "remote-demo" (metis:symbol-list) :test #'string=)))
    ;; bad signature refused
    (with-open-file (out (merge-pathnames "symbol.sig" scratch)
                         :direction :output :if-exists :supersede)
      (format out "metis-sig-v1~%metis-dev~%deadbeef~%"))
    (handler-case
        (progn
          (metis:install-symbol! (format nil "file://~A"
                                         (namestring (truename scratch)))
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
          (is (or (assoc :matmul ops)
                  (assoc :relu ops)
                  (find :matmul ops :key #'car)
                  (find :relu ops :key #'car)
                  (plusp (reduce #'+ (mapcar #'second ops) :initial-value 0))))
          (is (plusp
               (loop for pair in ops sum (if (listp pair) (second pair) 0))))))
      (when cuda
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
