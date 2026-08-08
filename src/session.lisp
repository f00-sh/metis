;;;; session.lisp — multi-turn interactive session + attachments (files/context/photos)
(in-package :metis)

(defstruct (attachment (:conc-name att-))
  id
  kind          ; :file | :context | :photo
  path          ; filesystem path when applicable
  media-type
  size
  name
  (text nil)    ; extracted text body for readable files / context string
  (caption nil)
  (meta nil)
  (time 0))

(defstruct (session (:conc-name sess-))
  id
  mind
  (attachments (make-hash-table :test #'equal))
  (turns nil)           ; newest first: (:role :user|:assistant :text :result ...)
  (turn-count 0)
  (capabilities nil)    ; alist of known capability names
  (accommodations 0)
  (created 0)
  ;; Recursive: iface-turn holds lock while attach/train helpers also take it.
  (lock (bt:make-recursive-lock "metis-session")))

(defvar *session* nil)
(defvar *sessions* (make-hash-table :test #'equal))

(defparameter *text-extensions*
  '(".txt" ".md" ".lisp" ".asd" ".cl" ".el" ".py" ".js" ".ts" ".tsx" ".jsx"
    ".c" ".h" ".cc" ".cpp" ".hpp" ".rs" ".go" ".java" ".rb" ".php" ".sh"
    ".json" ".csv" ".tsv" ".log" ".org" ".html" ".htm" ".xml" ".yml" ".yaml"
    ".toml" ".ini" ".cfg" ".conf" ".sql" ".r" ".jl" ".scala" ".kt" ".swift"
    ".css" ".scss" ".less" ".vue" ".svelte" ".tex" ".rst" ".adoc"))

(defparameter *photo-extensions*
  '(".png" ".jpg" ".jpeg" ".gif" ".webp" ".bmp" ".tif" ".tiff"))

(defparameter *extract-max-chars* 200000
  "Max characters retained per file after extraction.")

(defparameter *session-ingest-train-defaults*
  (list :name "session-lm" :epochs 2 :hidden 64 :seq-len 64 :depth 2
        :max-batches 24 :lr 4d-3)
  "Defaults for continuous train after ingest/watch.")

(defparameter *session-hard-train-defaults*
  (list :name "session-lm" :epochs 6 :hidden 96 :seq-len 96 :depth 2
        :max-batches 64 :lr 3d-3)
  "Hard train when the user drops a file in chat (@path /attach /train).")

(defparameter *session-light-train-defaults*
  (list :name "session-lm" :epochs 1 :hidden 64 :seq-len 64 :depth 2
        :max-batches 8 :lr 5d-3)
  "Background consolidation ticks while idle.")

;;; ------------------------------------------------------------------
;;; Background brain — always training / watching, concurrent with chat
;;; ------------------------------------------------------------------

(defvar *brain-lock* (bt:make-lock "metis-brain"))
(defvar *brain-queue* nil
  "FIFO of train jobs: (:text :name :epochs :hidden :seq-len :depth
   :max-batches :lr :session-id :source :intensity)")
(defvar *brain-running* nil)
(defvar *brain-thread* nil)
(defvar *brain-interval* 0.35d0
  "Seconds between watch polls / queue checks.")
(defvar *brain-jobs-done* 0)
(defvar *brain-last-error* nil)
(defvar *brain-last-job* nil)
(defvar *brain-last-events* nil)
(defvar *brain-consolidate-every* 24
  "Idle cycles between corpus consolidation trains.")
(defvar *brain-cycle* 0)
(defvar *brain-auto-start* t
  "Start brain thread on first watch/attach/train.")

(defparameter *session-folder-watches* (make-hash-table :test #'equal)
  "session-id → (:path :seen hash :train :train-name :async :intensity)")

(defun %brain-train-params (intensity)
  (copy-list
   (ecase intensity
     ((:hard :chat) *session-hard-train-defaults*)
     ((:ingest :normal) *session-ingest-train-defaults*)
     ((:light :consolidate) *session-light-train-defaults*))))

(defun brain-enqueue-train! (text &key (name nil) (intensity :hard)
                                    (session nil) (source :chat)
                                    (epochs nil) (hidden nil) (seq-len nil)
                                    (depth nil) (max-batches nil) (lr nil))
  "Queue real continuous train (not context-only). Returns job summary.
   Does not block the caller — the brain thread runs nn-continuous-train."
  (let* ((text (string-trim '(#\Space #\Newline #\Tab) (or text "")))
         (d (%brain-train-params intensity))
         (job (list :text text
                    :name (or name (getf d :name))
                    :epochs (or epochs (getf d :epochs))
                    :hidden (or hidden (getf d :hidden))
                    :seq-len (or seq-len (getf d :seq-len))
                    :depth (or depth (getf d :depth))
                    :max-batches (or max-batches (getf d :max-batches))
                    :lr (or lr (getf d :lr))
                    :session-id (and session (sess-id session))
                    :source source
                    :intensity intensity
                    :chars (length text)
                    :queued-at (now-universal))))
    (when (< (length text) 8)
      (return-from brain-enqueue-train!
        (list :queued nil :reason "text too short")))
    (bt:with-lock-held (*brain-lock*)
      (setf *brain-queue* (nconc *brain-queue* (list job))))
    (when *brain-auto-start*
      (brain-start!))
    (list :queued t
          :name (getf job :name)
          :intensity intensity
          :chars (getf job :chars)
          :source source
          :queue-depth (brain-queue-depth))))

(defun brain-queue-depth ()
  (bt:with-lock-held (*brain-lock*)
    (length *brain-queue*)))

(defun %brain-pop-job ()
  (bt:with-lock-held (*brain-lock*)
    (let ((j (pop *brain-queue*)))
      j)))

(defun %brain-run-job (job)
  "Execute one continuous-train job (real weight updates)."
  (setf *brain-last-job* (list :name (getf job :name)
                               :source (getf job :source)
                               :intensity (getf job :intensity)
                               :chars (getf job :chars)
                               :started (now-universal)))
  (let* ((sid (getf job :session-id))
         (sess (and sid (session-get sid)))
         (mind (or (and sess (sess-mind sess)) *mind*)))
    (when (and mind
               (fboundp 'nn-path-allowed-p)
               (not (nn-path-allowed-p mind)))
      (ignore-errors (nn-enable-path mind)))
    (let ((r (nn-continuous-train (getf job :text)
                                  :name (getf job :name)
                                  :epochs (getf job :epochs)
                                  :hidden (getf job :hidden)
                                  :seq-len (getf job :seq-len)
                                  :depth (getf job :depth)
                                  :max-batches (getf job :max-batches)
                                  :lr (getf job :lr))))
      (incf *brain-jobs-done*)
      (setf *brain-last-job*
            (list* :done t :finished (now-universal)
                   :history (getf r :history)
                   *brain-last-job*))
      (when (and mind (fboundp 'assert-fact))
        (ignore-errors
          (assert-fact mind
                       (list 'brain-trained
                             (getf job :name)
                             (getf job :source)
                             (getf job :chars))
                       :support :nn :forward nil)))
      r)))

(defun %brain-consolidate-tick ()
  "Light continuous train on a live session corpus — keeps learning when idle."
  (let ((sess (or *session*
                  (let ((found nil))
                    (maphash (lambda (_ s)
                               (declare (ignore _))
                               (when (and (null found) s)
                                 (setf found s)))
                             *sessions*)
                    found))))
    (when sess
      (let ((corpus (ignore-errors (session-corpus sess))))
        (when (and corpus (>= (length corpus) 32))
          (let* ((cap 12000)
                 (slice (if (<= (length corpus) cap)
                            corpus
                            (subseq corpus
                                    (max 0 (- (length corpus) cap))))))
            (%brain-run-job
             (list* :text slice
                    :source :consolidate
                    :intensity :light
                    :session-id (sess-id sess)
                    :chars (length slice)
                    (%brain-train-params :light)))))))))

(defun %brain-loop ()
  (metis-log :info "brain started (watch+train background)")
  (loop while *brain-running*
        do (handler-case
               (progn
                 (incf *brain-cycle*)
                 ;; 1) folder drops → attach + enqueue/train immediately
                 (let ((ev (session-watch-poll!)))
                   (when ev
                     (setf *brain-last-events* ev)
                     (metis-log :info "brain watch: ~A new file(s)" (length ev))))
                 ;; 2) drain hard/ingest train queue (actual nn-continuous-train)
                 (loop for job = (%brain-pop-job)
                       while job
                       do (%brain-run-job job))
                 ;; 3) idle consolidation — always learning like a brain
                 (when (and (zerop (mod *brain-cycle* *brain-consolidate-every*))
                            (zerop (brain-queue-depth)))
                   (%brain-consolidate-tick))
                 (sleep *brain-interval*))
             (error (e)
               (setf *brain-last-error* (princ-to-string e))
               (metis-log :error "brain: ~A" e)
               (sleep 1.0))))
  (metis-log :info "brain stopped"))

(defun brain-start! (&key (interval nil))
  "Start background brain (folder watch + train queue + consolidation).
   Concurrent with the user — does not block iface turns."
  (when (and *brain-thread* (bt:thread-alive-p *brain-thread*))
    (return-from brain-start!
      (list :running t :already t :queue (brain-queue-depth))))
  (when interval (setf *brain-interval* interval))
  (setf *brain-running* t
        *brain-last-error* nil)
  (setf *brain-thread*
        (bt:make-thread #'%brain-loop :name "metis-brain"))
  (list :running t :interval *brain-interval* :queue (brain-queue-depth)))

(defun brain-stop! ()
  (setf *brain-running* nil)
  (when (and *brain-thread* (bt:thread-alive-p *brain-thread*))
    (ignore-errors (bt:join-thread *brain-thread*)))
  (setf *brain-thread* nil)
  (list :running nil :jobs-done *brain-jobs-done*))

(defun brain-status ()
  (list :running (and *brain-running*
                      *brain-thread*
                      (bt:thread-alive-p *brain-thread*))
        :queue (brain-queue-depth)
        :jobs-done *brain-jobs-done*
        :cycle *brain-cycle*
        :interval *brain-interval*
        :last-error *brain-last-error*
        :last-job *brain-last-job*
        :last-events *brain-last-events*
        :watches (hash-table-count *session-folder-watches*)))

(defun %with-session-lock (sess thunk)
  (bt:with-recursive-lock-held ((sess-lock sess))
    (funcall thunk)))

(defun %ext (path)
  (string-downcase (or (pathname-type path) "")))

(defun %media-type-for (path)
  (let ((e (%ext path)))
    (cond
      ((member e '("png") :test #'string=) "image/png")
      ((member e '("jpg" "jpeg") :test #'string=) "image/jpeg")
      ((member e '("gif") :test #'string=) "image/gif")
      ((member e '("webp") :test #'string=) "image/webp")
      ((member e '("pdf") :test #'string=) "application/pdf")
      ((member e '("xlsx" "xlsm") :test #'string=)
       "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet")
      ((member e '("xls") :test #'string=) "application/vnd.ms-excel")
      ((member e '("docx") :test #'string=)
       "application/vnd.openxmlformats-officedocument.wordprocessingml.document")
      ((member e '("txt" "md" "log" "csv" "tsv") :test #'string=) "text/plain")
      ((member e '("lisp" "asd" "cl") :test #'string=) "text/x-common-lisp")
      ((member e '("py") :test #'string=) "text/x-python")
      ((member e '("json") :test #'string=) "application/json")
      ((member e '("html" "htm") :test #'string=) "text/html")
      (t "application/octet-stream"))))

(defun %text-file-p (path)
  (member (concatenate 'string "." (%ext path))
          *text-extensions* :test #'string-equal))

(defun %photo-file-p (path)
  (member (concatenate 'string "." (%ext path))
          *photo-extensions* :test #'string-equal))

(defun %limit-text (s &optional (max *extract-max-chars*))
  (if (and s (> (length s) max))
      (subseq s 0 max)
      s))

(defun %read-text-limited (path &optional (max *extract-max-chars*))
  (%limit-text (uiop:read-file-string path) max))

(defun %run-capture (program args)
  "Run PROGRAM with ARGS; return stdout string or NIL on failure."
  (handler-case
      (string-trim
       '(#\Space #\Newline #\Tab #\Return)
       (uiop:run-program (cons program args)
                         :output :string
                         :error-output :string
                         :ignore-error-status t))
    (error () nil)))

(defun %extract-pdf-text (path)
  (or (let ((t1 (%run-capture "pdftotext" (list "-layout" "-q" (namestring path) "-"))))
        (when (and t1 (plusp (length t1))) t1))
      (let ((t2 (%run-capture "pdftotext" (list "-q" (namestring path) "-"))))
        (when (and t2 (plusp (length t2))) t2))))

(defun %metis-script (name)
  (merge-pathnames
   (format nil "scripts/~A" name)
   (asdf:system-source-directory :metis)))

(defun %extract-xlsx-text (path)
  "Extract cell text from .xlsx via scripts/extract_xlsx.py (stdlib only)."
  (let* ((script (%metis-script "extract_xlsx.py"))
         (txt (when (probe-file script)
                (%run-capture "python3" (list (namestring script)
                                              (namestring path))))))
    (when (and txt (plusp (length txt))) txt)))

(defun %extract-docx-text (path)
  "Extract plain text from .docx via scripts/extract_docx.py (stdlib only)."
  (let* ((script (%metis-script "extract_docx.py"))
         (txt (when (probe-file script)
                (%run-capture "python3" (list (namestring script)
                                              (namestring path))))))
    (when (and txt (plusp (length txt))) txt)))

(defun %looks-binary-p (path)
  "Heuristic: many NUL bytes in first 4k → binary."
  (handler-case
      (with-open-file (in path :element-type '(unsigned-byte 8)
                          :if-does-not-exist :error)
        (let* ((n (min 4096 (file-length in)))
               (buf (make-array n :element-type '(unsigned-byte 8)))
               (got (read-sequence buf in))
               (nuls 0))
          (dotimes (i got)
            (when (zerop (aref buf i)) (incf nuls)))
          (> nuls (/ got 50))))
    (error () t)))

(defun extract-text-from-path (path &key (max *extract-max-chars*))
  "Best-effort unstructured text extraction for arbitrary files.
   Returns (:text string :method keyword :media-type string) or NIL text."
  (let* ((p (pathname path))
         (pn (namestring (or (probe-file p) p)))
         (e (%ext pn))
         (mt (%media-type-for pn)))
    (cond
      ((not (probe-file pn))
       (list :text nil :method :missing :media-type mt))
      ((string= e "pdf")
       (list :text (%limit-text (%extract-pdf-text pn) max)
             :method :pdftotext :media-type mt))
      ((member e '("xlsx" "xlsm") :test #'string=)
       (list :text (%limit-text (%extract-xlsx-text pn) max)
             :method :xlsx-xml :media-type mt))
      ((string= e "csv")
       (list :text (%read-text-limited pn max) :method :csv :media-type mt))
      ((string= e "tsv")
       (list :text (%read-text-limited pn max) :method :tsv :media-type mt))
      ((string= e "docx")
       (list :text (%limit-text (%extract-docx-text pn) max)
             :method :docx-xml :media-type mt))
      ((%text-file-p pn)
       (list :text (%read-text-limited pn max) :method :text :media-type mt))
      ((%photo-file-p pn)
       (list :text nil :method :photo :media-type mt))
      ;; last resort: try as utf-8 text if not obviously binary
      ((not (%looks-binary-p pn))
       (handler-case
           (list :text (%read-text-limited pn max)
                 :method :utf8-fallback :media-type mt)
         (error ()
           (list :text nil :method :unreadable :media-type mt))))
      (t (list :text nil :method :binary :media-type mt)))))

(defun session-create (&key (mind nil) (id nil) (boot t))
  "Create a multi-turn interactive session bound to a mind."
  (when (and boot (or (null mind) (null *mind*) (not (mind-booted (or mind *mind*)))))
    (boot :bootstrap t :reset (null *mind*)))
  (let* ((m (ensure-mind (or mind *mind*)))
         (id (or id (format nil "sess-~D" (get-universal-time))))
         (s (make-session
             :id id
             :mind m
             :created (now-universal)
             :capabilities
             (list :ask :tell :pursue :reflect :epoch
                   :attach-file :attach-context :attach-photo
                   :list-attachments :help))))
    (setf (gethash id *sessions*) s
          *session* s)
    (metis-log :info "session create ~A" id)
    s))

(defun session-get (&optional id)
  (if id (gethash id *sessions*) *session*))

(defun session-ensure (&optional id)
  (or (session-get id) (session-create :id id)))

(defun %session-record-attachment (sess att)
  (setf (gethash (att-id att) (sess-attachments sess)) att)
  (let ((m (sess-mind sess))
        (fact (list 'attachment
                    (att-id att)
                    (att-kind att)
                    (or (att-name att) "")
                    (or (att-media-type att) "")
                    (or (att-size att) 0)
                    (or (att-path att) ""))))
    (assert-fact m fact :support :session :forward nil)
    (when (att-text att)
      (assert-fact m
                   (list 'attachment-text (att-id att)
                         (truncate-string (att-text att) 500))
                   :support :session :forward nil))
    (when (att-caption att)
      (assert-fact m
                   (list 'attachment-caption (att-id att) (att-caption att))
                   :support :session :forward nil))
    (remember-episode m
                      :situation (list :attached (att-kind att) (att-id att))
                      :action 'session-attach
                      :outcome :ok
                      :tags (list :session :attachment (att-kind att)))
    att))

(defun session-attach-context (sess text &key (name "context") (caption nil)
                                         (train t) (async t) (intensity :hard))
  "Attach freeform context text as session material.
   TRAIN defaults T — real continuous train (async brain queue), not context-only."
  (unless (stringp text)
    (error 'metis-error :message "context must be a string"))
  (let ((att (make-attachment
              :id (format nil "ctx-~D-~D"
                          (get-universal-time) (random 100000))
              :kind :context
              :path nil
              :media-type "text/plain"
              :size (length text)
              :name name
              :text text
              :caption caption
              :time (now-universal))))
    (%with-session-lock sess
      (lambda ()
        (%session-record-attachment sess att)
        (working-add (sess-mind sess) (list :context name text) :source :session)))
    (when (and train text (plusp (length (string-trim '(#\Space #\Newline) text))))
      (setf (att-meta att)
            (list* :train
                   (session-train-on-text! sess text
                                           :name (getf *session-hard-train-defaults* :name)
                                           :async async
                                           :intensity intensity
                                           :source :context)
                   (att-meta att))))
    att))

(defun session-attach-file (sess path &key (caption nil) (name nil)
                                      (train t) (train-name nil)
                                      (async t) (intensity :hard))
  "Attach a file of any common unstructured type; extract text when possible.
   TRAIN defaults T — actually continuous-trains the model (hard by default).
   ASYNC T (default) queues on the brain thread so chat stays responsive."
  (let* ((p (pathname path))
         (pn (namestring (truename p))))
    (unless (probe-file p)
      (error 'metis-error :message (format nil "file not found: ~A" path)))
    (when (uiop:directory-pathname-p (uiop:ensure-pathname pn))
      (return-from session-attach-file
        (session-attach-folder sess pn :caption caption :train train
                               :train-name train-name :async async
                               :intensity intensity)))
    (let* ((size (with-open-file (in pn :element-type '(unsigned-byte 8))
                   (file-length in)))
           (ex (extract-text-from-path pn))
           (text (getf ex :text))
           (train-result nil)
           (att (make-attachment
                 :id (format nil "file-~D-~D"
                             (get-universal-time) (random 100000))
                 :kind :file
                 :path pn
                 :media-type (or (getf ex :media-type) (%media-type-for pn))
                 :size size
                 :name (or name (file-namestring pn))
                 :text text
                 :caption caption
                 :meta (list :extract-method (getf ex :method)
                             :has-text (and text (plusp (length (or text "")))))
                 :time (now-universal))))
      (%with-session-lock sess
        (lambda () (%session-record-attachment sess att)))
      (when (and train text (plusp (length (string-trim '(#\Space #\Newline) text))))
        (setf train-result
              (session-train-on-text! sess text
                                      :name (or train-name
                                                (getf (%brain-train-params intensity) :name))
                                      :async async
                                      :intensity intensity
                                      :source :attach-file))
        (setf (att-meta att) (list* :train train-result (att-meta att))))
      (when *brain-auto-start* (brain-start!))
      att)))

(defun %list-files-recursive (root)
  "All regular files under ROOT (recursive)."
  (let ((root (uiop:ensure-directory-pathname (truename root)))
        (out nil))
    (labels ((walk (dir)
               (dolist (p (directory (merge-pathnames "*.*" dir)))
                 (unless (uiop:directory-pathname-p p)
                   (let ((name (file-namestring p)))
                     (unless (or (char= (char name 0) #\.)
                                 (string= name "symbol.sig"))
                       (push (namestring p) out)))))
               (dolist (d (directory (merge-pathnames "*/" dir)))
                 (let ((name (car (last (pathname-directory d)))))
                   (unless (or (null name)
                               (char= (char name 0) #\.)
                               (string-equal name ".git")
                               (string-equal name "node_modules")
                               (string-equal name "__pycache__"))
                     (walk d))))))
      (walk root))
    (nreverse out)))

(defun session-attach-folder (sess path &key (caption nil) (train t)
                                        (train-name nil) (recursive t)
                                        (async t) (intensity :ingest))
  "Attach all files under PATH (folder). Returns summary plist.
   TRAIN defaults T — continuous-train each text file (async brain by default)."
  (let* ((root (uiop:ensure-directory-pathname (truename path)))
         (files (if recursive
                    (%list-files-recursive root)
                    (mapcar #'namestring
                            (remove-if #'uiop:directory-pathname-p
                                       (directory (merge-pathnames "*.*" root))))))
         (attached nil)
         (with-text 0)
         (trained 0)
         (errors nil))
    (dolist (f files)
      (handler-case
          (let ((att (session-attach-file sess f
                                          :caption caption
                                          :train train
                                          :train-name train-name
                                          :async async
                                          :intensity intensity)))
            (push (list :id (att-id att)
                        :name (att-name att)
                        :path (att-path att)
                        :has-text (and (att-text att) t)
                        :method (getf (att-meta att) :extract-method)
                        :train (getf (att-meta att) :train))
                  attached)
            (when (att-text att)
              (incf with-text)
              (when train (incf trained))))
        (error (e)
          (push (list :path f :error (princ-to-string e)) errors))))
    (when (and train *brain-auto-start*) (brain-start!))
    (list :folder (namestring root)
          :files (length files)
          :attached (length attached)
          :with-text with-text
          :trained (if train trained 0)
          :train train
          :async async
          :intensity intensity
          :attachments (nreverse attached)
          :errors (nreverse errors)
          :corpus-chars (length (session-corpus sess))
          :brain (brain-status))))

(defun session-train-on-text! (sess text &key (name nil)
                                           (epochs nil) (hidden nil)
                                           (seq-len nil) (depth nil)
                                           (max-batches nil) (lr nil)
                                           (async t) (intensity :hard)
                                           (source :train))
  "Real continuous train on TEXT (weight updates via nn-continuous-train).
   ASYNC T (default): queue on brain thread — user keeps chatting.
   ASYNC NIL: block until this train step finishes."
  (let* ((d (%brain-train-params intensity))
         (name (or name (getf d :name)))
         (text (string-trim '(#\Space #\Newline #\Tab) (or text ""))))
    (when (< (length text) 8)
      (return-from session-train-on-text!
        (list :trained nil :reason "text too short")))
    (when async
      (return-from session-train-on-text!
        (brain-enqueue-train! text
                              :name name
                              :intensity intensity
                              :session sess
                              :source source
                              :epochs epochs :hidden hidden :seq-len seq-len
                              :depth depth :max-batches max-batches :lr lr)))
    (when (and (fboundp 'nn-path-allowed-p)
               (sess-mind sess)
               (not (nn-path-allowed-p (sess-mind sess))))
      (ignore-errors (nn-enable-path (sess-mind sess))))
    (let ((r (nn-continuous-train text
                                  :name name
                                  :epochs (or epochs (getf d :epochs))
                                  :hidden (or hidden (getf d :hidden))
                                  :seq-len (or seq-len (getf d :seq-len))
                                  :depth (or depth (getf d :depth))
                                  :max-batches (or max-batches (getf d :max-batches))
                                  :lr (or lr (getf d :lr)))))
      (list :trained t :async nil :name name :history (getf r :history)
            :chars (length text) :intensity intensity))))

(defun session-ingest-path (sess path &key (train t) (train-name "session-lm")
                                      (caption nil) (async t)
                                      (intensity :ingest))
  "Ingest a file or folder (unstructured). TRAIN defaults T — real learning."
  (let* ((p (uiop:ensure-pathname path :want-absolute t :defaults *default-pathname-defaults*))
         (p (or (probe-file p) p)))
    (cond
      ((not (probe-file p))
       (error 'metis-error :message (format nil "path not found: ~A" path)))
      ((uiop:directory-exists-p p)
       (session-attach-folder sess p :caption caption :train train
                              :train-name train-name :async async
                              :intensity intensity))
      (t
       (let ((att (session-attach-file sess p :caption caption :train train
                                       :train-name train-name :async async
                                       :intensity intensity)))
         (list :file (att-path att)
               :id (att-id att)
               :name (att-name att)
               :has-text (and (att-text att) t)
               :method (getf (att-meta att) :extract-method)
               :train train
               :train-meta (getf (att-meta att) :train)
               :corpus-chars (length (session-corpus sess))
               :brain (brain-status)))))))

(defun session-watch-folder (sess path &key (train t) (train-name "session-lm")
                                       (async t) (intensity :hard)
                                       (auto-brain t))
  "Register PATH for realtime folder drops. Brain thread polls continuously —
   new files are attached and hard-trained immediately (no manual /watch poll)."
  (let* ((root (namestring (uiop:ensure-directory-pathname (truename path))))
         (seen (make-hash-table :test #'equal)))
    (dolist (f (%list-files-recursive root))
      (setf (gethash f seen) t))
    (setf (gethash (sess-id sess) *session-folder-watches*)
          (list :path root :seen seen :train train :train-name train-name
                :async async :intensity intensity :session sess))
    (when auto-brain (brain-start!))
    ;; initial ingest of everything currently present
    (let ((r (session-attach-folder sess root :train train :train-name train-name
                                    :async async :intensity intensity)))
      (list* :watching root :brain (brain-status) r))))

(defun session-watch-poll! (&optional sess)
  "Poll watched folders; attach+train any new files. Returns list of ingest events.
   Called automatically by the brain thread; also available via /watch poll."
  (let ((events nil)
        (sid (and sess (sess-id sess))))
    (maphash
     (lambda (id rec)
       (when (or (null sid) (equal id sid))
         (let* ((s (or (getf rec :session) (session-get id)))
                (root (getf rec :path))
                (seen (getf rec :seen))
                (train (getf rec :train))
                (tname (getf rec :train-name))
                (async (if (member :async rec) (getf rec :async) t))
                (intensity (or (getf rec :intensity) :hard)))
           (when (and s root (probe-file root))
             (dolist (f (%list-files-recursive root))
               (unless (gethash f seen)
                 (setf (gethash f seen) t)
                 (handler-case
                     (let ((att (session-attach-file s f :train train
                                                     :train-name tname
                                                     :async async
                                                     :intensity intensity)))
                       (push (list :session id :path f
                                   :id (att-id att)
                                   :has-text (and (att-text att) t)
                                   :trained train
                                   :train-meta (getf (att-meta att) :train)
                                   :async async
                                   :intensity intensity)
                             events))
                   (error (e)
                     (push (list :session id :path f
                                 :error (princ-to-string e))
                           events)))))))))
     *session-folder-watches*)
    (nreverse events)))

(defun session-attach-photo (sess path &key (caption nil) (name nil))
  "Attach a photo/image; records media provenance (path, type, size, caption)."
  (let* ((p (pathname path))
         (pn (namestring (truename p))))
    (unless (probe-file p)
      (error 'metis-error :message (format nil "photo not found: ~A" path)))
    (unless (%photo-file-p pn)
      (error 'metis-error
             :message (format nil "not a photo extension: ~A" pn)))
    (let* ((size (with-open-file (in pn :element-type '(unsigned-byte 8))
                   (file-length in)))
           (att (make-attachment
                 :id (format nil "photo-~D-~D"
                             (get-universal-time) (random 100000))
                 :kind :photo
                 :path pn
                 :media-type (%media-type-for pn)
                 :size size
                 :name (or name (file-namestring pn))
                 :text nil
                 :caption caption
                 :meta (list :bytes size :type (%media-type-for pn))
                 :time (now-universal))))
      (%session-record-attachment sess att)
      att)))
(defun session-list-attachments (sess)
  (mapcar (lambda (a)
            (list :id (att-id a)
                  :kind (att-kind a)
                  :name (att-name a)
                  :path (att-path a)
                  :media-type (att-media-type a)
                  :size (att-size a)
                  :has-text (and (att-text a) t)
                  :caption (att-caption a)))
          (hash-table-values (sess-attachments sess))))

(defun session-get-attachment (sess id)
  (gethash id (sess-attachments sess)))

(defun session-attachment-text (sess id)
  (let ((a (session-get-attachment sess id)))
    (and a (att-text a))))

(defun session-status (sess)
  (list :id (sess-id sess)
        :turns (sess-turn-count sess)
        :attachments (length (hash-table-keys (sess-attachments sess)))
        :accommodations (sess-accommodations sess)
        :capabilities (sess-capabilities sess)
        :mind (mind-status (sess-mind sess))))
