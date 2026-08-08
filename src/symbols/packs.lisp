;;;; packs.lisp — open-knowledge hybrid symbol packs (A1/B1/C1/D/E1/F1)
;;;; Product unit name: **symbols**. GPU is core accel, not a knowledge pack.
(in-package :metis)

(defparameter *symbol-pack-registry-dir*
  (merge-pathnames ".metis/symbols/registry/"
                   (user-homedir-pathname))
  "Permanent installed open-knowledge packs.")

(defparameter *symbol-pack-overlays* nil
  "Session overlays (newest first): list of (:id :path :temporary t).")

(defparameter *symbol-pack-enabled* (make-hash-table :test #'equal)
  "id → T when permanently enabled.")

(defparameter *symbol-pack-layer-store* (make-hash-table :test #'equal)
  "id → (:id :facts :rules :path :temporary :mind) — facts claimed by this layer.")

(defparameter *symbol-pack-fact-refcount* (make-hash-table :test #'equal)
  "fact → count of active *pack* layers claiming that fact.")

(defparameter *symbol-pack-base-pins* (make-hash-table :test #'equal)
  "fact → T when F was already live in the mind before any pack claimed it.
   Pack release must never retract base-pinned facts.")

(defparameter *symbol-pack-rule-refcount* (make-hash-table :test #'equal)
  "rule-name keyword → count of layers. Remove rule only at 0.")

(defun symbol-pack-registry-dir ()
  (uiop:ensure-directory-pathname *symbol-pack-registry-dir*))

(defun %pack-fact-key (f)
  "Canonical key for refcount (equal-based)."
  f)

(defun %pack-rule-key (id)
  (intern (format nil "PACK-~A" id) :keyword))

(defun %pack-refcount-inc! (table key)
  (setf (gethash key table) (1+ (or (gethash key table) 0))))

(defun %pack-refcount-dec! (table key)
  (let ((n (1- (or (gethash key table) 0))))
    (if (<= n 0)
        (progn (remhash key table) 0)
        (progn (setf (gethash key table) n) n))))

(defun %pack-base-pinned-p (fact)
  (gethash (%pack-fact-key fact) *symbol-pack-base-pins*))

(defun %pack-pin-base! (fact)
  (setf (gethash (%pack-fact-key fact) *symbol-pack-base-pins*) t))

(defun %pack-layer-put! (id &key facts rules path temporary mind)
  (setf (gethash id *symbol-pack-layer-store*)
        (list :id id
              :facts (copy-list (or facts nil))
              :rules (copy-list (or rules nil))
              :path path
              :temporary (and temporary t)
              :mind mind)))

(defun %pack-layer-get (id)
  (gethash id *symbol-pack-layer-store*))

(defun %pack-claim-facts! (mind facts id)
  "Multi-owner claim with explicit base pin.
   If F already live and no pack yet owns it, pin :base so pack release cannot wipe base.
   Only assert-fact when F was not already live. Always +1 pack refcount for this layer."
  (declare (ignore id))
  (let ((n 0))
    (dolist (f facts)
      (when (consp f)
        (let* ((key (%pack-fact-key f))
               (prev (or (gethash key *symbol-pack-fact-refcount*) 0))
               (live (ignore-errors (kb-holds-p (mind-kb mind) f))))
          (when (and (zerop prev) live)
            ;; external/base owner already holds F — pin so we never retract it
            (%pack-pin-base! f))
          (when (and (zerop prev) (not live))
            (assert-fact mind f :support :symbol-pack :forward nil))
          (%pack-refcount-inc! *symbol-pack-fact-refcount* key)
          (incf n))))
    n))

(defun %pack-claim-rules! (mind rules id)
  "One refcount unit per pack-id for the pack's whole rule set (pack-namespaced names)."
  (let ((n 0)
        (rkey (%pack-rule-key id))
        (prev (or (gethash (%pack-rule-key id) *symbol-pack-rule-refcount*) 0)))
    (when (zerop prev)
      (dolist (r rules)
        (when (and (consp r) (consp (first r)))
          (assert-rule mind (first r) (second r) :name rkey)
          (incf n))))
    (when (or (plusp n) (plusp (length rules)))
      (%pack-refcount-inc! *symbol-pack-rule-refcount* rkey)
      (when (zerop n) (setf n (length rules))))
    n))

(defun %pack-release-facts! (mind facts)
  "Dec pack claim only. Retract iff pack-refcount→0 AND not base-pinned."
  (let ((released 0) (kept 0) (base-kept 0))
    (dolist (f facts)
      (when (consp f)
        (let* ((key (%pack-fact-key f))
               (left (%pack-refcount-dec! *symbol-pack-fact-refcount* key))
               (base-p (%pack-base-pinned-p f)))
          (cond
            ((and (zerop left) (not base-p))
             (ignore-errors (retract-fact mind f))
             (incf released))
            ((and (zerop left) base-p)
             ;; last pack released; base pin remains — fact stays in mind
             (incf base-kept))
            (t (incf kept))))))
    (values released kept base-kept)))

(defun %pack-release-rules! (mind id rules)
  "Drop pack rule-set when last layer claim releases (rules are pack-namespaced)."
  (declare (ignore rules))
  (let ((rkey (%pack-rule-key id))
        (n 0))
    (let ((left (%pack-refcount-dec! *symbol-pack-rule-refcount* rkey)))
      (when (zerop left)
        (loop while (ignore-errors (kb-remove-rule (mind-kb mind) rkey))
              do (incf n))))
    n))

(defun %pack-retract-layer! (id &key (mind nil))
  "Drop pack ID layer. Retract facts/rules only if no other layer still claims them."
  (let* ((rec (%pack-layer-get id))
         (m (or mind (and rec (getf rec :mind)) *mind*))
         (released 0) (kept 0) (n-r 0))
    (when (and rec m)
      (multiple-value-bind (rel kpt base-k)
          (%pack-release-facts! m (getf rec :facts))
        (declare (ignore base-k))
        (setf released rel kept kpt))
      (setf n-r (%pack-release-rules! m id (getf rec :rules)))
      (remhash id *symbol-pack-layer-store*))
    (list :retracted t :id id
          :facts-released released
          :facts-kept kept
          :rules n-r)))

(defun %pack-match-fact (pattern fact)
  "T if PATTERN matches FACT (equal, or vars as ?x / symbols starting with ?)."
  (cond
    ((equal pattern fact) t)
    ((and (consp pattern) (consp fact)
          (= (length pattern) (length fact)))
     (every (lambda (p f)
              (or (equal p f)
                  (and (symbolp p)
                       (let ((n (symbol-name p)))
                         (and (plusp (length n)) (char= (char n 0) #\?))))))
            pattern fact))
    (t nil)))

(defun %pack-fact-live-p (mind fact)
  "T if FACT currently holds in MIND's KB."
  (and mind fact
       (ignore-errors (kb-holds-p (mind-kb mind) fact))))

(defun %pack-now ()
  (multiple-value-bind (s m h d mo y) (get-decoded-time)
    (declare (ignore s m h d mo))
    (format nil "~4,'0D" y)))

(defun %pack-file-sha256 (path)
  "Content hash for provenance pins. Uses openssl if present, else ironclad-free fallback."
  (cond
    ((not (probe-file path)) nil)
    (t
     (or
      (ignore-errors
        (let ((raw (uiop:run-program
                    (list "sha256sum" (namestring (truename path)))
                    :output :string :ignore-error-status t)))
          (string-downcase
           (string-trim
            '(#\Space #\Newline #\Tab #\Return)
            (or (first (cl-ppcre:split "\\s+" (or raw ""))) "")))))
      (ignore-errors
        (let* ((out (uiop:run-program
                     (list "sh" "-c"
                           (format nil "sha256sum ~S | awk '{print $1}'"
                                   (namestring (truename path))))
                     :output :string :ignore-error-status t)))
          (string-downcase
           (string-trim '(#\Space #\Newline #\Tab #\Return)
                        (or (first (cl-ppcre:split "\\s+" (or out ""))) "")))))
      ;; last resort: size+mtime fingerprint (not crypto; still pins local identity)
      (format nil "weak:~A:~A"
              (ignore-errors (file-length (open path :direction :probe)))
              (ignore-errors (file-write-date path)))))))

(defun make-symbol-pack-manifest
    (&key (id "unnamed")
          (name id)
          (version "0.1.0")
          (description "")
          (license "MIT")
          (sources nil)
          (weights-policy :reproducible-from-data)
          (repro-level :best-effort)
          (build-recipe nil)
          (kind :knowledge)
          (extra nil))
  "A1+E1 manifest. SOURCES = list of plists (:url :license :date :content-hash :note)."
  (append
   (list :metis-symbol-pack 1
         :id id
         :name name
         :version version
         :description description
         :license license
         :kind kind
         :weights-policy weights-policy
         :repro-level repro-level
         :sources (or sources nil)
         :build-recipe (or build-recipe
                           (list :steps '("assert facts/rules from pack.lisp"
                                          "optional: load ckpt if included")
                                 :tool "metis"))
         :created (%pack-now))
   extra))

(defun symbol-pack-validate-manifest (manifest)
  "T if MANIFEST has required open-knowledge fields."
  (and (consp manifest)
       (eql (getf manifest :metis-symbol-pack) 1)
       (stringp (getf manifest :id))
       (plusp (length (getf manifest :id)))
       (stringp (getf manifest :license))
       (member (getf manifest :weights-policy)
               '(:included :reproducible-from-data :optional-download
                 "included" "reproducible-from-data" "optional-download")
               :test #'equal)
       (listp (getf manifest :sources))
       t))

(defun symbol-pack-write! (dir manifest &key (facts nil) (rules nil) (corpus nil) (ckpt nil))
  "Write a hybrid pack directory: manifest.lisp + pack.lisp + optional corpus/ckpt."
  (let* ((dir (uiop:ensure-directory-pathname dir))
         (man-path (merge-pathnames "manifest.lisp" dir))
         (pack-path (merge-pathnames "pack.lisp" dir)))
    (ensure-directories-exist dir)
    (unless (symbol-pack-validate-manifest manifest)
      (error "invalid symbol pack manifest"))
    (with-open-file (out man-path :direction :output :if-exists :supersede
                         :if-does-not-exist :create)
      (let ((*print-pretty* t)
            (*package* (find-package :metis)))
        (prin1 manifest out)
        (terpri out)))
    (with-open-file (out pack-path :direction :output :if-exists :supersede
                         :if-does-not-exist :create)
      (let ((*print-pretty* t)
            (*print-case* :downcase)
            (*package* (find-package :keyword)))
        ;; keyword plist is package-stable across readers
        (prin1 (list :metis-pack 1
                     :facts (or facts nil)
                     :rules (or rules nil)
                     :corpus-inline corpus)
               out)
        (terpri out)))
    (when corpus
      (with-open-file (out (merge-pathnames "corpus.txt" dir)
                           :direction :output :if-exists :supersede
                           :if-does-not-exist :create)
        (write-string (if (stringp corpus) corpus
                          (format nil "~{~A~%~}" corpus))
                      out)))
    (when (and ckpt (probe-file ckpt))
      (uiop:copy-file ckpt (merge-pathnames "model.ckpt" dir)))
    (list :path (namestring dir)
          :manifest man-path
          :id (getf manifest :id))))

(defun symbol-pack-read-manifest (dir)
  (let ((p (merge-pathnames "manifest.lisp"
                            (uiop:ensure-directory-pathname dir))))
    (unless (probe-file p)
      (error "no manifest.lisp in ~A" dir))
    (with-open-file (in p)
      (let ((*package* (find-package :metis)))
        (read in)))))

(defun symbol-pack-read-body (dir)
  (let ((p (merge-pathnames "pack.lisp"
                            (uiop:ensure-directory-pathname dir))))
    (if (probe-file p)
        (with-open-file (in p)
          (let ((*package* (find-package :metis)))
            (read in)))
        nil)))

(defun %pack-body-facts (body)
  (cond
    ((null body) nil)
    ((and (consp body) (eq (first body) :metis-pack))
     (getf body :facts))
    ((and (consp body) (eq (first body) 'pack))
     (or (cdr (assoc 'facts (cdr body) :test #'string-equal))
         (getf (cdr body) :facts)))
    ((consp body) (or (getf body :facts)
                      (cdr (assoc 'facts body :test #'string-equal))))
    (t nil)))

(defun %pack-body-rules (body)
  (cond
    ((null body) nil)
    ((and (consp body) (eq (first body) :metis-pack))
     (getf body :rules))
    ((and (consp body) (eq (first body) 'pack))
     (or (cdr (assoc 'rules (cdr body) :test #'string-equal))
         (getf (cdr body) :rules)))
    ((consp body) (or (getf body :rules)
                      (cdr (assoc 'rules body :test #'string-equal))))
    (t nil)))

(defun symbol-pack-load-into-mind! (mind dir &key (support :symbol-pack)
                                              (temporary nil)
                                              (track-layer t))
  "Load symbolic facts/rules from pack DIR into MIND. Tracks layer for retract.
   Returns load stats including :fact-list / :rule-list owned by this pack."
  (let* ((man (symbol-pack-read-manifest dir))
         (body (symbol-pack-read-body dir))
         (facts (remove-if-not #'consp (%pack-body-facts body)))
         (rules (remove-if-not (lambda (r) (and (consp r) (consp (first r))))
                               (%pack-body-rules body)))
         (n-f 0) (n-r 0)
         (id (getf man :id))
         (path (namestring (uiop:ensure-directory-pathname dir)))
         (m (ensure-mind mind)))
    (declare (ignore support))
    (unless (symbol-pack-validate-manifest man)
      (error "pack manifest invalid: ~A" dir))
    ;; replace prior layer for same id (re-enable / re-overlay) — refcount-safe
    (when (and track-layer (%pack-layer-get id))
      (%pack-retract-layer! id :mind m))
    (setf n-f (%pack-claim-facts! m facts id)
          n-r (%pack-claim-rules! m rules id))
    (when track-layer
      (%pack-layer-put! id :facts facts :rules rules :path path
                        :temporary temporary :mind m))
    ;; optional corpus into current session when available (session loads later)
    (let* ((corp (merge-pathnames "corpus.txt"
                                  (uiop:ensure-directory-pathname dir)))
           (sess-sym (find-symbol "*SESSION*" :metis))
           (sess (and sess-sym (boundp sess-sym) (symbol-value sess-sym)))
           (train-fn (find-symbol "SESSION-TRAIN-ON-TEXT!" :metis)))
      (when (and (probe-file corp) sess train-fn (fboundp train-fn))
        (ignore-errors
          (funcall train-fn sess
                   (uiop:read-file-string corp)
                   :name (format nil "pack-~A" id)
                   :async nil
                   :intensity :hard
                   :source :symbol-pack))))
    (list :id id
          :facts n-f
          :rules n-r
          :fact-list facts
          :rule-list rules
          :manifest man
          :path path
          :temporary (and temporary t))))

;;; ---- B1 export / import snapshot ---------------------------------

(defun symbol-export-snapshot! (mind path &key (corpus nil) (ckpt nil) (label "snapshot"))
  "B1: export mind KB (+ optional corpus/ckpt) as a portable symbol pack directory."
  (let* ((m (ensure-mind mind))
         (dir (uiop:ensure-directory-pathname path))
         (kb (kb-snapshot (mind-kb m)))
         (facts (getf kb :facts))
         (fact-list (remove-if-not #'consp (or facts nil)))
         (rules (mapcar (lambda (r)
                          (list (getf r :head) (getf r :body)))
                        (or (getf kb :rules) nil)))
         (sources (list (list :url (format nil "local://export/~A" label)
                              :license "user"
                              :date (%pack-now)
                              :content-hash "export"
                              :note "local mind snapshot")))
         (man (make-symbol-pack-manifest
               :id (format nil "snapshot-~A" (cl-ppcre:regex-replace-all "[^a-zA-Z0-9_-]" label "-"))
               :name label
               :version "0.0.1"
               :description "Exported local mind snapshot"
               :license "user"
               :sources sources
               :weights-policy (if ckpt :included :reproducible-from-data)
               :repro-level :best-effort)))
    (symbol-pack-write! dir man
                        :facts fact-list
                        :rules rules
                        :corpus corpus
                        :ckpt ckpt)
    (when (probe-file (merge-pathnames "manifest.lisp" dir))
      (let ((h (%pack-file-sha256 (merge-pathnames "manifest.lisp" dir))))
        (setf (getf man :export-hash) h)))
    (list :exported t
          :path (namestring dir)
          :id (getf man :id)
          :facts (length fact-list)
          :rules (length rules))))

(defun symbol-import-snapshot! (mind path)
  "B1: import a pack/snapshot directory into MIND."
  (symbol-pack-load-into-mind! mind path :support :import))

;;; ---- C1 permanent registry + session overlay ---------------------

(defun symbol-pack-install! (src &key (id nil) (temporary nil) (mind nil))
  "Install pack from local path (or file:// URL) into registry or session overlay.
   Temporary install loads into mind immediately and tracks layer for unload."
  (let* ((path (cond
                 ((and (stringp src) (eql 0 (search "file://" src)))
                  (subseq src 7))
                 ((pathnamep src) src)
                 (t src)))
         (path (uiop:ensure-directory-pathname (truename path)))
         (man (symbol-pack-read-manifest path))
         (pid (or id (getf man :id)))
         (m (or mind *mind* (boot))))
    (unless (symbol-pack-validate-manifest man)
      (error "cannot install invalid pack ~A" path))
    (if temporary
        (let ((stats (symbol-pack-load-into-mind! m path
                                                  :support :overlay
                                                  :temporary t
                                                  :track-layer t)))
          ;; newest overlay first
          (setf *symbol-pack-overlays*
                (cons (list :id pid :path (namestring path) :temporary t)
                      (remove pid *symbol-pack-overlays*
                              :key (lambda (x) (getf x :id))
                              :test #'string-equal)))
          (list :installed t :id pid :temporary t
                :path (namestring path) :stats stats))
        (let* ((dest (merge-pathnames
                      (format nil "~A/" pid)
                      (symbol-pack-registry-dir)))
               (src-ns (namestring path))
               (dst-ns (namestring dest))
               (same-dir (or (equal src-ns dst-ns)
                             (ignore-errors
                               (equal (namestring (truename path))
                                      (namestring (probe-file dest)))))))
          (ensure-directories-exist dest)
          ;; Never copy a path onto itself — uiop:copy-file truncates to empty.
          (unless same-dir
            (dolist (f '("manifest.lisp" "pack.lisp" "corpus.txt" "model.ckpt"))
              (let ((from (merge-pathnames f path))
                    (to (merge-pathnames f dest)))
                (when (and (probe-file from)
                           (or (null (probe-file to))
                               (not (equal (ignore-errors (namestring (truename from)))
                                           (ignore-errors (namestring (truename to)))))))
                  (uiop:copy-file from to)))))
          (setf (gethash pid *symbol-pack-enabled*) nil)
          (list :installed t :id pid :temporary nil
                :path (namestring dest)
                :enabled nil
                :copied (not same-dir))))))

(defun symbol-pack-enable! (id &key (mind nil))
  "Load a permanently installed pack into MIND, track layer, mark enabled."
  (let* ((m (or mind *mind* (boot)))
         (dir (merge-pathnames (format nil "~A/" id)
                               (symbol-pack-registry-dir))))
    (unless (probe-file (merge-pathnames "manifest.lisp" dir))
      (error "pack not installed: ~A" id))
    (let ((stats (symbol-pack-load-into-mind! m dir
                                              :support :registry
                                              :temporary nil
                                              :track-layer t))
          (man (symbol-pack-read-manifest dir)))
      (setf (gethash id *symbol-pack-enabled*) t)
      (when (fboundp '%symbol-register-caps-from-manifest!)
        (%symbol-register-caps-from-manifest! id man))
      ;; Model-package conditioning on the house chat spine (not RAG-only)
      (when (fboundp 'symbol-model-on-enable!)
        (ignore-errors (symbol-model-on-enable! id man :dir dir)))
      (list :enabled t :id id :stats stats))))

(defun symbol-pack-disable! (id &key (mind nil))
  "Disable permanent pack: retract its layer facts/rules from MIND."
  (let ((m (or mind *mind*))
        (retract nil))
    (setf (gethash id *symbol-pack-enabled*) nil)
    (when (%pack-layer-get id)
      (setf retract (%pack-retract-layer! id :mind m)))
    (when (fboundp '%symbol-unregister-caps!)
      (%symbol-unregister-caps! id))
    (when (fboundp 'symbol-model-on-disable!)
      (ignore-errors (symbol-model-on-disable! id)))
    (list :enabled nil :id id :retract retract)))

(defun symbol-pack-overlay-unload! (id &key (mind nil))
  "Unload temporary overlay: retract layer facts/rules and drop overlay record."
  (let ((retract (%pack-retract-layer! id :mind (or mind *mind*))))
    (setf *symbol-pack-overlays*
          (remove id *symbol-pack-overlays*
                  :key (lambda (x) (getf x :id))
                  :test #'string-equal))
    (when (fboundp '%symbol-unregister-caps!)
      (%symbol-unregister-caps! id))
    (list :unloaded t :id id
          :remaining (length *symbol-pack-overlays*)
          :retract retract)))

(defun symbol-pack-query (pattern &key (mind nil))
  "Multi-symbol layered query with precedence:
   1) temporary overlays (newest first)
   2) permanently enabled registry packs
   3) base mind facts not owned by any pack layer
   Only returns facts that are live in MIND (no ghost hits after bad retract).
   Returns (values fact layer-id layer-kind) or NIL."
  (let ((m (or mind *mind*)))
    (labels ((live (f) (%pack-fact-live-p m f)))
      ;; 1 overlays
      (dolist (ov *symbol-pack-overlays*)
        (let* ((id (getf ov :id))
               (rec (%pack-layer-get id)))
          (when rec
            (dolist (f (getf rec :facts))
              (when (and (%pack-match-fact pattern f) (live f))
                (return-from symbol-pack-query
                  (values f id :overlay)))))))
      ;; 2 enabled registry (sorted ids for stability)
      (let ((ids nil))
        (maphash (lambda (id en) (when en (push id ids))) *symbol-pack-enabled*)
        (dolist (id (sort ids #'string<))
          (let ((rec (%pack-layer-get id)))
            (when (and rec (not (getf rec :temporary)))
              (dolist (f (getf rec :facts))
                (when (and (%pack-match-fact pattern f) (live f))
                  (return-from symbol-pack-query
                    (values f id :registry))))))))
      ;; 3 base mind — skip facts still owned by any active layer
      (let ((owned (make-hash-table :test #'equal)))
        (maphash (lambda (_ rec)
                   (dolist (f (getf rec :facts))
                     (setf (gethash f owned) t)))
                 *symbol-pack-layer-store*)
        (when m
          (dolist (f (facts m))
            (unless (gethash f owned)
              (when (%pack-match-fact pattern f)
                (return-from symbol-pack-query
                  (values f :base :base)))))))
      nil)))

(defun symbol-pack-query-all (pattern &key (mind nil) (limit 50))
  "All layered matches with precedence tags. List of (:fact :layer :kind).
   Skips ghosts (layer-store hits not live in MIND)."
  (let ((m (or mind *mind*))
        (out nil)
        (n 0))
    (labels ((take (f id kind)
               (when (and f (< n limit)
                          (%pack-match-fact pattern f)
                          (or (eq kind :base) (%pack-fact-live-p m f)))
                 (push (list :fact f :layer id :kind kind) out)
                 (incf n))))
      (dolist (ov *symbol-pack-overlays*)
        (let ((rec (%pack-layer-get (getf ov :id))))
          (when rec
            (dolist (f (getf rec :facts))
              (take f (getf ov :id) :overlay)))))
      (let ((ids nil))
        (maphash (lambda (id en) (when en (push id ids))) *symbol-pack-enabled*)
        (dolist (id (sort ids #'string<))
          (let ((rec (%pack-layer-get id)))
            (when (and rec (not (getf rec :temporary)))
              (dolist (f (getf rec :facts))
                (take f id :registry))))))
      (let ((owned (make-hash-table :test #'equal)))
        (maphash (lambda (_ rec)
                   (dolist (f (getf rec :facts))
                     (setf (gethash f owned) t)))
                 *symbol-pack-layer-store*)
        (when m
          (dolist (f (facts m))
            (unless (gethash f owned)
              (take f :base :base))))))
    (nreverse out)))

(defun symbol-pack-clear-layers! ()
  "Test helper: clear layer + refcount + base-pin tables (does not touch mind)."
  (clrhash *symbol-pack-layer-store*)
  (clrhash *symbol-pack-fact-refcount*)
  (clrhash *symbol-pack-base-pins*)
  (clrhash *symbol-pack-rule-refcount*)
  (setf *symbol-pack-overlays* nil)
  t)

(defun symbol-pack-list-installed ()
  (let ((root (symbol-pack-registry-dir))
        (out nil))
    (ensure-directories-exist root)
    (dolist (p (directory (merge-pathnames "*/manifest.lisp" root)))
      (ignore-errors
        (let* ((dir (uiop:pathname-directory-pathname p))
               (man (symbol-pack-read-manifest dir))
               (id (getf man :id)))
          (push (list :id id
                      :path (namestring dir)
                      :enabled (gethash id *symbol-pack-enabled*)
                      :name (getf man :name)
                      :license (getf man :license)
                      :version (getf man :version))
                out))))
    (nreverse out)))

;;; ---- D open catalog (no payments) --------------------------------

(defun symbol-pack-seed-root ()
  "Open-knowledge seed packs live under knowledge/packs/ (not symbols/ code tree)."
  (merge-pathnames "knowledge/packs/"
                   (asdf:system-source-directory :metis)))

(defun symbol-pack-catalog (&key (include-installed t) (include-seeds t))
  "Open knowledge catalog: in-tree seeds + installed registry. No accounts/payments."
  (when include-seeds (ignore-errors (symbol-pack-ensure-seeds!)))
  (let ((entries nil))
    (when include-seeds
      (let ((root (symbol-pack-seed-root)))
        (when (probe-file root)
          (dolist (p (directory (merge-pathnames "*/manifest.lisp" root)))
            (ignore-errors
              (let* ((dir (uiop:pathname-directory-pathname p))
                     (man (symbol-pack-read-manifest dir)))
                (when (symbol-pack-validate-manifest man)
                  (push (list :id (getf man :id)
                              :name (getf man :name)
                              :version (getf man :version)
                              :license (getf man :license)
                              :description (getf man :description)
                              :category (getf man :category)
                              :capabilities (or (getf man :capabilities)
                                               (getf man :caps))
                              :source :seed
                              :path (namestring dir)
                              :weights-policy (getf man :weights-policy)
                              :sources (getf man :sources)
                              :open t
                              :payment nil)
                        entries))))))))
    (when include-installed
      (dolist (e (symbol-pack-list-installed))
        (push (append e (list :source :registry :open t :payment nil)) entries)))
    ;; GPU is NOT a knowledge catalog entry
    (setf entries (remove "gpu-nn" entries
                          :key (lambda (e) (getf e :id))
                          :test #'string-equal))
    ;; Prefer seed paths for install source (registry can be empty after a
    ;; bad self-copy). Mark installed when registry entry also exists.
    (let ((by-id (make-hash-table :test #'equal))
          (installed (make-hash-table :test #'equal)))
      (dolist (e entries)
        (let ((id (string-downcase (or (getf e :id) ""))))
          (when (eq (getf e :source) :registry)
            (setf (gethash id installed) t))
          (let ((prev (gethash id by-id)))
            (cond
              ((null prev) (setf (gethash id by-id) e))
              ;; keep seed over empty/broken registry as install path
              ((and (eq (getf prev :source) :registry)
                    (eq (getf e :source) :seed))
               (setf (gethash id by-id)
                     (append e (list :installed t))))
              ((and (eq (getf prev :source) :seed)
                    (eq (getf e :source) :registry))
               (setf (gethash id by-id)
                     (append prev (list :installed t))))
              (t nil)))))
      (let ((final nil))
        (maphash (lambda (_ e)
                   (declare (ignore _))
                   (let* ((id (string-downcase (or (getf e :id) "")))
                          (e2 (if (and (gethash id installed)
                                       (not (getf e :installed)))
                                  (append e (list :installed t))
                                  e)))
                     (push e2 final)))
                 by-id)
        (setf final (sort final #'string-lessp
                          :key (lambda (e) (or (getf e :id) ""))))
        (list :catalog final
              :count (length final)
              :payments nil
              :accounts nil
              :unit "symbols")))))

(defun symbol-pack-catalog-install (id-or-path &key (temporary nil))
  "Install from catalog id (seed) or filesystem path/URL."
  (let ((id id-or-path))
    (cond
      ((or (pathnamep id-or-path)
           (and (stringp id-or-path)
                (or (eql 0 (search "/" id-or-path))
                    (eql 0 (search "file://" id-or-path))
                    (eql 0 (search "./" id-or-path)))))
       (symbol-pack-install! id-or-path :temporary temporary))
      (t
       (let* ((cat (getf (symbol-pack-catalog) :catalog))
              (hit (find id cat :key (lambda (e) (getf e :id)) :test #'string-equal)))
         (unless hit (error "unknown catalog symbol ~A" id))
         (symbol-pack-install! (getf hit :path)
                               :id id
                               :temporary temporary))))))

(defun symbol-pack-ensure-seeds! ()
  "Create seed open packs if missing (dictionary, sample domain, cl-docs-lite)."
  (let ((root (symbol-pack-seed-root)))
    (ensure-directories-exist root)
    ;; 1) tiny English dictionary
    (let ((d (merge-pathnames "dict-en-lite/" root)))
      (unless (probe-file (merge-pathnames "manifest.lisp" d))
        (symbol-pack-write!
         d
         (make-symbol-pack-manifest
          :id "dict-en-lite"
          :name "English Dictionary (lite)"
          :version "0.1.0"
          :description "Tiny open dictionary seed"
          :license "CC0-1.0"
          :sources (list (list :url "https://example.invalid/dict-en-lite"
                               :license "CC0-1.0"
                               :date (%pack-now)
                               :content-hash "seed-dict-en-lite"
                               :note "embedded seed entries"))
          :weights-policy :reproducible-from-data
          :repro-level :best-effort)
         :facts '((word-def "cat" "a small domesticated carnivorous mammal")
                  (word-def "dog" "a domesticated carnivorous mammal")
                  (word-def "metis" "cunning intelligence; Greek goddess of wisdom")
                  (word-def "symbol" "a knowledge pack unit in Metis"))
         :rules '(((wordp ?w) ((word-def ?w ?d))))
         :corpus (list "cat: a small domesticated carnivorous mammal"
                       "dog: a domesticated carnivorous mammal"
                       "metis: cunning intelligence"))))
    ;; 2) animals sample
    (let ((d (merge-pathnames "animals-lite/" root)))
      (unless (probe-file (merge-pathnames "manifest.lisp" d))
        (symbol-pack-write!
         d
         (make-symbol-pack-manifest
          :id "animals-lite"
          :name "Animals (lite)"
          :version "0.1.0"
          :description "Sample animal encyclopedia seed"
          :license "CC0-1.0"
          :sources (list (list :url "https://example.invalid/animals-lite"
                               :license "CC0-1.0"
                               :date (%pack-now)
                               :content-hash "seed-animals-lite"
                               :note "embedded seed"))
          :weights-policy :reproducible-from-data)
         :facts '((animal "dolphin" "mammal")
                  (animal "eagle" "bird")
                  (animal "salmon" "fish")
                  (habitat "dolphin" "ocean")
                  (habitat "eagle" "sky")
                  (habitat "salmon" "river"))
         :corpus (list "Dolphins are ocean mammals."
                       "Eagles are birds of prey."
                       "Salmon spawn in rivers."))))
    ;; 3) Common Lisp docs lite (license-clear subset notes)
    (let ((d (merge-pathnames "cl-docs-lite/" root)))
      (unless (probe-file (merge-pathnames "manifest.lisp" d))
        (symbol-pack-write!
         d
         (make-symbol-pack-manifest
          :id "cl-docs-lite"
          :name "Common Lisp Docs (lite)"
          :version "0.1.0"
          :description "Tiny CL reference seed (not full HyperSpec)"
          :license "MIT"
          :sources (list (list :url "https://www.lispworks.com/documentation/HyperSpec/Front/"
                               :license "see-vendor"
                               :date (%pack-now)
                               :content-hash "seed-cl-docs-lite"
                               :note "educational subset only; not full HyperSpec copy"))
          :weights-policy :reproducible-from-data)
         :facts '((cl-fn "cons" "construct a cons cell")
                  (cl-fn "car" "first element of a list")
                  (cl-fn "cdr" "rest of a list")
                  (cl-fn "defun" "define a named function")
                  (cl-concept "REPL" "read-eval-print loop"))
         :corpus (list "CONS constructs pairs."
                       "DEFUN defines functions."
                       "The REPL reads, evaluates, prints."))))
    (list :seeds-ready t :root (namestring root)
          :ids '("dict-en-lite" "animals-lite" "cl-docs-lite"))))

(defun symbol-pack-boot! ()
  "Ensure seeds + registry dir exist. Call from boot."
  (ensure-directories-exist (symbol-pack-registry-dir))
  (symbol-pack-ensure-seeds!)
  t)

;;; ---- iface helpers -----------------------------------------------

(defun %iface-symbol-pack-command (text)
  "Parse /symbol-pack … and /symbols catalog/install knowledge commands."
  (let* ((t0 (string-trim '(#\Space #\Tab) (or text "")))
         (parts (cl-ppcre:split "\\s+" t0)))
    (cond
      ((string-equal (first parts) "/symbol-pack")
       (let ((sub (second parts)))
         (cond
           ((string-equal sub "catalog")
            (list :reply-text
                  (format nil "Open symbols catalog (~A entries, no payments):~%~{~A~%~}"
                          (getf (symbol-pack-catalog) :count)
                          (mapcar (lambda (e)
                                    (format nil "  ~A — ~A [~A]"
                                            (getf e :id)
                                            (or (getf e :name) "")
                                            (or (getf e :license) "")))
                                  (getf (symbol-pack-catalog) :catalog)))))
           ((string-equal sub "install")
            (let ((id (third parts)))
              (list :reply-text
                    (format nil "Installed: ~A"
                            (symbol-pack-catalog-install id)))))
           ((string-equal sub "enable")
            (list :reply-text
                  (format nil "Enabled: ~A"
                          (symbol-pack-enable! (third parts)))))
           ((string-equal sub "disable")
            (list :reply-text
                  (format nil "Disabled: ~A"
                          (symbol-pack-disable! (third parts)))))
           ((string-equal sub "export")
            (let ((path (or (third parts) "/tmp/metis-export-pack/")))
              (list :reply-text
                    (format nil "Exported: ~A"
                            (symbol-export-snapshot! (or *mind* (boot)) path)))))
           ((string-equal sub "import")
            (list :reply-text
                  (format nil "Imported: ~A"
                          (symbol-import-snapshot! (or *mind* (boot))
                                                   (third parts)))))
           ((string-equal sub "overlay")
            (list :reply-text
                  (format nil "Overlay: ~A"
                          (symbol-pack-catalog-install (third parts)
                                                       :temporary t))))
           ((string-equal sub "unload")
            (list :reply-text
                  (format nil "Unload: ~A"
                          (symbol-pack-overlay-unload! (third parts)))))
           (t (list :reply-text
                    "Usage: /symbol-pack catalog|install|enable|disable|export|import|overlay|unload")))))
      (t nil))))
