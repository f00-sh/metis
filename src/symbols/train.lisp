;;;; train.lisp — source kits + train/build path for sealed symbols
;;;; Authors work in a readable source kit; build emits sealed packages only.
(in-package :metis)

(defun symbol-source-kit-root ()
  "Default root for author source kits (readable; not shipped form)."
  (merge-pathnames "knowledge/source-kits/"
                   (asdf:system-source-directory :metis)))

(defun symbol-sealed-root ()
  "Default root for sealed shipped packages."
  (merge-pathnames "knowledge/sealed/"
                   (asdf:system-source-directory :metis)))

(defun make-symbol-source-manifest
    (&key (id "unnamed")
          (name id)
          (version "1.0.0")
          (description "")
          (license "MIT")
          (category :science)
          (depends-on nil)
          (capabilities nil)
          (bibliography nil)
          (extra nil))
  (append
   (list :metis-source-kit 1
         :id id
         :name name
         :version version
         :description description
         :license license
         :category category
         :depends-on (or depends-on nil)
         :capabilities (or capabilities nil)
         :bibliography (or bibliography nil)
         :created (multiple-value-bind (s m h d mo y) (get-decoded-time)
                    (declare (ignore s m h))
                    (format nil "~4,'0D-~2,'0D-~2,'0D" y mo d)))
   extra))

(defun symbol-source-kit-new!
    (id &key (root nil)
             (name nil)
             (version "1.0.0")
             (description "")
             (license "CC-BY-4.0")
             (category :science)
             (depends-on nil)
             (capabilities nil)
             (bibliography nil))
  "Create a new source kit directory skeleton for ID."
  (let* ((root (or root (symbol-source-kit-root)))
         (dir (merge-pathnames (format nil "~A/" id)
                               (uiop:ensure-directory-pathname root)))
         (man (make-symbol-source-manifest
               :id id :name (or name id) :version version
               :description description :license license
               :category category :depends-on depends-on
               :capabilities capabilities
               :bibliography bibliography)))
    (ensure-directories-exist (merge-pathnames "corpus/" dir))
    (ensure-directories-exist (merge-pathnames "sources/" dir))
    (with-open-file (out (merge-pathnames "source-manifest.lisp" dir)
                         :direction :output :if-exists :supersede
                         :if-does-not-exist :create)
      (let ((*print-pretty* t) (*package* (find-package :metis)))
        (prin1 man out) (terpri out)))
    (with-open-file (out (merge-pathnames "bibliography.lisp" dir)
                         :direction :output :if-exists :supersede
                         :if-does-not-exist :create)
      (let ((*print-pretty* t) (*package* (find-package :metis)))
        (prin1 (list :bibliography 1
                     :entries (or bibliography nil))
               out)
        (terpri out)))
    (with-open-file (out (merge-pathnames "facts.lisp" dir)
                         :direction :output :if-exists :supersede
                         :if-does-not-exist :create)
      (let ((*print-pretty* t) (*package* (find-package :keyword)))
        (prin1 (list :facts nil) out) (terpri out)))
    (with-open-file (out (merge-pathnames "rules.lisp" dir)
                         :direction :output :if-exists :supersede
                         :if-does-not-exist :create)
      (let ((*print-pretty* t) (*package* (find-package :keyword)))
        (prin1 (list :rules nil) out) (terpri out)))
    (with-open-file (out (merge-pathnames "corpus/README.txt" dir)
                         :direction :output :if-exists :supersede
                         :if-does-not-exist :create)
      (format out "Drop license-clear training text here (.txt).~%"))
    (list :created t :id id :path (namestring dir))))

(defun %read-lisp-file (path)
  (when (probe-file path)
    (with-open-file (in path)
      (let ((*package* (find-package :metis))
            (*read-eval* nil))
        (read in nil nil)))))

(defun %kit-read-corpus (dir)
  (let ((corp-dir (merge-pathnames "corpus/"
                                   (uiop:ensure-directory-pathname dir)))
        (lines nil))
    (when (probe-file corp-dir)
      (dolist (p (directory (merge-pathnames "*.txt" corp-dir)))
        (unless (string-equal (pathname-name p) "README")
          (with-open-file (in p)
            (loop for line = (read-line in nil nil)
                  while line
                  when (plusp (length (string-trim '(#\Space #\Tab) line)))
                    do (push line lines))))))
    (nreverse lines)))

(defun symbol-source-kit-read (dir)
  "Read a source kit into a unified plist for train/seal."
  (let* ((dir (uiop:ensure-directory-pathname dir))
         (man (or (%read-lisp-file (merge-pathnames "source-manifest.lisp" dir))
                  (error "no source-manifest.lisp in ~A" dir)))
         (bib-file (%read-lisp-file (merge-pathnames "bibliography.lisp" dir)))
         (facts-form (%read-lisp-file (merge-pathnames "facts.lisp" dir)))
         (rules-form (%read-lisp-file (merge-pathnames "rules.lisp" dir)))
         (facts (cond
                  ((and (consp facts-form) (getf facts-form :facts))
                   (getf facts-form :facts))
                  ((and (consp facts-form) (eq (first facts-form) :facts))
                   (rest facts-form))
                  (t nil)))
         (rules (cond
                  ((and (consp rules-form) (getf rules-form :rules))
                   (getf rules-form :rules))
                  (t nil)))
         (bib (or (getf man :bibliography)
                  (and bib-file (getf bib-file :entries))
                  nil))
         (corpus (%kit-read-corpus dir)))
    (list :id (getf man :id)
          :name (getf man :name)
          :version (getf man :version)
          :description (getf man :description)
          :license (getf man :license)
          :category (getf man :category)
          :depends-on (getf man :depends-on)
          :capabilities (getf man :capabilities)
          :bibliography bib
          :facts facts
          :rules rules
          :corpus corpus
          :path (namestring dir))))

(defun symbol-source-kit-ingest! (dir paths)
  "Copy text files into kit corpus/. PATHS = list of pathnames/strings.
   Large books are fine — each file is kept whole under corpus/."
  (let* ((dir (uiop:ensure-directory-pathname dir))
         (corp (merge-pathnames "corpus/" dir))
         (copied nil)
         (bytes 0))
    (ensure-directories-exist corp)
    (dolist (p paths)
      (let* ((from (pathname p))
             (to (merge-pathnames (file-namestring from) corp)))
        (when (probe-file from)
          (uiop:copy-file from to)
          (incf bytes (or (ignore-errors (with-open-file (in to) (file-length in))) 0))
          (push (namestring to) copied))))
    (list :ingested (length copied) :files (nreverse copied) :bytes bytes)))

(defun symbol-source-kit-ingest-book!
    (dir book-path &key (chunk-chars 12000) (name nil))
  "Ingest an ENTIRE book (plain text) into the kit as chunked corpus files.
   BOOK-PATH = .txt (preferred) or any text-like file. Chunks keep sequential order
   so retrieval can pull long-form content. Returns stats.

   This is the book-scale path: symbols are allowed to be large."
  (let* ((dir (uiop:ensure-directory-pathname dir))
         (corp (merge-pathnames "corpus/" dir))
         (book (pathname book-path))
         (base (or name (pathname-name book) "book"))
         (text (with-open-file (in book :direction :input
                                   :if-does-not-exist :error
                                   :external-format :utf-8)
                 (let ((s (make-string (file-length in))))
                   (read-sequence s in)
                   s)))
         (n (length text))
         (chunks 0)
         (files nil))
    (ensure-directories-exist corp)
    (when (zerop n) (error "empty book ~A" book))
    (loop for start from 0 below n by chunk-chars
          for i from 0
          for end = (min n (+ start chunk-chars))
          for path = (merge-pathnames
                      (format nil "~A-~4,'0D.txt" base i) corp)
          do (with-open-file (out path :direction :output
                                  :if-exists :supersede
                                  :if-does-not-exist :create
                                  :external-format :utf-8)
               (write-string (subseq text start end) out))
             (push (namestring path) files)
             (incf chunks))
    (list :book (namestring book)
          :chars n
          :chunks chunks
          :chunk-chars chunk-chars
          :files (nreverse files))))

(defun %train-extract-def-facts (corpus-lines domain-tag)
  "Lightweight extraction: lines 'TERM: definition' → (domain-def domain term def)."
  (let ((out nil))
    (dolist (line corpus-lines)
      (let ((pos (search ": " line)))
        (when (and pos (> pos 0) (< pos 80))
          (let ((term (string-trim '(#\Space #\Tab) (subseq line 0 pos)))
                (def (string-trim '(#\Space #\Tab) (subseq line (+ pos 2)))))
            (when (and (>= (length term) 2) (>= (length def) 8)
                       (not (search "http" term :test #'char-equal)))
              (push (list 'domain-def domain-tag term def) out))))))
    (nreverse out)))

(defun symbol-train-from-kit!
    (dir &key (mind nil) (extract-defs t) (write-back t) (epochs 0))
  "Train/build knowledge from a source kit.
   - Merges facts/rules from kit files
   - Optionally extracts definition facts from corpus lines
   - Optionally runs a few pure-CL LM epochs on corpus when EPOCHS > 0 and an LM exists
   - Writes trained-facts.lisp snapshot when WRITE-BACK
   Returns trained plist ready for symbol-seal!."
  (let* ((m (or mind *mind*))
         (kit (symbol-source-kit-read dir))
         (id (getf kit :id))
         (facts (copy-list (getf kit :facts)))
         (rules (copy-list (getf kit :rules)))
         (corpus (getf kit :corpus))
         (extracted 0))
    (when extract-defs
      (let ((xs (%train-extract-def-facts corpus id)))
        (setf extracted (length xs)
              facts (append facts xs))))
    ;; Stable train marker only (no wall-clock) so open-sealed fingerprints
    ;; are reproducible from the same kit.
    (push (list 'symbol-trained id (getf kit :version)
                extracted (length corpus))
          facts)
    (when (and m (plusp epochs) corpus
               (fboundp 'nn-continuous-train))
      (ignore-errors
        (let ((text (format nil "~{~A~%~}" corpus)))
          (nn-continuous-train m text :epochs epochs))))
    (when write-back
      (let ((outp (merge-pathnames "trained-facts.lisp"
                                   (uiop:ensure-directory-pathname dir))))
        (with-open-file (out outp :direction :output :if-exists :supersede
                             :if-does-not-exist :create)
          (let ((*print-pretty* t) (*package* (find-package :keyword)))
            (prin1 (list :facts facts :rules rules
                         :extracted extracted
                         :corpus-lines (length corpus))
                   out)
            (terpri out)))))
    (list :id id
          :name (getf kit :name)
          :version (getf kit :version)
          :description (getf kit :description)
          :license (getf kit :license)
          :category (getf kit :category)
          :depends-on (getf kit :depends-on)
          :capabilities (getf kit :capabilities)
          :bibliography (getf kit :bibliography)
          :facts facts
          :rules rules
          :corpus corpus
          :extracted extracted
          :trained t
          :path (getf kit :path))))

(defun symbol-build!
    (kit-dir
     &key (dest nil)
          (mode :open-sealed)
          (key nil)
          (key-id "metis-dev")
          (trust-tier :community)
          (train t)
          (register-marketplace t))
  "Full path: (train) source kit → sealed package under knowledge/sealed/<id>/.
   Returns seal status."
  (let* ((trained (if train
                      (symbol-train-from-kit! kit-dir)
                      (symbol-source-kit-read kit-dir)))
         (id (getf trained :id))
         (dest (or dest
                   (merge-pathnames (format nil "~A/" id)
                                    (symbol-sealed-root))))
         (seal (symbol-seal! trained dest
                             :mode mode :key key :key-id key-id
                             :trust-tier trust-tier :sign t)))
    (when register-marketplace
      (symbol-marketplace-register!
       id
       :version (getf trained :version)
       :body-sha256 (getf seal :body-sha256)
       :trust-tier trust-tier
       :mode mode
       :path (getf seal :path)
       :license (getf trained :license))
      (ignore-errors (symbol-marketplace-save-index!)))
    (list* :built t :trained trained seal)))

;;; ---- CLI-ish entry for scripts -----------------------------------

(defun symbol-cli-train (kit-dir &rest args)
  (apply #'symbol-train-from-kit! kit-dir args))

(defun symbol-cli-build (kit-dir &rest args)
  (apply #'symbol-build! kit-dir args))

(defun symbol-cli-verify (sealed-dir)
  (symbol-seal-verify sealed-dir :require nil))

(defun symbol-cli-load (sealed-dir &rest args)
  (apply #'symbol-seal-load! sealed-dir args))
