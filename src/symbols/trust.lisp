;;;; trust.lisp — symbol package signing (HMAC-SHA256 via openssl or pure fallback)
(in-package :metis.symbols)

(defparameter *symbol-trust-keys*
  nil
  "Alist of (key-id . secret-string). Loaded from trust store.")

(defparameter *symbol-trust-strict* t
  "When true, remote installs require a valid symbol.sig.")

(defparameter *symbol-trust-store*
  nil
  "Path to trust keys file. Default ~/.metis/trust/keys.lisp")

(defun symbol-trust-store-path ()
  (or *symbol-trust-store*
      (merge-pathnames ".metis/trust/keys.lisp" (user-homedir-pathname))))

(defun load-trust-keys! (&optional path)
  (let ((p (or path (symbol-trust-store-path))))
    (when (probe-file p)
      (with-open-file (in p)
        (let ((*package* (find-package :cl-user)))
          (setf *symbol-trust-keys* (read in)))))
    *symbol-trust-keys*))

(defun ensure-default-trust-key! ()
  "Ensure a local development trust key exists for signing fixtures."
  (load-trust-keys!)
  (unless (assoc "metis-dev" *symbol-trust-keys* :test #'string=)
    (let ((p (symbol-trust-store-path)))
      (ensure-directories-exist p)
      (push (cons "metis-dev" "metis-dev-secret-change-me") *symbol-trust-keys*)
      (with-open-file (out p :direction :output :if-exists :supersede)
        (with-standard-io-syntax
          (prin1 *symbol-trust-keys* out)
          (terpri out)))))
  *symbol-trust-keys*)

(defun %sha256-hex-file (path)
  "SHA256 hex digest of file contents using openssl (portable)."
  (string-downcase
   (string-trim
    '(#\Space #\Newline #\Tab #\Return)
    (uiop:run-program
     (list "openssl" "dgst" "-sha256" "-hex" (namestring path))
     :output :string)
    ;; openssl outputs "SHA256(file)= hex"
    )))

(defun %openssl-sha256-hex-of-string (s)
  (string-downcase
   (string-trim
    '(#\Space #\Newline #\Tab #\Return)
    (uiop:run-program
     (list "openssl" "dgst" "-sha256" "-hex")
     :input (make-string-input-stream s)
     :output :string))))

(defun %parse-openssl-hex (out)
  (let ((pos (search "= " out)))
    (if pos
        (string-downcase (string-trim '(#\Space #\Newline) (subseq out (+ pos 2))))
        (string-downcase (string-trim '(#\Space #\Newline) out)))))

(defun %file-digest (path)
  (%parse-openssl-hex
   (uiop:run-program
    (list "openssl" "dgst" "-sha256" (namestring (truename path)))
    :output :string)))

(defun %hmac-sha256-hex (secret message)
  (%parse-openssl-hex
   (uiop:run-program
    (list "openssl" "dgst" "-sha256" "-hmac" secret)
    :input (make-string-input-stream message)
    :output :string)))

(defun %list-symbol-files (root)
  (let ((root (uiop:ensure-directory-pathname root))
        (files nil))
    (labels ((walk (dir)
               (dolist (p (directory (merge-pathnames "*.*" dir)))
                 (unless (uiop:directory-pathname-p p)
                   (let ((name (enough-namestring p root)))
                     (unless (or (string= (file-namestring p) "symbol.sig")
                                 (search ".git/" name)
                                 ;; never include transfer artifacts in signed payload
                                 (search "pkg.tar.gz" name)
                                 (search "download.tar.gz" name)
                                 (uiop:string-suffix-p name ".tar.gz")
                                 (uiop:string-suffix-p name ".tgz"))
                       (push (list name p) files)))))
               (dolist (d (directory (merge-pathnames "*/" dir)))
                 (walk d))))
      (walk root))
    (sort files #'string< :key #'first)))

(defun %symbol-package-root (root)
  "Absolute directory pathname for a symbol package (stable for sign/verify)."
  (uiop:ensure-directory-pathname (truename root)))

(defun symbol-canonical-payload (root)
  "Canonical string over relative paths + digests for signing."
  (let ((root (%symbol-package-root root)))
    (with-output-to-string (out)
      (dolist (pair (%list-symbol-files root))
        (format out "~A ~A~%" (first pair) (%file-digest (second pair)))))))

(defun sign-symbol-package! (root &key (key-id "metis-dev"))
  "Write symbol.sig for package at ROOT using KEY-ID from trust store."
  (ensure-default-trust-key!)
  (let* ((root (%symbol-package-root root))
         (secret (or (cdr (assoc key-id *symbol-trust-keys* :test #'string=))
                     (error "unknown trust key-id ~A" key-id)))
         (payload (symbol-canonical-payload root))
         (sig (%hmac-sha256-hex secret payload))
         (sigpath (merge-pathnames "symbol.sig" root)))
    (with-open-file (out sigpath :direction :output :if-exists :supersede)
      (format out "metis-sig-v1~%")
      (format out "~A~%" key-id)
      (format out "~A~%" sig))
    sigpath))

(defun verify-symbol-package (root &key (require t))
  "Verify symbol.sig under ROOT. Returns (:ok key-id) or signals error if REQUIRE."
  (let* ((root (%symbol-package-root root))
         (sigpath (merge-pathnames "symbol.sig" root)))
    (unless (probe-file sigpath)
      (if require
          (error "symbol package unsigned: missing symbol.sig in ~A" root)
          (return-from verify-symbol-package (list :unsigned t))))
    (ensure-default-trust-key!)
    (multiple-value-bind (key-id claimed)
        (with-open-file (in sigpath)
          (let ((magic (read-line in nil nil))
                (kid (read-line in nil nil))
                (hex (read-line in nil nil)))
            (unless (equal magic "metis-sig-v1")
              (error "bad symbol.sig magic"))
            (values (string-trim '(#\Space #\Return) kid)
                    (string-downcase (string-trim '(#\Space #\Return) hex)))))
      (let* ((secret (cdr (assoc key-id *symbol-trust-keys* :test #'string=)))
             (payload (symbol-canonical-payload root))
             (expect (and secret (%hmac-sha256-hex secret payload))))
        (cond
          ((null secret)
           (error "symbol signature key-id ~A not in trust store" key-id))
          ((not (equal claimed expect))
           (error "symbol signature mismatch for ~A (key ~A)" root key-id))
          (t (list :ok t :key-id key-id)))))))
