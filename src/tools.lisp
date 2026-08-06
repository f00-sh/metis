;;;; tools.lisp — tool registry the mind can invoke
(in-package :metis)

(defstruct (tool (:conc-name tool-))
  name
  doc
  fn              ; (lambda (&rest args) ...)
  (schema nil)    ; optional arg description
  (safe t)
  (enabled t)
  (uses 0)
  (last-error nil))

(defstruct (tool-registry (:conc-name tr-))
  (tools (make-hash-table :test #'eq))
  (lock (bt:make-lock "metis-tools")))

(defun make-empty-tools ()
  (make-tool-registry))

(defun tr-register (reg name fn &key doc schema (safe t) (enabled t))
  (let ((tool (make-tool :name name :fn fn :doc doc :schema schema
                         :safe safe :enabled enabled)))
    (setf (gethash name (tr-tools reg)) tool)
    tool))

(defun tr-get (reg name)
  (gethash name (tr-tools reg)))

(defun tr-list (reg)
  (mapcar (lambda (tool)
            (list :name (tool-name tool)
                  :doc (tool-doc tool)
                  :safe (tool-safe tool)
                  :enabled (tool-enabled tool)
                  :uses (tool-uses tool)))
          (hash-table-values (tr-tools reg))))

(defun tr-invoke (reg name &rest args)
  (let ((tool (tr-get reg name)))
    (unless tool
      (error 'tool-error :tool name :message "unknown tool"))
    (unless (tool-enabled tool)
      (error 'tool-error :tool name :message "tool disabled"))
    (incf (tool-uses tool))
    (handler-case
        (apply (tool-fn tool) args)
      (error (e)
        (setf (tool-last-error tool) (princ-to-string e))
        (error 'tool-error :tool name
                           :message (princ-to-string e))))))

(defun install-core-tools (reg mind-ref)
  "mind-ref is a thunk or delayed access — we pass functions that close over mind later.
   Here mind-ref is a function of zero args returning the mind struct."
  (tr-register
   reg 'kb-assert
   (lambda (fact)
     (assert-fact (funcall mind-ref) fact)
     fact)
   :doc "Assert a fact into the knowledge base"
   :schema '(fact))

  (tr-register
   reg 'kb-ask
   (lambda (pattern)
     (ask (funcall mind-ref) pattern))
   :doc "Query KB for pattern matches"
   :schema '(pattern))

  (tr-register
   reg 'kb-facts
   (lambda ()
     (facts (funcall mind-ref)))
   :doc "List all KB facts")

  (tr-register
   reg 'remember
   (lambda (situation &optional outcome)
     (remember-episode (funcall mind-ref)
                       :situation situation
                       :outcome outcome)
     :ok)
   :doc "Store an episodic memory"
   :schema '(situation &optional outcome))

  (tr-register
   reg 'recall
   (lambda (&optional pattern)
     (mapcar (lambda (e)
               (list :id (ep-id e)
                     :situation (ep-situation e)
                     :action (ep-action e)
                     :outcome (ep-outcome e)
                     :valence (ep-valence e)))
             (recall-episodes (funcall mind-ref) :pattern pattern :limit 20)))
   :doc "Recall episodes matching pattern")

  (tr-register
   reg 'plan
   (lambda (goals)
     (plan (funcall mind-ref) goals))
   :doc "STRIPS plan for goals"
   :schema '(goals))

  (tr-register
   reg 'reflect
   (lambda (&optional topic)
     (reflect (funcall mind-ref) topic))
   :doc "Introspect on mind state / topic")

  (tr-register
   reg 'time-now
   (lambda () (now-iso))
   :doc "Current UTC time ISO-8601")

  (tr-register
   reg 'read-file
   (lambda (path)
     (let ((p (uiop:parse-native-namestring path)))
       (unless (uiop:file-exists-p p)
         (error "file not found: ~A" path))
       (uiop:read-file-string p)))
   :doc "Read a UTF-8 text file"
   :schema '(path)
   :safe t)

  (tr-register
   reg 'list-dir
   (lambda (path)
     (mapcar #'namestring
             (uiop:directory-files
              (uiop:ensure-directory-pathname path))))
   :doc "List files in directory"
   :schema '(path))

  (tr-register
   reg 'write-world-file
   (lambda (name content)
     (let* ((dir (get-config :world-dir))
            (path (merge-pathnames
                   (format nil "~A.lisp" name)
                   dir)))
       (ensure-directories-exist path)
       (with-open-file (out path :direction :output
                                 :if-exists :supersede
                                 :if-does-not-exist :create)
         (write-string content out))
       (namestring path)))
   :doc "Write a file under worlds/"
   :schema '(name content))

  (tr-register
   reg 'http-get
   (lambda (url)
     (multiple-value-bind (body status)
         (drakma:http-request url :want-stream nil)
       (list :status status
             :body (truncate-string
                    (cond ((stringp body) body)
                          ((vectorp body)
                           (map 'string #'code-char body))
                          (t (prin1-to-string body)))
                    8000))))
   :doc "HTTP GET (returns truncated body)"
   :schema '(url)
   :safe t)

  (tr-register
   reg 'eval-lisp
   (lambda (form)
     (let ((f (if (stringp form)
                  (let ((*package* (find-package :metis)))
                    (read-from-string form))
                  form)))
       (if (fboundp 'sandboxed-eval)
           (sandboxed-eval f)
           (let ((*package* (find-package :metis)))
             (eval f)))))
   :doc "Sandboxed eval of a Lisp form in :metis package"
   :schema '(form)
   :safe nil)

  (tr-register
   reg 'shell
   (lambda (command)
     (unless (get-config :tool-shell-enabled)
       (error "shell tool disabled (set-config :tool-shell-enabled t)"))
     (uiop:run-program command
                       :output :string
                       :error-output :string
                       :ignore-error-status t))
   :doc "Run shell command (disabled by default)"
   :schema '(command)
   :safe nil
   :enabled nil)

  (tr-register
   reg 'list-tools
   (lambda () (tr-list reg))
   :doc "List registered tools")

  reg)
