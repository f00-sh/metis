;;;; chat-spine.lisp — house base LM freeform mouth + symbol model packages
;;;; Symbols condition generation (adapters / prompt experts / process tags),
;;;; not RAG-first residual chat. External LLM is never the freeform mind.
(in-package :metis)

(defparameter *house-chat-model* "house-chat"
  "Registry name of the in-process house base language model.")

(defparameter *house-chat-ready* nil
  "T when house-chat model is registered this process.")

(defparameter *symbol-model-conditioners*
  (make-hash-table :test #'equal)
  "pack-id → conditioner plist (:id :kind :prompt-prefix :model-name :active t).")

(defparameter *product-freeform-external-llm* nil
  "Hard product law: freeform must NEVER use external API completion.
   Escape-hatch llm.lisp may exist; product freeform ignores it.")

;;; ---- conditioner registry (symbol = model package, not RAG bag) ---

(defun symbol-model-active (&optional id)
  "List active conditioners, or T if ID is active."
  (if id
      (let ((c (gethash (string id) *symbol-model-conditioners*)))
        (and c (getf c :active) c))
      (let ((out nil))
        (maphash (lambda (k v)
                   (declare (ignore k))
                   (when (getf v :active) (push v out)))
                 *symbol-model-conditioners*)
        (nreverse out))))

(defun symbol-model-attach! (id &key (prompt-prefix nil)
                                  (model-name nil)
                                  (kind :adapter)
                                  (meta nil))
  "Attach a model-package conditioner for symbol ID (weights expert / adapter tag).
   Conditioning modulates house generation; unload via symbol-model-detach!."
  (let* ((id (string id))
         (rec (list :id id
                    :kind (or kind :adapter)
                    :prompt-prefix (or prompt-prefix
                                       (format nil "[symbol-adapter ~A active]" id))
                    :model-name model-name
                    :active t
                    :meta meta
                    :attached-at (get-universal-time))))
    (setf (gethash id *symbol-model-conditioners*) rec)
    (when *mind*
      (ignore-errors
        (assert-fact *mind*
                     (list 'symbol-model-active id (getf rec :kind))
                     :support :chat-spine :forward nil)))
    rec))

(defun symbol-model-detach! (id)
  "Remove model-package conditioning for ID."
  (let* ((id (string id))
         (was (gethash id *symbol-model-conditioners*)))
    (remhash id *symbol-model-conditioners*)
    (when (and *mind* was)
      (ignore-errors
        (retract-fact *mind* (list 'symbol-model-active id (getf was :kind)))))
    (list :detached id :was (and was t))))

(defun symbol-model-clear! ()
  (clrhash *symbol-model-conditioners*)
  t)

(defun symbol-model-on-enable! (id man &key (dir nil))
  "Hook from pack enable: if pack ships model.ckpt or :model-package, attach conditioner."
  (let* ((id (string id))
         (dir (or dir
                  (ignore-errors
                    (merge-pathnames (format nil "~A/" id)
                                     (symbol-pack-registry-dir)))))
         (ckpt (and dir (merge-pathnames "model.ckpt" dir)))
         (model-pkg (or (getf man :model-package)
                        (eq (getf man :weights-policy) :included)
                        (and ckpt (probe-file ckpt))))
         (caps (or (getf man :capabilities) (getf man :caps)))
         (prefix (format nil "[~A sieve:~{~A~^,~}]"
                         id
                         (mapcar (lambda (c) (string-downcase (string c)))
                                 (or caps '(:domain))))))
    (when model-pkg
      (let ((mname nil))
        (when (and ckpt (probe-file ckpt))
          (setf mname (format nil "symbol-~A" id)))
        (symbol-model-attach! id
                              :prompt-prefix prefix
                              :model-name mname
                              :kind (if (and ckpt (probe-file ckpt))
                                        :weights
                                        :adapter)
                              :meta (list :manifest-id id
                                          :ckpt (and ckpt (probe-file ckpt)
                                                     (namestring ckpt))
                                          :weights-bound (and mname t)))))
    (symbol-model-active id)))

(defun symbol-model-on-disable! (id)
  (symbol-model-detach! id))

;;; ---- house base model --------------------------------------------

(defun house-chat-model-name ()
  *house-chat-model*)

(defun house-chat-available-p ()
  (and (metis.nn:nn-registry-get *house-chat-model*) t))

(defun house-chat-ensure! (&key (force nil)
                             (corpus nil)
                             (epochs 2)
                             (hidden 48)
                             (seq-len 32)
                             (depth 2)
                             (max-batches 40))
  "Ensure house-chat model is registered. Prefer existing registry entry;
   else train a tiny pure-CL LM on CORPUS (or a default English seed).
   Path correctness over fluency — small house model is intentional."
  (when (and (not force) (house-chat-available-p))
    (setf *house-chat-ready* t)
    (return-from house-chat-ensure!
      (list :ready t :name *house-chat-model* :existed t)))
  (let* ((seed (or corpus
                   (format nil "~{~A ~}"
                           '("Metis is a Common Lisp cognitive architecture."
                             "Hello I am Metis. I use house models not external APIs."
                             "Symbols condition generation like adapters."
                             "Math process and reason act are tool sieves."
                             "Natural language is the chat spine."
                             "Ask anything about symbols packs and pure CL neural nets."
                             "The house chat model answers residual freeform questions."
                             "We train and generate in process only."))))
         (r (nn-train-language-model seed
                                     :name *house-chat-model*
                                     :epochs epochs
                                     :hidden hidden
                                     :seq-len seq-len
                                     :depth depth
                                     :max-batches max-batches
                                     :lr 5d-3)))
    (setf *house-chat-ready* t)
    (list :ready t :name *house-chat-model* :trained t :result r)))

(defun %house-condition-prefix ()
  "Concat active symbol adapter prefixes (sieves on the chat spine)."
  (let ((parts nil))
    (dolist (c (symbol-model-active))
      (let ((p (getf c :prompt-prefix)))
        (when (and p (plusp (length (string p))))
          (push (string p) parts))))
    (when parts
      (format nil "~{~A~%~}" (nreverse parts)))))

(defun house-chat-generate (question &key (mind nil)
                                       (length 80)
                                       (ensure t)
                                       (context nil))
  "Generate residual freeform reply from the **in-process house base LM**,
   conditioned by active symbol model packages. Never calls external LLM."
  (let* ((m (or mind *mind*))
         (*mind* m)
         (q (string-trim '(#\Space #\Tab #\Newline) (or question ""))))
    (when ensure
      (house-chat-ensure!))
    (unless (house-chat-available-p)
      (return-from house-chat-generate
        (list :freeform :house-chat
              :source :house-chat
              :ok nil
              :reply-text
              "House chat model is not ready. Train with house-chat-ensure! or /nn train."
              :model *house-chat-model*)))
    (unless (nn-path-allowed-p m)
      (return-from house-chat-generate
        (list :freeform :refuse
              :refused t
              :source :tms-out
              :reply-text
              "I can't generate: neural path is disabled (TMS OUT). Use /nn enable."
              :reason "TMS nn-path-enabled is OUT")))
    (let* ((cond-prefix (%house-condition-prefix))
           (active (mapcar (lambda (c) (getf c :id)) (symbol-model-active)))
           (prompt
            (with-output-to-string (out)
              (when (and cond-prefix (plusp (length cond-prefix)))
                (write-string cond-prefix out))
              (when (and context (plusp (length (string-trim '(#\Space) context))))
                (format out "Context:~%~A~%"
                        (truncate-string context 800)))
              (format out "User: ~A~%Metis: " q)))
           (gen (handler-case
                    (nn-generate *house-chat-model*
                                 :prompt prompt
                                 :length length
                                 :temperature 0.9
                                 :mind m)
                  (error (e)
                    (return-from house-chat-generate
                      (list :freeform :house-chat
                            :source :house-chat
                            :ok nil
                            :error (princ-to-string e)
                            :reply-text
                            (format nil "House generate failed: ~A" e)
                            :model *house-chat-model*)))))
           ;; Prefer cleaned text; if sketchy, still return house path with
           ;; a minimal honest English wrapper (path correctness over fluency).
           (clean (and gen
                       (or (and (fboundp '%iface-englishish-p)
                                (%iface-englishish-p gen))
                           (and (>= (length gen) 8)
                                (>= (count-if #'alpha-char-p gen) 4)))))
           (reply
            (cond
              (clean (string-trim '(#\Space #\Tab #\Newline) gen))
              ((and gen (plusp (length gen)))
               (format nil "~A" (string-trim '(#\Space #\Tab #\Newline) gen)))
              (t "…"))))
      (list :freeform :house-chat
            :source :house-chat
            :model *house-chat-model*
            :ok t
            :conditioned-by active
            :condition-prefix cond-prefix
            :prompt prompt
            :text gen
            :reply-text reply
            :house-spine t))))

(defun house-chat-freeform-answer (question &key (mind nil) (context nil)
                                              (length 80))
  "Product residual freeform entry: house spine only (no external LLM)."
  (declare (ignore context)) ;; context folded inside house-chat-generate when passed
  (house-chat-generate question :mind mind :length length :ensure t
                       :context context))
