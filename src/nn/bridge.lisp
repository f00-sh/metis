;;;; bridge.lisp — Metis integration: train/infer tools, iface hooks
(in-package :metis)

(defparameter *nn-model-dir*
  nil)

(defun nn-model-dir ()
  (or *nn-model-dir*
      (merge-pathnames "models/"
                       (asdf:system-source-directory :metis))))

(defun nn-train-language-model (text &key (name "default-lm")
                                       (epochs 8)
                                       (hidden 256)
                                       (seq-len 64)
                                       (lr 1d-3)
                                       (max-batches nil)
                                       (emb-dim nil))
  "Train a character language model on TEXT entirely in-process (pure Common Lisp).
   No Python, no external ML runtime. Registers model under NAME, writes a
   checkpoint under (nn-model-dir), asserts readiness into the mind KB/TMS.
   Returns training history and artifact metadata."
  (let* ((vocab (metis.nn:build-char-vocab text))
         (model (metis.nn:language-model vocab
                                         :hidden hidden
                                         :seq-len seq-len
                                         :emb-dim emb-dim))
         (history (metis.nn:train-lm! model text
                                      :epochs epochs :lr lr
                                      :seq-len seq-len
                                      :max-batches max-batches
                                      :log-every 50))
         (path (merge-pathnames (format nil "~A.ckpt" name)
                                (ensure-directories-exist (nn-model-dir)))))
    (metis.nn:save-checkpoint model path
                              :meta (list :name name
                                          :vocab-size (metis.nn:vocab-size vocab)
                                          :kind :char-lm
                                          :hidden hidden
                                          :seq-len seq-len
                                          :epochs epochs))
    (metis.nn:nn-registry-register name model
                                   :meta (list :path (namestring path)
                                               :kind :char-lm
                                               :vocab vocab
                                               :hidden hidden
                                               :seq-len seq-len))
    (when *mind*
      (assert-fact *mind*
                   (list 'nn-model name :char-lm
                         (metis.nn:vocab-size vocab)
                         (namestring path))
                   :support :nn :forward nil)
      (tms-assert (or (mind-tms *mind*)
                      (setf (mind-tms *mind*) (make-empty-tms)))
                  (list 'nn-model-ready name)
                  :informant :nn-train))
    (list :name name
          :history history
          :path (namestring path)
          :vocab-size (metis.nn:vocab-size vocab)
          :hidden hidden
          :seq-len seq-len
          :epochs epochs)))

(defun nn-train-file (path &key (name nil) (epochs 8) (hidden 256) (seq-len 64)
                            (max-batches nil))
  "Train an in-process language model on the full contents of PATH."
  (let* ((path (namestring (truename path)))
         (text (uiop:read-file-string path))
         (name (or name (pathname-name path))))
    (nn-train-language-model text
                             :name name
                             :epochs epochs
                             :hidden hidden
                             :seq-len seq-len
                             :max-batches max-batches)))

(defun nn-generate (name &key (prompt "") (length 200) (temperature 1.0))
  "Sample from a registered in-process language model."
  (let ((entry (metis.nn:nn-registry-get name)))
    (unless entry
      (error 'metis-error :message (format nil "unknown nn model ~A" name)))
    (metis.nn:lm-generate (getf entry :model)
                          :prompt prompt
                          :length length
                          :temperature temperature)))

(defun nn-train-mlp-xor (&key (epochs 600) (name "xor") (hidden 32) (lr 0.05d0))
  "Train an MLP on XOR end-to-end (autograd + Adam). Nonlinear benchmark of
   the pure-CL substrate — not a product endpoint, a correctness proof."
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

(defun install-nn-tools (mind)
  "Install neural train/infer tools on MIND (called at boot)."
  (register-tool
   mind 'nn-train-text
   (lambda (text &optional name)
     (nn-train-language-model text
                              :name (or name "session-lm")
                              :epochs 4
                              :hidden 256
                              :seq-len 64))
   :doc "Train in-process character language model on a string (pure CL)"
   :schema '(text &optional name)
   :safe t)
  (register-tool
   mind 'nn-train-file
   (lambda (path &optional name)
     (nn-train-file path :name name :epochs 4 :hidden 256 :seq-len 64))
   :doc "Train in-process character language model from a file path"
   :schema '(path &optional name)
   :safe t)
  (register-tool
   mind 'nn-generate
   (lambda (name &optional prompt length)
     (nn-generate name
                  :prompt (or prompt "")
                  :length (or length 200)))
   :doc "Generate text from a registered in-process language model"
   :schema '(name &optional prompt length)
   :safe t)
  (register-tool
   mind 'nn-list
   (lambda () (metis.nn:nn-registry-list))
   :doc "List registered neural models"
   :safe t)
  (register-tool
   mind 'nn-train-xor
   (lambda () (nn-train-mlp-xor))
   :doc "Train MLP on XOR — pure-CL autograd + optimizer verification"
   :safe t)
  t)

;; Extend iface parse for train/generate
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
    ((cl-ppcre:scan "(?i)^/generate\\s+(\\S+)(?:\\s+(.*))?$" text)
     (cl-ppcre:register-groups-bind (name prompt)
         ("(?i)^/generate\\s+(\\S+)(?:\\s+(.*))?$" text)
       (list :generate name (or prompt ""))))
    ((cl-ppcre:scan "(?i)^/nn\\s+list\\s*$" text)
     (list :nn-list))
    (t nil)))
