;;;; symbols.lisp — plugin system + NN backend (cpu/gpu) tests
(in-package :metis/tests)

(def-suite :metis-symbols
  :description "Metis symbols (plugins) registry, cpu-nn, gpu-nn backend")
(in-suite :metis-symbols)

(test symbols-boot-registers-cpu
  (metis:boot :bootstrap t :reset t)
  (is (member "cpu-nn" (metis:symbol-list) :test #'string=))
  (let ((info (metis:symbol-info "cpu-nn")))
    (is (getf info :enabled))
    (is (member :nn-backend (getf info :capabilities))))
  (let ((be (metis:nn-backend-status)))
    (is (equal "cpu-nn" (getf be :id)))
    (is (getf be :ready))))

(test symbols-tools-on-boot
  (metis:boot :bootstrap t :reset t)
  (let ((tools (metis:list-tools metis:*mind*)))
    (is (find 'metis::symbols-list tools :key (lambda (x) (getf x :name))))
    (is (find 'metis::symbol-enable tools :key (lambda (x) (getf x :name))))
    (is (find 'metis::nn-backend tools :key (lambda (x) (getf x :name))))))

(test symbols-cpu-matmul-path
  "Active cpu-nn backend produces correct matmul via shipped t-matmul."
  (metis:symbols-boot!)
  (metis:enable-symbol! "cpu-nn" :force t)
  (let* ((a (metis.nn:tensor-from-list '((1d0 2d0) (3d0 4d0))))
         (b (metis.nn:tensor-from-list '((5d0 6d0) (7d0 8d0))))
         (c (metis.nn:t-matmul a b))
         (d (metis.nn:tensor-data c)))
    ;; [[19,22],[43,50]]
    (is (< (abs (- (aref d 0) 19d0)) 1d-9))
    (is (< (abs (- (aref d 1) 22d0)) 1d-9))
    (is (< (abs (- (aref d 2) 43d0)) 1d-9))
    (is (< (abs (- (aref d 3) 50d0)) 1d-9))))

(test symbols-gpu-enable-when-available
  "gpu-nn enable uses real CUDA path when device present; else clean error."
  (metis:symbols-boot!)
  (let ((available (ignore-errors (metis.symbols:cuda-available-p))))
    (if available
        (let ((info (metis:enable-symbol! "gpu-nn")))
          (is (getf info :enabled))
          (is (equal "gpu-nn" (getf (metis:nn-backend-status) :id)))
          (let* ((a (metis.nn:tensor-from-list '((1d0 2d0) (3d0 4d0))))
                 (b (metis.nn:tensor-from-list '((5d0 6d0) (7d0 8d0))))
                 (c (metis.nn:t-matmul a b))
                 (d (metis.nn:tensor-data c)))
            ;; float path — allow small tolerance
            (is (< (abs (- (aref d 0) 19d0)) 1d-2))
            (is (< (abs (- (aref d 3) 50d0)) 1d-2)))
          (metis:disable-symbol! "gpu-nn")
          (is (equal "cpu-nn" (getf (metis:nn-backend-status) :id))))
        (handler-case
            (progn
              (metis:enable-symbol! "gpu-nn")
              (fail "gpu-nn should error when CUDA unavailable"))
          (error (e)
            (is (search "CUDA" (princ-to-string e) :test #'char-equal)))))))

(test symbols-install-from-directory
  "Install a third-party style symbol from a directory with manifest.lisp."
  (let* ((scratch #P"/tmp/grok-goal-plugins-symbols/implementer/sample-symbol/")
         (_ (ensure-directories-exist scratch))
         (manifest (merge-pathnames "manifest.lisp" scratch)))
    (declare (ignore _))
    (with-open-file (out manifest :direction :output :if-exists :supersede)
      (write-string
       "(in-package :cl-user)
(metis.symbols:register-symbol!
 :id \"sample-echo\"
 :name \"Sample Echo\"
 :version \"0.1.0\"
 :description \"Test third-party symbol\"
 :capabilities '(:tool :demo)
 :priority 1
 :hooks (metis.symbols:define-symbol-hooks
          :activate (lambda (r) (setf (getf (metis.symbols:sr-meta r) :activated) t) t)
          :deactivate (lambda (r) (declare (ignore r)) t))
 :meta (list :kind :sample))
"
       out))
    (let ((info (metis:install-symbol! scratch :id "sample-echo" :enable t)))
      (is (equal "sample-echo" (getf info :id)))
      (is (getf info :enabled))
      (is (member "sample-echo" (metis:symbol-list) :test #'string=)))))
