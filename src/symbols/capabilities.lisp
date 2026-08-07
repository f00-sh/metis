;;;; capabilities.lisp — product entry points used by category symbols
(in-package :metis)

(defun chat-ui-summary (&optional session-id)
  "Summarize turns for SESSION-ID (or current session)."
  (let* ((s (or (and session-id (session-get session-id))
                (session-ensure)))
         (turns (reverse (sess-turns s)))
         (n (length turns))
         (users (count :user turns :key (lambda (turn) (getf turn :role))))
         (assts (count :assistant turns :key (lambda (turn) (getf turn :role)))))
    (list :session (sess-id s)
          :turns n
          :user-turns users
          :assistant-turns assts
          :attachments (length (session-list-attachments s))
          :last (when turns
                  (list :role (getf (first (last turns)) :role)
                        :text (truncate-string
                               (or (getf (first (last turns)) :text) "")
                               120))))))

(defun chat-ui-transcript (&optional session-id)
  "Full transcript of session turns."
  (let ((s (or (and session-id (session-get session-id))
               (session-ensure))))
    (list :session (sess-id s)
          :transcript
          (mapcar (lambda (turn)
                    (list :role (getf turn :role)
                          :text (getf turn :text)
                          :time (getf turn :time)))
                  (reverse (sess-turns s))))))

(defun image-ingest-session (&optional session-id)
  "Ingest photo attachments: assert provenance facts and return captions/corpus."
  (let* ((s (or (and session-id (session-get session-id))
                (session-ensure)))
         (m (sess-mind s))
         (photos nil)
         (corpus-parts nil))
    (maphash
     (lambda (_ a)
       (declare (ignore _))
       (when (eq (att-kind a) :photo)
         (let ((fact (list 'image-ingested (att-id a)
                           (or (att-path a) "")
                           (or (att-media-type a) "image")
                           (or (att-size a) 0))))
           (assert-fact m fact :support :image-ingest :forward nil)
           (when (att-caption a)
             (push (att-caption a) corpus-parts)
             (assert-fact m (list 'image-caption (att-id a) (att-caption a))
                          :support :image-ingest :forward nil))
           (push (list :id (att-id a)
                       :path (att-path a)
                       :media-type (att-media-type a)
                       :size (att-size a)
                       :caption (att-caption a))
                 photos))))
     (sess-attachments s))
    (list :session (sess-id s)
          :ingested (length photos)
          :photos (nreverse photos)
          :corpus (format nil "~{~A~%~}" (nreverse corpus-parts)))))

(defun domain-pack-load (mind pack-path)
  "Load domain pack file (facts + rules) into MIND."
  (let* ((path (truename pack-path))
         (form (with-open-file (in path)
                 (let ((*package* (find-package :metis)))
                   (read in))))
         (facts (cdr (assoc 'facts form)))
         (rules (cdr (assoc 'rules form)))
         (n-facts 0)
         (n-rules 0))
    (dolist (f facts)
      (assert-fact mind f :support :domain-pack :forward nil)
      (incf n-facts))
    (dolist (r rules)
      ;; r = (head body) where body is list of premise literals
      (assert-rule mind (first r) (second r) :name :domain-pack)
      (incf n-rules))
    (list :loaded t
          :path (namestring path)
          :facts n-facts
          :rules n-rules
          :mind (mind-name mind))))

(defun curriculum-apply (curriculum-path &key (name "curriculum-lm")
                                            (epochs 2)
                                            (hidden 64)
                                            (seq-len 128)
                                            (depth 3)
                                            (max-batches 20))
  "Apply curriculum text file via continuous train (deeper/longer defaults)."
  (let* ((text (uiop:read-file-string curriculum-path))
         (backend-before (nn-backend-status))
         (r (nn-continuous-train text
                                 :name name
                                 :epochs epochs
                                 :hidden hidden
                                 :seq-len seq-len
                                 :depth depth
                                 :max-batches max-batches)))
    (list* :curriculum (namestring curriculum-path)
           :backend backend-before
           :backend-after (nn-backend-status)
           :op-counts (metis.symbols:nn-backend-op-counts)
           r)))
