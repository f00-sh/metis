;;;; durable.lisp — LMDB-backed durable mind-state store
(in-package :metis)

(defvar *durable-env* nil)
(defvar *durable-db* nil)
(defvar *durable-path* nil)

(defun durable-default-path ()
  (or (get-config :durable-path)
      (merge-pathnames "metis-lmdb/"
                       (uiop:ensure-directory-pathname
                        (or (get-config :world-dir)
                            (merge-pathnames "worlds/"
                                             (asdf:system-source-directory :metis)))))))

(defun durable-open (&optional path)
  "Open LMDB environment for durable storage."
  (let ((path (uiop:ensure-directory-pathname
               (or path (durable-default-path)))))
    (ensure-directories-exist path)
    (when *durable-env*
      (durable-close))
    (setf *durable-path* path)
    (setf *durable-env*
          (lmdb:open-env (namestring path)
                         :map-size (* 256 1024 1024)
                         :max-dbs 8
                         :if-does-not-exist :create))
    ;; get-db must not run inside an already-open client txn
    (let ((lmdb:*env* *durable-env*))
      (setf *durable-db*
            (lmdb:get-db "metis"
                         :env *durable-env*
                         :if-does-not-exist :create
                         :value-encoding :octets)))
    (metis-log :info "durable LMDB open ~A" path)
    (list :path (namestring path) :open t)))

(defun durable-close ()
  (when *durable-env*
    (ignore-errors (lmdb:close-env *durable-env*)))
  (setf *durable-env* nil
        *durable-db* nil
        *durable-path* nil)
  t)

(defun %durable-encode (obj)
  (lmdb:string-to-octets
   (with-standard-io-syntax
     (let ((*package* (find-package :metis))
           (*print-readably* t)
           (*print-circle* t))
       (prin1-to-string obj)))))

(defun %durable-decode (raw)
  (let* ((str (cond ((stringp raw) raw)
                    ((vectorp raw) (lmdb:octets-to-string raw))
                    (t (princ-to-string raw))))
         (*package* (find-package :metis)))
    (read-from-string str)))

(defun %durable-ensure-open ()
  (unless (and *durable-env* *durable-db*)
    (durable-open)))

(defun durable-put (key value)
  "Persist KEY -> VALUE (any readable Lisp object) in LMDB."
  (%durable-ensure-open)
  (let ((lmdb:*env* *durable-env*))
    (lmdb:with-txn (:write t)
      (lmdb:put *durable-db* (string key) (%durable-encode value))))
  t)

(defun durable-get (key &optional default)
  "Fetch VALUE for KEY from LMDB, or DEFAULT."
  (%durable-ensure-open)
  (let ((lmdb:*env* *durable-env*))
    (lmdb:with-txn ()
      (let ((raw (lmdb:g3t *durable-db* (string key))))
        (if raw
            (%durable-decode raw)
            default)))))

(defun durable-del (key)
  (%durable-ensure-open)
  (let ((lmdb:*env* *durable-env*))
    (lmdb:with-txn (:write t)
      (ignore-errors (lmdb:del *durable-db* (string key)))))
  t)

(defun durable-save-mind (mind &optional (key "mind-default"))
  "Serialize mind KB/rules/goals/beliefs + hybrid hippocampus/self-model."
  (let* ((m (ensure-mind mind))
         (payload
          (list :metis-durable 2
                :saved (now-iso)
                :version *metis-version*
                :kb (kb-snapshot (mind-kb m))
                :goals (mind-goals m)
                :beliefs (and (mind-beliefs m)
                              (belief-snapshot (mind-beliefs m)))
                :tms (and (mind-tms m) (tms-snapshot (mind-tms m)))
                :cycle (mind-cycle m)
                :hippocampus (when (boundp '*hippocampus*)
                               (copy-tree *hippocampus*))
                :hybrid-metrics (when (fboundp 'hybrid-metrics)
                                  (ignore-errors (hybrid-metrics)))
                :self-model
                (list :hybrid-mode
                      (ignore-errors
                        (and (mind-tms m)
                             (find-if (lambda (f)
                                        (and (consp f)
                                             (eq (first f) 'hybrid-mode)))
                                      (tms-in-facts (mind-tms m)))))
                      :learn-rate
                      (ignore-errors
                        (and (mind-tms m)
                             (find-if (lambda (f)
                                        (and (consp f)
                                             (eq (first f) 'learn-rate)))
                                      (tms-in-facts (mind-tms m)))))
                      :consolidation-lr
                      (and (boundp '*consolidation-lr*) *consolidation-lr*)
                      :consolidation-max-batches
                      (and (boundp '*consolidation-max-batches*)
                           *consolidation-max-batches*)))))
    (durable-put key payload)
    (metis-log :info "durable-save-mind ~A" key)
    key))

(defun durable-load-mind (mind &optional (key "mind-default"))
  "Restore mind + hippocampus + hybrid self-model from durable store."
  (let* ((m (ensure-mind mind))
         (payload (durable-get key)))
    (unless payload
      (return-from durable-load-mind nil))
    (unless (eq (first payload) :metis-durable)
      (error 'metis-error :message "invalid durable mind payload"))
    (kb-restore (mind-kb m) (getf payload :kb))
    (setf (mind-goals m) (getf payload :goals)
          (mind-cycle m) (or (getf payload :cycle) 0))
    (when (and (mind-beliefs m) (getf payload :beliefs))
      (dolist (pair (getf payload :beliefs))
        (belief-set (mind-beliefs m) (first pair) (second pair))))
    (when (and (mind-tms m) (getf payload :tms))
      (dolist (n (getf (getf payload :tms) :nodes))
        (when (eq (getf n :label) :in)
          (tms-assert (mind-tms m) (getf n :fact)
                      :informant :durable
                      :belief (or (getf n :belief) 1.0)))))
    ;; Hybrid continuum restore
    (when (getf payload :hippocampus)
      (setf *hippocampus* (copy-tree (getf payload :hippocampus))))
    (when (and (getf payload :hybrid-metrics)
               (boundp '*hybrid-metrics*))
      (setf *hybrid-metrics* (copy-list (getf payload :hybrid-metrics))))
    (let ((sm (getf payload :self-model)))
      (when sm
        (when (getf sm :consolidation-lr)
          (setf *consolidation-lr* (getf sm :consolidation-lr)))
        (when (getf sm :consolidation-max-batches)
          (setf *consolidation-max-batches*
                (getf sm :consolidation-max-batches)))
        (when (and (mind-tms m) (getf sm :hybrid-mode))
          (tms-assert (mind-tms m) (getf sm :hybrid-mode)
                      :informant :durable))
        (when (and (mind-tms m) (getf sm :learn-rate))
          (tms-assert (mind-tms m) (getf sm :learn-rate)
                      :informant :durable))))
    (metis-log :info "durable-load-mind ~A" key)
    t))

(defun durable-save-hybrid! (&key (mind *mind*) (key "hybrid-default"))
  "Shipped hybrid durable save (hippo + self-model + mind)."
  (durable-save-mind mind key))

(defun durable-load-hybrid! (&key (mind *mind*) (key "hybrid-default"))
  "Shipped hybrid durable load. Returns T if restored."
  (durable-load-mind mind key))

(defun durable-roundtrip-ok-p (mind &optional (key "roundtrip-test"))
  "Write current mind, wipe marker fact, restore; prove durable path works."
  (let* ((m (ensure-mind mind))
         (marker (list 'durable-marker (get-universal-time) (random 1000000))))
    (assert-fact m marker :support :durable-test)
    (durable-save-mind m key)
    (retract-fact m marker)
    (unless (null (kb-holds-p (mind-kb m) marker))
      (return-from durable-roundtrip-ok-p nil))
    (durable-load-mind m key)
    (and (kb-holds-p (mind-kb m) marker) t)))
