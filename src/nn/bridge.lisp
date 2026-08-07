;;;; bridge.lisp — Metis integration: continuous train, TMS-gated neural fire
(in-package :metis)

(defparameter *nn-model-dir* nil)

(defparameter *nn-path-fact* 'nn-path-enabled
  "TMS fact that must be IN for the neural fire path to run.")

(defun nn-model-dir ()
  (or *nn-model-dir*
      (merge-pathnames "models/"
                       (asdf:system-source-directory :metis))))

;;; ------------------------------------------------------------------
;;; TMS policy: when the neural path may fire
;;; ------------------------------------------------------------------

(defun nn-ensure-mind-tms (&optional (mind *mind*))
  (unless mind
    (return-from nn-ensure-mind-tms nil))
  (or (mind-tms mind)
      (setf (mind-tms mind) (make-empty-tms))))

(defun nn-enable-path (&optional (mind *mind*))
  "Assert TMS policy allowing neural fire (IN)."
  (let ((tms (nn-ensure-mind-tms mind)))
    (unless tms
      (error 'metis-error :message "nn-enable-path requires a mind with TMS"))
    (tms-assert tms *nn-path-fact* :informant :nn-policy)
    (assert-fact mind (list 'nn-policy *nn-path-fact* :in)
                 :support :nn-policy :forward nil)
    t))

(defun nn-disable-path (&optional (mind *mind*))
  "Retract TMS policy so neural fire is blocked (OUT)."
  (let ((tms (nn-ensure-mind-tms mind)))
    (unless tms
      (error 'metis-error :message "nn-disable-path requires a mind with TMS"))
    (tms-retract-assumption tms *nn-path-fact*)
    (assert-fact mind (list 'nn-policy *nn-path-fact* :out)
                 :support :nn-policy :forward nil)
    t))

(defun nn-path-allowed-p (&optional (mind *mind*))
  "Neural fire allowed when: no mind/TMS present (pure substrate), or
   TMS fact *nn-path-fact* is IN on the live mind."
  (cond
    ((null mind) t)
    ((null (mind-tms mind)) t)
    (t (tms-in-p (mind-tms mind) *nn-path-fact*))))

(defun nn-check-path! (&optional (mind *mind*))
  "Choke point: refuse neural fire when TMS policy is OUT.
   Signals metis-error — never silent sample."
  (unless (nn-path-allowed-p mind)
    (error 'metis-error
           :message
           (format nil
                   "neural path blocked: TMS ~S is OUT (enable with nn-enable-path)"
                   *nn-path-fact*)))
  t)

;;; ------------------------------------------------------------------
;;; Train (create) multi-layer LM
;;; ------------------------------------------------------------------

(defun nn-train-language-model (text &key (name "default-lm")
                                       (epochs 8)
                                       (hidden 256)
                                       (seq-len 128)
                                       (depth 3)
                                       (lr 1d-3)
                                       (max-batches nil)
                                       (emb-dim nil))
  "Train a multi-layer character language model on TEXT (pure Common Lisp).

   Product defaults: DEPTH 3, SEQ-LEN 128 (longer/deeper than 4.1 smoke defaults).
   When gpu-nn is the active symbol backend, train dispatches matmul/relu on GPU.
   Registers model under NAME, checkpoints, asserts readiness into mind KB/TMS."
  (when (and (find-package :metis.symbols)
             (fboundp 'metis.symbols:nn-backend-reset-op-counts!))
    (metis.symbols:nn-backend-reset-op-counts!))
  (let* ((vocab (metis.nn:build-char-vocab text))
         (model (metis.nn:language-model vocab
                                         :hidden hidden
                                         :seq-len seq-len
                                         :emb-dim emb-dim
                                         :depth depth))
         (backend (ignore-errors (nn-backend-status)))
         (history (metis.nn:train-lm! model text
                                      :epochs epochs :lr lr
                                      :seq-len seq-len
                                      :max-batches max-batches
                                      :log-every 50))
         (path (merge-pathnames (format nil "~A.ckpt" name)
                                (ensure-directories-exist (nn-model-dir))))
         (meta (list :path (namestring path)
                     :kind :char-lm
                     :vocab vocab
                     :hidden hidden
                     :seq-len seq-len
                     :depth depth
                     :epochs epochs
                     :backend backend
                     :op-counts (ignore-errors (metis.symbols:nn-backend-op-counts))
                     :continuous-steps 1
                     :history history)))
    (metis.nn:save-checkpoint model path
                              :meta (list :name name
                                          :vocab-size (metis.nn:vocab-size vocab)
                                          :kind :char-lm
                                          :hidden hidden
                                          :seq-len seq-len
                                          :depth depth
                                          :epochs epochs
                                          :backend backend))
    (metis.nn:nn-registry-register name model :meta meta)
    (when *mind*
      (assert-fact *mind*
                   (list 'nn-model name :char-lm
                         (metis.nn:vocab-size vocab)
                         (namestring path)
                         :depth depth :seq-len seq-len)
                   :support :nn :forward nil)
      (tms-assert (nn-ensure-mind-tms *mind*)
                  (list 'nn-model-ready name)
                  :informant :nn-train))
    (list :name name
          :history history
          :path (namestring path)
          :vocab-size (metis.nn:vocab-size vocab)
          :hidden hidden
          :seq-len seq-len
          :depth depth
          :epochs epochs
          :backend backend
          :op-counts (ignore-errors (metis.symbols:nn-backend-op-counts))
          :continued nil
          :continuous-steps 1)))

(defun nn-train-file (path &key (name nil) (epochs 8) (hidden 256) (seq-len 128)
                            (depth 3) (max-batches nil))
  "Train an in-process multi-layer language model on PATH."
  (let* ((path (namestring (truename path)))
         (text (uiop:read-file-string path))
         (name (or name (pathname-name path))))
    (nn-train-language-model text
                             :name name
                             :epochs epochs
                             :hidden hidden
                             :seq-len seq-len
                             :depth depth
                             :max-batches max-batches)))

;;; ------------------------------------------------------------------
;;; Continuous train — same registered model, successive corpora
;;; ------------------------------------------------------------------

(defun nn-continuous-train (text &key (name "default-lm")
                                   (epochs 4)
                                   (lr 1d-3)
                                   (max-batches nil)
                                   (hidden 256)
                                   (seq-len 128)
                                   (depth 3)
                                   (emb-dim nil))
  "Incrementally train NAME on TEXT without process restart.

   If NAME is already registered, continue training the same multi-layer
   model (weights updated in place; vocab fixed from first intake).
   Otherwise create via nn-train-language-model. Returns history + metadata."
  (let ((entry (metis.nn:nn-registry-get name)))
    (if (null entry)
        (nn-train-language-model text
                                 :name name
                                 :epochs epochs
                                 :hidden hidden
                                 :seq-len seq-len
                                 :depth depth
                                 :lr lr
                                 :max-batches max-batches
                                 :emb-dim emb-dim)
        (let* ((model (getf entry :model))
               (meta (copy-list (getf entry :meta)))
               (history (metis.nn:train-lm! model text
                                            :epochs epochs :lr lr
                                            :seq-len (metis.nn:lm-seq-len model)
                                            :max-batches max-batches
                                            :log-every 50))
               (steps (1+ (or (getf meta :continuous-steps) 1)))
               (path (or (getf meta :path)
                         (namestring
                          (merge-pathnames (format nil "~A.ckpt" name)
                                           (ensure-directories-exist
                                            (nn-model-dir))))))
               (prior-hist (getf meta :history))
               (all-hist (append (or prior-hist nil) history)))
          (metis.nn:save-checkpoint model path
                                    :meta (list :name name
                                                :kind :char-lm
                                                :depth (metis.nn:lm-depth model)
                                                :seq-len (metis.nn:lm-seq-len model)
                                                :hidden (metis.nn:lm-hidden model)
                                                :continuous-steps steps))
          (setf meta (list* :continuous-steps steps
                            :history all-hist
                            :path path
                            :last-history history
                            meta))
          (metis.nn:nn-registry-register name model :meta meta)
          (when *mind*
            (assert-fact *mind*
                         (list 'nn-continuous-train name steps)
                         :support :nn :forward nil)
            (tms-assert (nn-ensure-mind-tms *mind*)
                        (list 'nn-model-ready name)
                        :informant :nn-continuous))
          (list :name name
                :history history
                :all-history all-hist
                :path path
                :depth (metis.nn:lm-depth model)
                :seq-len (metis.nn:lm-seq-len model)
                :hidden (metis.nn:lm-hidden model)
                :continued t
                :continuous-steps steps)))))

;;; ------------------------------------------------------------------
;;; Attachment → corpus → continuous train
;;; ------------------------------------------------------------------

(defun session-corpus (sess)
  "Assemble training text from all session attachments that carry text
   (files + freeform context). Captions included when present."
  (with-output-to-string (out)
    (dolist (a (hash-table-values (sess-attachments sess)))
      (when (and (att-text a) (plusp (length (att-text a))))
        (write-string (att-text a) out)
        (terpri out))
      (when (and (att-caption a) (plusp (length (att-caption a))))
        (write-string (att-caption a) out)
        (terpri out)))))

(defun nn-train-from-session (sess &key (name "session-lm")
                                     (epochs 4)
                                     (hidden 256)
                                     (seq-len 64)
                                     (depth 2)
                                     (max-batches nil)
                                     (lr 1d-3))
  "Corpus pipeline: session attachments → continuous train on NAME.

   First call creates the multi-layer model; subsequent calls continue
   training the same registered model on the current attachment corpus."
  (let ((corpus (session-corpus sess)))
    (when (zerop (length (string-trim '(#\Space #\Newline #\Tab) corpus)))
      (error 'metis-error
             :message "session-corpus is empty — attach files or context first"))
    (nn-continuous-train corpus
                         :name name
                         :epochs epochs
                         :hidden hidden
                         :seq-len seq-len
                         :depth depth
                         :max-batches max-batches
                         :lr lr)))

;;; ------------------------------------------------------------------
;;; Generate (TMS-gated fire)
;;; ------------------------------------------------------------------

(defun nn-generate (name &key (prompt "") (length 200) (temperature 1.0)
                          (mind nil))
  "Sample from a registered in-process language model.

   Single choke point for neural fire: consults live mind TMS policy via
   nn-check-path!. When policy is OUT, signals metis-error (no silent sample)."
  (let ((*mind* (or mind *mind*)))
    (nn-check-path! *mind*)
    (let ((entry (metis.nn:nn-registry-get name)))
      (unless entry
        (error 'metis-error :message (format nil "unknown nn model ~A" name)))
      (metis.nn:lm-generate (getf entry :model)
                            :prompt prompt
                            :length length
                            :temperature temperature))))

(defun nn-train-mlp-xor (&key (epochs 600) (name "xor") (hidden 32) (lr 0.05d0))
  "Train an MLP on XOR end-to-end (autograd + Adam). Nonlinear benchmark."
  (let* ((model (metis.nn:mlp (list 2 hidden 1)))
         (xs (list (metis.nn:tensor-from-list '(0d0 0d0))
                   (metis.nn:tensor-from-list '(0d0 1d0))
                   (metis.nn:tensor-from-list '(1d0 0d0))
                   (metis.nn:tensor-from-list '(1d0 1d0))))
         (ys (list (metis.nn:tensor-from-list '(0d0))
                   (metis.nn:tensor-from-list '(1d0))
                   (metis.nn:tensor-from-list '(1d0))
                   (metis.nn:tensor-from-list '(0d0))))
         (hist (metis.nn:train! model xs ys :epochs epochs :lr lr))
         (preds (mapcar (lambda (x)
                          (aref (metis.nn:tensor-data
                                 (metis.nn:module-forward model x))
                                0))
                        xs)))
    (metis.nn:nn-registry-register name model
                                   :meta (list :kind :mlp-xor :hidden hidden))
    (list :name name
          :history (last hist 5)
          :predictions preds
          :final-loss (second (first (last hist))))))

;;; ------------------------------------------------------------------
;;; Tools + iface
;;; ------------------------------------------------------------------

(defun install-nn-tools (mind)
  "Install neural train/infer tools on MIND and enable TMS neural path by default."
  (nn-enable-path mind)
  (register-tool
   mind 'nn-train-text
   (lambda (text &optional name)
     (nn-continuous-train text
                          :name (or name "session-lm")
                          :epochs 4
                          :hidden 256
                          :seq-len 64
                          :depth 2))
   :doc "Continuous-train multi-layer char LM on a string (pure CL)"
   :schema '(text &optional name)
   :safe t)
  (register-tool
   mind 'nn-train-file
   (lambda (path &optional name)
     (nn-train-file path :name name :epochs 4 :hidden 256 :seq-len 64 :depth 2))
   :doc "Train multi-layer char LM from a file path"
   :schema '(path &optional name)
   :safe t)
  (register-tool
   mind 'nn-train-session
   (lambda (&optional name)
     (let ((s (session-ensure)))
       (nn-train-from-session s :name (or name "session-lm")
                              :epochs 4 :hidden 256 :seq-len 64 :depth 2)))
   :doc "Train/continuous-train from current session attachments corpus"
   :schema '(&optional name)
   :safe t)
  (register-tool
   mind 'nn-generate
   (lambda (name &optional prompt length)
     (nn-generate name
                  :prompt (or prompt "")
                  :length (or length 200)
                  :mind mind))
   :doc "Generate text from a registered LM (TMS-gated)"
   :schema '(name &optional prompt length)
   :safe t)
  (register-tool
   mind 'nn-list
   (lambda () (metis.nn:nn-registry-list))
   :doc "List registered neural models"
   :safe t)
  (register-tool
   mind 'nn-enable
   (lambda () (nn-enable-path mind))
   :doc "TMS-assert neural path enabled (allow generate)"
   :safe t)
  (register-tool
   mind 'nn-disable
   (lambda () (nn-disable-path mind))
   :doc "TMS-retract neural path (block generate)"
   :safe t)
  (register-tool
   mind 'nn-train-xor
   (lambda () (nn-train-mlp-xor))
   :doc "Train MLP on XOR — pure-CL autograd + optimizer verification"
   :safe t)
  t)

(defun %iface-nn-commands (sess text)
  (cond
    ((cl-ppcre:scan "(?i)^/train\\s+file\\s+(\\S+)(?:\\s+(\\S+))?$" text)
     (cl-ppcre:register-groups-bind (path name)
         ("(?i)^/train\\s+file\\s+(\\S+)(?:\\s+(\\S+))?$" text)
       (list :train-file path name)))
    ((cl-ppcre:scan "(?i)^/train\\s+text\\s+(.+)$" text)
     (cl-ppcre:register-groups-bind (body)
         ("(?i)^/train\\s+text\\s+(.+)$" text)
       (list :train-text body)))
    ((cl-ppcre:scan "(?i)^/train\\s+attachments(?:\\s+(\\S+))?\\s*$" text)
     (cl-ppcre:register-groups-bind (name)
         ("(?i)^/train\\s+attachments(?:\\s+(\\S+))?\\s*$" text)
       (list :train-attachments (or name "session-lm"))))
    ((cl-ppcre:scan "(?i)^/generate\\s+(\\S+)(?:\\s+(.*))?$" text)
     (cl-ppcre:register-groups-bind (name prompt)
         ("(?i)^/generate\\s+(\\S+)(?:\\s+(.*))?$" text)
       (list :generate name (or prompt ""))))
    ((cl-ppcre:scan "(?i)^/nn\\s+list\\s*$" text)
     (list :nn-list))
    ((cl-ppcre:scan "(?i)^/nn\\s+enable\\s*$" text)
     (list :nn-enable))
    ((cl-ppcre:scan "(?i)^/nn\\s+disable\\s*$" text)
     (list :nn-disable))
    (t nil)))
