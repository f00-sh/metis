;;;; seal.lisp — sealed symbol packages (open-sealed + private-sealed)
;;;;
;;;; Shipped form: public header + opaque body + integrity signature.
;;;; Metis does not filter content. Engineering checks only (hash/sig/key).
;;;; Product claim: opaque + tamper-evident at rest. NOT unextractable under debugger.
(in-package :metis)

(defparameter *symbol-seal-magic* "METIS-SEAL-V1")
(defparameter *symbol-open-seal-label* "metis-open-sealed-v1"
  "Documented key-derivation label for open-sealed (reproducible) packages.")
(defparameter *symbol-marketplace-index* nil
  "In-memory marketplace fingerprint index (id → list of version records).")

;;; ---- crypto helpers (openssl) ------------------------------------

(defun %seal-sha256-file (path)
  "SHA-256 hex of file at PATH."
  (unless (probe-file path) (error "no file for hash: ~A" path))
  (let* ((out (uiop:run-program
               (list "openssl" "dgst" "-sha256"
                     (namestring (truename path)))
               :output :string))
         (pos (search "= " out)))
    (string-downcase
     (string-trim '(#\Space #\Newline #\Tab #\Return)
                  (if pos (subseq out (+ pos 2)) out)))))

(defun %seal-sha256-string (s)
  (let* ((out (uiop:run-program
               (list "openssl" "dgst" "-sha256")
               :input (make-string-input-stream (or s ""))
               :output :string))
         (pos (search "= " out)))
    (string-downcase
     (string-trim '(#\Space #\Newline #\Tab #\Return)
                  (if pos (subseq out (+ pos 2)) out)))))

(defun %seal-hmac-hex (secret message)
  (let* ((out (uiop:run-program
               (list "openssl" "dgst" "-sha256" "-hmac" (or secret ""))
               :input (make-string-input-stream (or message ""))
               :output :string))
         (pos (search "= " out)))
    (string-downcase
     (string-trim '(#\Space #\Newline #\Tab #\Return)
                  (if pos (subseq out (+ pos 2)) out)))))

(defun %seal-open-key (id version)
  "Reproducible open-sealed key material (documented; still opaque at rest)."
  (%seal-sha256-string
   (format nil "~A|~A|~A" *symbol-open-seal-label* id version)))

(defun %seal-open-salt-hex (id version)
  "16 hex digits (8 bytes) derived salt for open-sealed reproducibility."
  (subseq (%seal-sha256-string
           (format nil "salt|~A|~A|~A" *symbol-open-seal-label* id version))
          0 16))

(defun %seal-aes-encrypt (plaintext passphrase &key (out-path nil) (salt-hex nil))
  "AES-256-CBC encrypt PLAINTEXT with PASSPHRASE → binary at OUT-PATH.
   When SALT-HEX is provided (open-sealed), encryption is deterministic.
   When NIL (private-sealed), openssl generates a random salt (non-reproducible)."
  (let ((tmp-in (uiop:tmpize-pathname
                 (merge-pathnames "seal-in.txt" (uiop:temporary-directory))))
        (tmp-out (or out-path
                     (uiop:tmpize-pathname
                      (merge-pathnames "seal-out.bin"
                                       (uiop:temporary-directory))))))
    (unwind-protect
         (progn
           (with-open-file (o tmp-in :direction :output :if-exists :supersede
                              :if-does-not-exist :create
                              :element-type 'character)
             (write-string plaintext o))
           (let ((args (list "openssl" "enc" "-aes-256-cbc" "-pbkdf2"
                             "-in" (namestring tmp-in)
                             "-out" (namestring tmp-out)
                             "-pass" (format nil "pass:~A" passphrase))))
             (setf args (if salt-hex
                            (append args (list "-S" salt-hex))
                            (append args (list "-salt"))))
             (uiop:run-program args :output :string :error-output :string))
           (unless (probe-file tmp-out)
             (error "seal encrypt failed"))
           (namestring (truename tmp-out)))
      (ignore-errors (delete-file tmp-in))
      (when (and (null out-path) (probe-file tmp-out))
        nil))))

(defun %seal-aes-decrypt-file (in-path passphrase &key (salt-hex nil))
  "Decrypt AES body at IN-PATH with PASSPHRASE → plaintext string or signal.
   SALT-HEX required for open-sealed bodies sealed with fixed -S (no Salted__ header).
   NIL salt → openssl reads embedded Salted__ (private-sealed / random -salt)."
  (let ((tmp-out (uiop:tmpize-pathname
                  (merge-pathnames "seal-dec.txt" (uiop:temporary-directory)))))
    (unwind-protect
         (progn
           (handler-case
               (let ((args (list "openssl" "enc" "-d" "-aes-256-cbc" "-pbkdf2"
                                 "-in" (namestring (truename in-path))
                                 "-out" (namestring tmp-out)
                                 "-pass" (format nil "pass:~A" passphrase))))
                 (when salt-hex
                   (setf args (append args (list "-S" salt-hex))))
                 (uiop:run-program args :output :string :error-output :string))
             (error (e)
               (error "symbol seal decrypt failed (wrong key or corrupt body): ~A" e)))
           (unless (probe-file tmp-out)
             (error "symbol seal decrypt produced no output"))
           (with-open-file (in tmp-out :direction :input)
             (let ((s (make-string (file-length in))))
               (read-sequence s in)
               s)))
      (ignore-errors (when (probe-file tmp-out) (delete-file tmp-out))))))

;;; ---- header / body schema ----------------------------------------

(defun make-symbol-seal-header
    (&key (id "unnamed")
          (name id)
          (version "1.0.0")
          (description "")
          (license "MIT")
          (mode :open-sealed) ; :open-sealed | :private-sealed
          (trust-tier :community) ; :core :vetted :org :community :unvetted :local
          (depends-on nil)      ; list of (:id "x" :version ">=1.0" :role :required)
          (capabilities nil)
          (bibliography nil)    ; citations only (title url doi license date)
          (body-sha256 nil)
          (package-sha256 nil)
          (created nil)
          (extra nil))
  "Public header for a sealed symbol. Never contains knowledge payload."
  (append
   (list :metis-seal 1
         :magic *symbol-seal-magic*
         :id id
         :name name
         :version version
         :description description
         :license license
         :mode mode
         :trust-tier trust-tier
         :depends-on (or depends-on nil)
         :capabilities (or capabilities nil)
         :bibliography (or bibliography nil)
         :body-sha256 body-sha256
         :package-sha256 package-sha256
         :created (or created
                      (multiple-value-bind (s m h d mo y)
                          (get-decoded-time)
                        (declare (ignore s m h))
                        (format nil "~4,'0D-~2,'0D-~2,'0D" y mo d))))
   extra))

(defun symbol-seal-header-validate (header)
  (and (consp header)
       (eql (getf header :metis-seal) 1)
       (equal (getf header :magic) *symbol-seal-magic*)
       (stringp (getf header :id))
       (plusp (length (getf header :id)))
       (stringp (getf header :version))
       (member (getf header :mode)
               '(:open-sealed :private-sealed "open-sealed" "private-sealed")
               :test #'equal)
       (stringp (getf header :license))
       t))

(defun %seal-body-sexp (&key facts rules corpus capabilities meta)
  (with-standard-io-syntax
    (let ((*print-pretty* nil)
          (*print-circle* nil)
          (*package* (find-package :metis))
          (*print-readably* t))
      (prin1-to-string
       (list :metis-seal-body 1
             :facts (or facts nil)
             :rules (or rules nil)
             :corpus (or corpus nil)
             :capabilities (or capabilities nil)
             :meta (or meta nil))))))

(defun %seal-parse-body-sexp (s)
  (let ((*package* (find-package :metis))
        (*read-eval* nil))
    (let ((form (read-from-string s)))
      (unless (and (consp form) (eql (getf form :metis-seal-body) 1))
        (error "invalid seal body payload"))
      form)))

;;; ---- seal / verify / load ----------------------------------------

(defun symbol-seal-dir-p (dir)
  "T if DIR looks like a sealed symbol package."
  (let ((d (uiop:ensure-directory-pathname dir)))
    (and (probe-file (merge-pathnames "header.lisp" d))
         (probe-file (merge-pathnames "body.mse" d)))))

(defun symbol-seal-read-header (dir)
  (let ((p (merge-pathnames "header.lisp"
                            (uiop:ensure-directory-pathname dir))))
    (unless (probe-file p) (error "no header.lisp in ~A" dir))
    (with-open-file (in p)
      (let ((*package* (find-package :metis))
            (*read-eval* nil))
        (read in)))))

(defun symbol-seal-write-header! (dir header)
  (let ((p (merge-pathnames "header.lisp"
                            (uiop:ensure-directory-pathname dir))))
    (ensure-directories-exist dir)
    (with-open-file (out p :direction :output :if-exists :supersede
                         :if-does-not-exist :create)
      (let ((*print-pretty* t)
            (*package* (find-package :metis)))
        (prin1 header out)
        (terpri out)))
    p))

(defun %seal-canonical-message (header-hash body-hash)
  (format nil "metis-seal-v1~%~A~%~A~%" header-hash body-hash))

(defun symbol-seal-sign! (dir &key (key-id "metis-dev"))
  "Write symbol.sig over header+body digests using trust key KEY-ID."
  (metis.symbols:ensure-default-trust-key!)
  (let* ((dir (uiop:ensure-directory-pathname dir))
         (hpath (merge-pathnames "header.lisp" dir))
         (bpath (merge-pathnames "body.mse" dir))
         (secret (or (cdr (assoc key-id metis.symbols::*symbol-trust-keys*
                                 :test #'string=))
                     (error "unknown trust key-id ~A" key-id)))
         (hh (%seal-sha256-file hpath))
         (bh (%seal-sha256-file bpath))
         (msg (%seal-canonical-message hh bh))
         (sig (%seal-hmac-hex secret msg))
         (sigpath (merge-pathnames "symbol.sig" dir)))
    (with-open-file (out sigpath :direction :output :if-exists :supersede
                         :if-does-not-exist :create)
      (format out "metis-seal-sig-v1~%")
      (format out "~A~%" key-id)
      (format out "~A~%" sig)
      (format out "~A~%" hh)
      (format out "~A~%" bh))
    (list :signed t :key-id key-id :header-sha256 hh :body-sha256 bh
          :sigpath (namestring sigpath))))

(defun symbol-seal-verify (dir &key (require t) (key nil))
  "Verify sealed package integrity+authenticity.
   Returns plist (:ok t ...) or errors if REQUIRE.
   KEY is private passphrase for private-sealed decrypt probe (optional here)."
  (declare (ignore key))
  (let* ((dir (uiop:ensure-directory-pathname dir))
         (hpath (merge-pathnames "header.lisp" dir))
         (bpath (merge-pathnames "body.mse" dir))
         (sigpath (merge-pathnames "symbol.sig" dir)))
    (unless (and (probe-file hpath) (probe-file bpath))
      (if require
          (error "not a sealed symbol package: ~A" dir)
          (return-from symbol-seal-verify (list :ok nil :reason :missing-files))))
    (let ((header (symbol-seal-read-header dir)))
      (unless (symbol-seal-header-validate header)
        (if require
            (error "invalid seal header in ~A" dir)
            (return-from symbol-seal-verify (list :ok nil :reason :bad-header))))
      (let* ((hh (%seal-sha256-file hpath))
             (bh (%seal-sha256-file bpath))
             (declared-body (getf header :body-sha256)))
        (when (and declared-body (not (equal declared-body bh)))
          (if require
              (error "body hash mismatch (header declares ~A, file is ~A)"
                     declared-body bh)
              (return-from symbol-seal-verify
                (list :ok nil :reason :body-hash-mismatch
                      :declared declared-body :actual bh))))
        (unless (probe-file sigpath)
          (if require
              (error "sealed symbol unsigned: missing symbol.sig in ~A" dir)
              (return-from symbol-seal-verify
                (list :ok nil :reason :unsigned))))
        (metis.symbols:ensure-default-trust-key!)
        (multiple-value-bind (magic key-id claimed-sig claimed-hh claimed-bh)
            (with-open-file (in sigpath)
              (values (read-line in nil nil)
                      (string-trim '(#\Space #\Return) (or (read-line in nil "") ""))
                      (string-downcase (string-trim '(#\Space #\Return)
                                                    (or (read-line in nil "") "")))
                      (string-downcase (string-trim '(#\Space #\Return)
                                                    (or (read-line in nil "") "")))
                      (string-downcase (string-trim '(#\Space #\Return)
                                                    (or (read-line in nil "") "")))))
          (unless (equal magic "metis-seal-sig-v1")
            (if require
                (error "bad seal signature magic")
                (return-from symbol-seal-verify
                  (list :ok nil :reason :bad-magic))))
          (when (and (plusp (length claimed-hh)) (not (equal claimed-hh hh)))
            (if require
                (error "header tamper: signature header-hash mismatch")
                (return-from symbol-seal-verify
                  (list :ok nil :reason :header-tamper))))
          (when (and (plusp (length claimed-bh)) (not (equal claimed-bh bh)))
            (if require
                (error "body tamper: signature body-hash mismatch")
                (return-from symbol-seal-verify
                  (list :ok nil :reason :body-tamper))))
          (let* ((secret (cdr (assoc key-id metis.symbols::*symbol-trust-keys*
                                     :test #'string=)))
                 (expect (and secret
                              (%seal-hmac-hex secret
                                              (%seal-canonical-message hh bh)))))
            (cond
              ((null secret)
               (if require
                   (error "seal key-id ~A not in trust store" key-id)
                   (list :ok nil :reason :unknown-key :key-id key-id)))
              ((not (equal claimed-sig expect))
               (if require
                   (error "seal signature mismatch for ~A" dir)
                   (list :ok nil :reason :sig-mismatch :key-id key-id)))
              (t
               (list :ok t
                     :id (getf header :id)
                     :version (getf header :version)
                     :mode (getf header :mode)
                     :trust-tier (getf header :trust-tier)
                     :key-id key-id
                     :header-sha256 hh
                     :body-sha256 bh)))))))))

(defun symbol-seal!
    (source-or-plist
     dest
     &key (mode :open-sealed)
          (key nil)
          (key-id "metis-dev")
          (trust-tier :community)
          (sign t))
  "Build a sealed symbol package at DEST from a source kit directory OR a body plist.
   SOURCE-OR-PLIST:
     - pathname/string → source kit (source-manifest + facts/rules/corpus)
     - plist with :facts :rules :corpus :id …
   MODE :open-sealed (reproducible open key) or :private-sealed (requires KEY).
   KEY = passphrase for private-sealed (required) or override for open.
   Returns status plist."
  (when (and (eq mode :private-sealed) (or (null key) (zerop (length (string key)))))
    (error "private-sealed requires :key passphrase"))
  (let* ((dest (uiop:ensure-directory-pathname dest))
         (src (cond
                ((or (pathnamep source-or-plist) (stringp source-or-plist))
                 (symbol-source-kit-read source-or-plist))
                ((consp source-or-plist) source-or-plist)
                (t (error "symbol-seal! bad source"))))
         (id (or (getf src :id) "unnamed"))
         (version (or (getf src :version) "1.0.0"))
         (pass (or key
                   (when (eq mode :open-sealed)
                     (%seal-open-key id version))))
         (body-str (%seal-body-sexp
                    :facts (getf src :facts)
                    :rules (getf src :rules)
                    :corpus (getf src :corpus)
                    :capabilities (getf src :capabilities)
                    :meta (list :id id :version version)))
         (bpath (merge-pathnames "body.mse" dest))
         ;; open-sealed: fixed salt → same kit/plist always same body-sha256
         (salt (when (eq mode :open-sealed)
                 (%seal-open-salt-hex id version))))
    (ensure-directories-exist dest)
    (%seal-aes-encrypt body-str pass :out-path bpath :salt-hex salt)
    (let* ((bh (%seal-sha256-file bpath))
           (header (make-symbol-seal-header
                    :id id
                    :name (or (getf src :name) id)
                    :version version
                    :description (or (getf src :description) "")
                    :license (or (getf src :license) "MIT")
                    :mode mode
                    :trust-tier trust-tier
                    :depends-on (getf src :depends-on)
                    :capabilities (getf src :capabilities)
                    :bibliography (or (getf src :bibliography)
                                      (getf src :sources))
                    :body-sha256 bh
                    :extra (list :category (getf src :category)
                                 :facets (or (getf src :facets)
                                             (symbol-default-facets-for-caps
                                              (getf src :capabilities)))
                                 :sideload (eq trust-tier :unvetted)))))
      (symbol-seal-write-header! dest header)
      (let ((hh (%seal-sha256-file (merge-pathnames "header.lisp" dest))))
        (setf (getf header :package-sha256)
              (%seal-sha256-string (format nil "~A~A" hh bh)))
        (symbol-seal-write-header! dest header))
      (let ((sig (when sign (symbol-seal-sign! dest :key-id key-id))))
        ;; refuse casual plaintext leakage of body as .lisp
        (list :sealed t
              :id id
              :version version
              :mode mode
              :trust-tier trust-tier
              :path (namestring dest)
              :body-sha256 bh
              :signature sig
              :opaque t)))))

(defun %seal-resolve-passphrase (header &key key)
  (let ((mode (getf header :mode)))
    (cond
      ((member mode '(:private-sealed "private-sealed") :test #'equal)
       (or key (error "private-sealed symbol requires :key to load")))
      (t
       (or key (%seal-open-key (getf header :id) (getf header :version)))))))

(defun symbol-seal-decrypt-body (dir &key (key nil) (verify t))
  "Decrypt sealed body → body plist. Verifies signature first when VERIFY."
  (when verify
    (let ((v (symbol-seal-verify dir :require t)))
      (unless (getf v :ok) (error "seal verify failed: ~A" v))))
  (let* ((header (symbol-seal-read-header dir))
         (pass (%seal-resolve-passphrase header :key key))
         (mode (getf header :mode))
         (salt (unless (%seal-mode-private-p mode)
                 (%seal-open-salt-hex (getf header :id)
                                      (getf header :version))))
         (bpath (merge-pathnames "body.mse"
                                 (uiop:ensure-directory-pathname dir)))
         (plain (handler-case
                    (%seal-aes-decrypt-file bpath pass :salt-hex salt)
                  (error (e)
                    (error "refusing load: decrypt failed (~A)" e)))))
    (%seal-parse-body-sexp plain)))

(defun %seal-mode-private-p (mode)
  (member mode '(:private-sealed "private-sealed") :test #'equal))

(defun %seal-required-deps (header)
  "List of required dependency plists from HEADER."
  (remove-if-not
   (lambda (d)
     (let ((role (or (getf d :role) :required)))
       (member role '(:required "required" :require "require") :test #'equal)))
   (or (getf header :depends-on) nil)))

(defun %seal-dep-loaded-p (dep-id)
  (let ((id (string dep-id)))
    (or (and (boundp '*symbol-pack-enabled*)
             (gethash id *symbol-pack-enabled*))
        (and (boundp '*symbol-pack-overlays*)
             (find id *symbol-pack-overlays*
                   :key (lambda (x) (getf x :id)) :test #'string-equal))
        (and (fboundp '%pack-layer-get) (%pack-layer-get id)))))

;;; ---- dependency pins (refcount) ----------------------------------
;;; When A requires B, A holds a pin on B. Unloading A releases pins.
;;; B is auto-unloaded only if: no remaining pins AND B was auto-loaded
;;; as a dependency (not explicitly user-loaded).

(defparameter *symbol-dep-pins* (make-hash-table :test #'equal)
  "dep-id → list of holder symbol ids that currently require it.")

(defparameter *symbol-required-deps* (make-hash-table :test #'equal)
  "holder-id → list of required dep ids.")

(defparameter *symbol-auto-loaded* (make-hash-table :test #'equal)
  "id → T if this symbol was loaded only as a dependency (eligible for cascade unload).")

(defun symbol-dep-pin! (holder dep-id)
  "Record that HOLDER requires DEP-ID (refcount +1 style via membership)."
  (let* ((h (string holder))
         (d (string dep-id))
         (holders (gethash d *symbol-dep-pins*)))
    (unless (member h holders :test #'string-equal)
      (setf (gethash d *symbol-dep-pins*) (cons h holders)))
    t))

(defun symbol-dep-unpin! (holder dep-id)
  "Release HOLDER's pin on DEP-ID. Returns remaining holder count."
  (let* ((h (string holder))
         (d (string dep-id))
         (rest (remove h (gethash d *symbol-dep-pins*) :test #'string-equal)))
    (if rest
        (setf (gethash d *symbol-dep-pins*) rest)
        (remhash d *symbol-dep-pins*))
    (length rest)))

(defun symbol-dep-holders (dep-id)
  (copy-list (gethash (string dep-id) *symbol-dep-pins*)))

(defun symbol-mark-auto-loaded! (id)
  (setf (gethash (string id) *symbol-auto-loaded*) t))

(defun symbol-mark-explicit-loaded! (id)
  "User/explicit load — not cascade-unloaded when last pin drops."
  (remhash (string id) *symbol-auto-loaded*))

(defun symbol-auto-loaded-p (id)
  (gethash (string id) *symbol-auto-loaded*))

(defun symbol-record-required-deps! (holder dep-ids)
  (setf (gethash (string holder) *symbol-required-deps*)
        (mapcar #'string dep-ids)))

(defun symbol-required-deps-of (holder)
  (copy-list (gethash (string holder) *symbol-required-deps*)))

(defun symbol-clear-dep-state! (id)
  (remhash (string id) *symbol-required-deps*)
  (remhash (string id) *symbol-auto-loaded*)
  ;; remove id as a holder from all pin lists
  (maphash (lambda (dep holders)
             (let ((rest (remove (string id) holders :test #'string-equal)))
               (if rest
                   (setf (gethash dep *symbol-dep-pins*) rest)
                   (remhash dep *symbol-dep-pins*))))
           *symbol-dep-pins*)
  t)

(defun symbol-seal-ensure-deps! (header &key (mind nil) (auto t) (holder nil))
  "Ensure required :depends-on are loaded. AUTO tries knowledge/sealed/<id>/.
   HOLDER (usually the loading symbol id) pins each dep so unload is refcounted.
   Signals error with a clear missing list if unsatisfied."
  (let ((missing nil)
        (loaded nil)
        (m (or mind *mind*))
        (holder (and holder (string holder))))
    (dolist (d (%seal-required-deps header))
      (let ((dep-id (string (or (getf d :id) (getf d :name) ""))))
        (when (plusp (length dep-id))
          (cond
            ((%seal-dep-loaded-p dep-id)
             (push dep-id loaded)
             (when holder (symbol-dep-pin! holder dep-id)))
            (auto
             (let ((seed (merge-pathnames (format nil "~A/" dep-id)
                                          (symbol-sealed-root))))
               (if (and (probe-file (merge-pathnames "header.lisp" seed))
                        (probe-file (merge-pathnames "body.mse" seed)))
                   (progn
                     ;; recursive load as auto-dep: temporary overlay so cascade
                     ;; unload does not leave permanent registry pollution, and
                     ;; as-dependency marks cascade eligibility.
                     (symbol-seal-load! seed :mind m :verify t
                                        :as-dependency t
                                        :temporary t)
                     (push dep-id loaded)
                     (when holder (symbol-dep-pin! holder dep-id)))
                   (push dep-id missing))))
            (t (push dep-id missing))))))
    (when missing
      (error "symbol ~A requires deps not loaded: ~{~A~^, ~} (load those sealed packages first or place them under knowledge/sealed/)"
             (or holder (getf header :id)) (nreverse missing)))
    (when holder
      (symbol-record-required-deps! holder (nreverse (copy-list loaded))))
    (list :ok t :loaded (nreverse loaded))))

(defun symbol-seal-load!
    (dir &key (mind nil) (key nil) (verify t) (temporary nil)
              (trust-tier-override nil)
              (auto-deps t)
              (as-dependency nil))
  "Verify, decrypt, inject sealed knowledge into MIND via pack layers.
   Refuses on bad signature, hash mismatch, or decrypt failure.
   private-sealed ALWAYS loads as a temporary overlay — never writes a
   permanent plaintext pack.lisp/corpus.txt into the registry.
   Required :depends-on are auto-loaded from knowledge/sealed/ when AUTO-DEPS.
   AS-DEPENDENCY T marks this load as auto-dep (cascade-unload only if unpinned)."
  (let* ((m (or mind *mind* (boot)))
         (dir (uiop:ensure-directory-pathname dir))
         (v (when verify (symbol-seal-verify dir :require t)))
         (header (symbol-seal-read-header dir))
         (mode (getf header :mode))
         (private-p (%seal-mode-private-p mode))
         ;; private-sealed: never permanent-install decrypted body
         (temporary (or temporary private-p))
         (body (symbol-seal-decrypt-body dir :key key :verify nil))
         (id (getf header :id))
         (facts (getf body :facts))
         (rules (getf body :rules))
         (caps (or (getf body :capabilities) (getf header :capabilities)))
         (tier (or trust-tier-override
                   (if private-p :unvetted
                       (getf header :trust-tier))
                   :community)))
    (when auto-deps
      (symbol-seal-ensure-deps! header :mind m :auto t :holder id))
    (if as-dependency
        (symbol-mark-auto-loaded! id)
        (symbol-mark-explicit-loaded! id))
    (let* ((mkt (symbol-marketplace-check id
                                          :version (getf header :version)
                                          :body-sha256 (getf v :body-sha256)))
           (tmp (merge-pathnames
                 (format nil "seal-load-~A-~A/"
                         id (get-internal-real-time))
                 (uiop:temporary-directory))))
      (unwind-protect
           (progn
             (ensure-directories-exist tmp)
             ;; restrict temp tree as much as portable CL allows
             (ignore-errors
               (uiop:run-program
                (list "chmod" "700" (namestring tmp))
                :ignore-error-status t))
             (symbol-pack-write!
              tmp
              (make-symbol-pack-manifest
               :id id
               :name (getf header :name)
               :version (getf header :version)
               :description (getf header :description)
               :license (getf header :license)
               :sources (getf header :bibliography)
               :weights-policy :included
               :extra (list :category (getf header :category)
                            :capabilities caps
                            :facets (or (getf header :facets)
                                        (symbol-default-facets-for-caps caps))
                            :trust-tier tier
                            :sealed t
                            :mode mode
                            :depends-on (getf header :depends-on)))
              :facts facts
              :rules rules
              ;; private: do not leave corpus on disk longer than this tmp tree
              :corpus (unless private-p (getf body :corpus)))
             (when private-p
               ;; still inject corpus into mind via facts only; no corpus file needed
               nil)
             (let ((stats
                    (if temporary
                        (symbol-pack-install! tmp :id id :temporary t :mind m)
                        (progn
                          (symbol-pack-install! tmp :id id :mind m)
                          (symbol-pack-enable! id :mind m)))))
               (dolist (c caps)
                 (when (fboundp 'symbol-capability-register!)
                   (symbol-capability-register! c id)))
               ;; Temporary seal loads also attach model-package conditioning
               (when (and temporary (fboundp 'symbol-model-on-enable!))
                 (ignore-errors
                   (symbol-model-on-enable!
                    id
                    (list :id id
                          :capabilities caps
                          :model-package (getf header :model-package)
                          :weights-policy (getf header :weights-policy)
                          :facets (getf header :facets)))))
               (list :loaded t
                     :id id
                     :version (getf header :version)
                     :trust-tier tier
                     :mode mode
                     :temporary (and temporary t)
                     :private private-p
                     :verify v
                     :marketplace mkt
                     :stats stats
                     :facts (length facts)
                     :rules (length rules)
                     :as-dependency (and as-dependency t)
                     :deps (symbol-required-deps-of id))))
        ;; always wipe plaintext material
        (ignore-errors (uiop:delete-directory-tree
                        tmp :validate t :if-does-not-exist :ignore))))))

(defun %symbol-unload-core! (id &key (mind nil))
  "Disable/overlay-unload ID and drop caps/facets. No dep cascade."
  (let ((m (or mind *mind*))
        (id (string id))
        (action nil))
    (cond
      ((find id *symbol-pack-overlays*
             :key (lambda (x) (getf x :id)) :test #'string-equal)
       (symbol-pack-overlay-unload! id :mind m)
       (setf action :unloaded))
      ((gethash id *symbol-pack-enabled*)
       (symbol-pack-disable! id :mind m)
       (setf action :disabled))
      (t
       (setf action :not-loaded)))
    (when (fboundp '%symbol-unregister-caps!)
      (%symbol-unregister-caps! id))
    (symbol-clear-dep-state! id)
    (list :id id :action action)))

(defun symbol-seal-unload!
    (id &key (mind nil) (cascade-unused-deps t))
  "Unload symbol ID. Releases dep pins. Cascades unload of auto-loaded deps
   only when no other loaded symbol still pins them.
   Never unloads a dep that is still required by another currently loaded symbol."
  (let* ((m (or mind *mind*))
         (id (string id))
         (deps (symbol-required-deps-of id))
         (core (%symbol-unload-core! id :mind m))
         (cascaded nil)
         (kept nil))
    (when cascade-unused-deps
      (dolist (d deps)
        (let ((remaining (length (symbol-dep-holders d))))
          ;; pins for this holder already cleared in symbol-clear-dep-state!
          (cond
            ((plusp remaining)
             (push (list :id d :kept t :holders (symbol-dep-holders d)) kept))
            ((and (symbol-auto-loaded-p d) (%seal-dep-loaded-p d))
             ;; still auto-loaded and unpinned → safe cascade
             (let ((r (symbol-seal-unload! d :mind m :cascade-unused-deps t)))
               (push (list :id d :cascaded t :result r) cascaded)))
            (t
             ;; unpinned but user/explicit load — keep
             (push (list :id d :kept t :reason :explicit-or-shared) kept))))))
    (list :unloaded t
          :id id
          :core core
          :cascaded (nreverse cascaded)
          :kept-deps (nreverse kept))))

;;; ---- marketplace fingerprint index -------------------------------

(defun symbol-marketplace-index-path ()
  (merge-pathnames "knowledge/marketplace/index.lisp"
                   (asdf:system-source-directory :metis)))

(defun symbol-marketplace-load-index! (&optional path)
  (let ((p (or path (symbol-marketplace-index-path))))
    (setf *symbol-marketplace-index* (make-hash-table :test #'equal))
    (when (probe-file p)
      (with-open-file (in p)
        (let* ((*package* (find-package :metis))
               (*read-eval* nil)
               (form (read in nil nil)))
          (when (and (consp form) (getf form :entries))
            (dolist (e (getf form :entries))
              (let ((id (string-downcase (or (getf e :id) ""))))
                (push e (gethash id *symbol-marketplace-index*))))))))
    *symbol-marketplace-index*))

(defun symbol-marketplace-register!
    (id &key version body-sha256 trust-tier mode path license)
  "Add/update a marketplace index entry (local open catalog)."
  (unless *symbol-marketplace-index*
    (symbol-marketplace-load-index!))
  (let* ((id (string-downcase (string id)))
         (rec (list :id id
                    :version version
                    :body-sha256 body-sha256
                    :trust-tier (or trust-tier :community)
                    :mode (or mode :open-sealed)
                    :path path
                    :license license))
         (cur (remove version (gethash id *symbol-marketplace-index*)
                      :key (lambda (x) (getf x :version))
                      :test #'string-equal)))
    (setf (gethash id *symbol-marketplace-index*) (cons rec cur))
    rec))

(defun symbol-marketplace-save-index! (&optional path)
  (unless *symbol-marketplace-index*
    (symbol-marketplace-load-index!))
  (let ((p (or path (symbol-marketplace-index-path)))
        (entries nil))
    (ensure-directories-exist p)
    (maphash (lambda (_ list)
               (dolist (e list) (push e entries)))
             *symbol-marketplace-index*)
    (with-open-file (out p :direction :output :if-exists :supersede
                         :if-does-not-exist :create)
      (let ((*print-pretty* t) (*package* (find-package :metis)))
        (prin1 (list :metis-marketplace 1
                     :payments nil
                     :entries (sort entries #'string-lessp
                                    :key (lambda (e) (getf e :id))))
               out)
        (terpri out)))
    p))

(defun %version<= (a b)
  "Crude dotted version compare; T if A <= B as strings of ints."
  (labels ((parts (s)
             (mapcar (lambda (x) (or (ignore-errors (parse-integer x :junk-allowed t)) 0))
                     (cl-ppcre:split "\\." (or s "0")))))
    (let ((pa (parts a)) (pb (parts b)))
      (loop for i from 0 below (max (length pa) (length pb))
            for xa = (or (nth i pa) 0)
            for xb = (or (nth i pb) 0)
            do (cond ((< xa xb) (return t))
                     ((> xa xb) (return nil)))
            finally (return t)))))

(defun symbol-marketplace-check (id &key version body-sha256)
  "Compare a package against marketplace index.
   Returns advisories: :unknown | :match | :hash-mismatch | :newer-available."
  (unless *symbol-marketplace-index*
    (ignore-errors (symbol-marketplace-load-index!)))
  (let* ((id (string-downcase (string id)))
         (entries (and *symbol-marketplace-index*
                       (gethash id *symbol-marketplace-index*))))
    (if (null entries)
        (list :status :unknown
              :id id
              :note "not in marketplace index — treat as sideload/unvetted if not core")
        (let* ((same-ver (find version entries
                               :key (lambda (e) (getf e :version))
                               :test #'string-equal))
               (newest (first (sort (copy-list entries) #'string>
                                    :key (lambda (e) (getf e :version)))))
               (hash-ok (and same-ver body-sha256
                             (equal body-sha256 (getf same-ver :body-sha256)))))
          (list :status
                (cond
                  ((and same-ver body-sha256
                        (not (equal body-sha256 (getf same-ver :body-sha256))))
                   :hash-mismatch)
                  ((and newest version
                        (not (string-equal version (getf newest :version)))
                        (%version<= version (getf newest :version))
                        (not (string-equal version (getf newest :version))))
                   :newer-available)
                  (hash-ok :match)
                  (same-ver :version-known)
                  (t :id-known))
                :id id
                :version version
                :expected-hash (and same-ver (getf same-ver :body-sha256))
                :actual-hash body-sha256
                :newest (and newest (getf newest :version))
                :trust-tier (and same-ver (getf same-ver :trust-tier))
                :entries entries)))))

;;; ---- plaintext leakage probe (for tests / opacity claim) ---------

(defun symbol-seal-body-opaque-p (dir &key (needles nil))
  "T if body.mse does not contain obvious plaintext NEEDLES (default sample words)."
  (let* ((bpath (merge-pathnames "body.mse"
                                 (uiop:ensure-directory-pathname dir)))
         (needles (or needles
                      '("metis-seal-body" "corpus" "capability"
                        "integral" "derivative" "triangle"))))
    (unless (probe-file bpath) (return-from symbol-seal-body-opaque-p nil))
    (with-open-file (in bpath :element-type '(unsigned-byte 8))
      (let* ((n (file-length in))
             (buf (make-array n :element-type '(unsigned-byte 8))))
        (read-sequence buf in)
        (let ((s (map 'string #'code-char buf)))
          (notany (lambda (needle) (search needle s :test #'char-equal))
                  needles))))))
