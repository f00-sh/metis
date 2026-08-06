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
  (lock (bt:make-lock "metis-session")))

(defvar *session* nil)
(defvar *sessions* (make-hash-table :test #'equal))

(defparameter *text-extensions*
  '(".txt" ".md" ".lisp" ".asd" ".json" ".csv" ".log" ".org" ".html" ".xml" ".yml" ".yaml"))

(defparameter *photo-extensions*
  '(".png" ".jpg" ".jpeg" ".gif" ".webp" ".bmp" ".tif" ".tiff"))

(defun %ext (path)
  (string-downcase (or (pathname-type path) "")))

(defun %media-type-for (path)
  (let ((e (%ext path)))
    (cond
      ((member e '("png") :test #'string=) "image/png")
      ((member e '("jpg" "jpeg") :test #'string=) "image/jpeg")
      ((member e '("gif") :test #'string=) "image/gif")
      ((member e '("webp") :test #'string=) "image/webp")
      ((member e '("txt" "md" "log" "csv") :test #'string=) "text/plain")
      ((member e '("lisp" "asd") :test #'string=) "text/x-common-lisp")
      ((member e '("json") :test #'string=) "application/json")
      ((member e '("html") :test #'string=) "text/html")
      (t "application/octet-stream"))))

(defun %text-file-p (path)
  (member (concatenate 'string "." (%ext path))
          *text-extensions* :test #'string-equal))

(defun %photo-file-p (path)
  (member (concatenate 'string "." (%ext path))
          *photo-extensions* :test #'string-equal))

(defun %read-text-limited (path &optional (max 100000))
  (let ((s (uiop:read-file-string path)))
    (if (> (length s) max)
        (subseq s 0 max)
        s)))

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

(defun session-attach-context (sess text &key (name "context") (caption nil))
  "Attach freeform context text as session material.
   Does not advance sess-turn-count (that is only for iface-turn)."
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
    (%session-record-attachment sess att)
    (working-add (sess-mind sess) (list :context name text) :source :session)
    att))
(defun session-attach-file (sess path &key (caption nil) (name nil))
  "Attach an ordinary file; text files get body extract."
  (let* ((p (pathname path))
         (pn (namestring (truename p))))
    (unless (probe-file p)
      (error 'metis-error :message (format nil "file not found: ~A" path)))
    (let* ((size (with-open-file (in pn :element-type '(unsigned-byte 8))
                   (file-length in)))
           (text (when (%text-file-p pn)
                   (%read-text-limited pn)))
           (att (make-attachment
                 :id (format nil "file-~D-~D"
                             (get-universal-time) (random 100000))
                 :kind :file
                 :path pn
                 :media-type (%media-type-for pn)
                 :size size
                 :name (or name (file-namestring pn))
                 :text text
                 :caption caption
                 :time (now-universal))))
      (%session-record-attachment sess att)
      att)))

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
