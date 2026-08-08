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
  "Load domain pack file (facts + rules + optional couple-templates) into MIND."
  (let* ((path (truename pack-path))
         (form (with-open-file (in path)
                 (let ((*package* (find-package :metis)))
                   (read in))))
         (facts (cdr (assoc 'facts form)))
         (rules (cdr (assoc 'rules form)))
         (templates (cdr (assoc 'couple-templates form)))
         (n-facts 0)
         (n-rules 0)
         (tmpl-info nil))
    (dolist (f facts)
      (assert-fact mind f :support :domain-pack :forward nil)
      (incf n-facts))
    (dolist (r rules)
      ;; r = (head body) where body is list of premise literals
      (assert-rule mind (first r) (second r) :name :domain-pack)
      (incf n-rules))
    (when templates
      (setf tmpl-info
            (register-coupled-templates! templates
                                         :source (intern (file-namestring path)
                                                         :keyword))))
    (list :loaded t
          :path (namestring path)
          :facts n-facts
          :rules n-rules
          :couple-templates (and templates (length templates))
          :template-registration tmpl-info
          :mind (mind-name mind))))

(defun symbol-marketplace-catalog (&key (root nil))
  "Open marketplace: knowledge symbol packs + in-tree code symbols.
   No payments/accounts. GPU is core (not listed as a knowledge product)."
  (declare (ignore root))
  (symbol-pack-ensure-seeds!)
  (let* ((knowledge (getf (symbol-pack-catalog) :catalog))
         (sys-root (asdf:system-source-directory :metis))
         (sym-root (merge-pathnames "symbols/" sys-root))
         (code-packs nil))
    (when (probe-file sym-root)
      (dolist (d (directory (merge-pathnames "*/" sym-root)))
        (let* ((id (car (last (pathname-directory d))))
               (manifest (merge-pathnames "manifest.lisp" d))
               (sig (merge-pathnames "symbol.sig" d)))
          ;; skip gpu-nn as marketplace knowledge; still a built-in accel
          (when (and (probe-file manifest)
                     (not (string-equal id "gpu-nn"))
                     (not (string-equal id "knowledge")))
            (push (list :id id
                        :path (namestring d)
                        :manifest (namestring manifest)
                        :signed (and (probe-file sig) t)
                        :installable t
                        :kind :code
                        :open t
                        :payment nil)
                  code-packs)))))
    (list :marketplace t
          :payments nil
          :accounts nil
          :unit "symbols"
          :knowledge knowledge
          :knowledge-count (length knowledge)
          :packages (sort (append
                           (mapcar (lambda (e)
                                     (list :id (getf e :id)
                                           :path (getf e :path)
                                           :kind :knowledge
                                           :license (getf e :license)
                                           :open t
                                           :payment nil
                                           :installable t))
                                   knowledge)
                           code-packs)
                          #'string<
                          :key (lambda (p) (getf p :id)))
          :count (+ (length knowledge) (length code-packs))
          :install-via 'install-symbol!
          :knowledge-install-via 'symbol-pack-catalog-install
          :note "Open knowledge packs via /symbol-pack; GPU is built-in accel not a store SKU")))

(defun symbol-marketplace-install (id-or-path &key (enable t)
                                              (require-signature t))
  "Install a marketplace package by id (in-tree symbols/) or path/URL.
   REQUIRE-SIGNATURE defaults T (signed packages are the product norm).
   In-tree first-party boot remains unsigned via symbols-boot! / enable-symbol!."
  (let* ((catalog (symbol-marketplace-catalog))
         (by-id (find id-or-path (getf catalog :packages)
                      :key (lambda (p) (getf p :id))
                      :test #'string=))
         (src (if by-id (getf by-id :path) id-or-path))
         (remote (and (stringp src)
                      (or (eql 0 (search "http://" src))
                          (eql 0 (search "https://" src))
                          (eql 0 (search "file://" src))))))
    (let ((nid (cond (by-id (getf by-id :id))
                     ((and (stringp id-or-path)
                           (not (or (search "/" id-or-path)
                                    (search "\\" id-or-path)
                                    (search ":" id-or-path))))
                      id-or-path)
                     (t (let ((p (uiop:ensure-directory-pathname src)))
                          (or (car (last (pathname-directory p)))
                              "symbol"))))))
      (install-symbol! src :id nid
                       :enable enable
                       :require-signature require-signature
                       :trust-remote (or remote require-signature)))))

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
