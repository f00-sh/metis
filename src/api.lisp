;;;; api.lisp — production HTTP/JSON API (Hunchentoot) + security gates
(in-package :metis)

(defvar *api-acceptor* nil)
(defvar *api-token* nil)
(defvar *api-hits* (make-hash-table :test #'equal))
(defvar *api-hit-lock* (bt:make-lock "metis-api-rate"))

(defun %json-out (obj)
  (with-output-to-string (s)
    (yason:encode obj s)))

(defun %json-alist (plist)
  "Convert plist-ish tree to hash-tables/lists for yason."
  (labels ((conv (x)
             (cond
               ((hash-table-p x) x)
               ((and (consp x) (keywordp (car x)))
                (let ((h (make-hash-table :test #'equal)))
                  (loop for (k v) on x by #'cddr
                        when (keywordp k)
                        do (setf (gethash (string-downcase (symbol-name k)) h)
                                 (conv v)))
                  h))
               ((listp x) (mapcar #'conv x))
               ((symbolp x) (symbol-name x))
               (t x))))
    (conv plist)))

(defun api-require-auth (&optional token-header configured-token)
  "Auth gate: if configured-token set, header must match. Pure for tests."
  (let ((need (or configured-token *api-token*)))
    (if (null need)
        t
        (equal token-header need))))

(defun %api-authorized-p ()
  (api-require-auth (hunchentoot:header-in* :x-metis-token) *api-token*))

(defun api-security-check-input (str &key (max-len nil))
  "Reject oversized / suspicious input before read. Returns (values ok reason)."
  (let ((max-len (or max-len (get-config :api-max-body 65536))))
    (cond
      ((null str) (values t nil))
      ((not (stringp str)) (values nil "non-string"))
      ((> (length str) max-len) (values nil "body-too-large"))
      ((search "#." str :test #'char-equal) (values nil "reader-eval-forbidden"))
      ((cl-ppcre:scan "(?i)\\buiop:(quit|run-program)\\b" str)
       (values nil "dangerous-form"))
      ((cl-ppcre:scan "(?i)\\b(sb-ext:quit|sb-ext:run-program)\\b" str)
       (values nil "dangerous-form"))
      (t (values t nil)))))

(defun %api-rate-ok-p (client-id)
  (bt:with-lock-held (*api-hit-lock*)
    (let* ((now (get-universal-time))
           (window (floor now 60))
           (key (cons client-id window))
           (n (incf (gethash key *api-hits* 0)))
           (limit (get-config :api-rate-limit 120)))
      ;; opportunistic prune
      (maphash (lambda (k v)
                 (declare (ignore v))
                 (when (< (cdr k) (- window 2))
                   (remhash k *api-hits*)))
               *api-hits*)
      (<= n limit))))

(defun %api-read-json ()
  (let* ((raw (hunchentoot:raw-post-data :force-text t))
         (yason:*parse-object-as* :hash-table))
    (multiple-value-bind (ok reason)
        (api-security-check-input raw)
      (unless ok
        (error 'metis-error :message (format nil "api input rejected: ~A" reason))))
    (if (and raw (plusp (length raw)))
        (yason:parse raw)
        (make-hash-table :test #'equal))))

(defun %api-safe-read (str)
  (multiple-value-bind (ok reason)
      (api-security-check-input str)
    (unless ok
      (error 'metis-error :message (format nil "api input rejected: ~A" reason)))
    (let ((*package* (find-package :metis))
          (*read-eval* nil))
      (read-from-string str))))

(defun %api-body-field (body key &optional default)
  (or (gethash key body) (gethash (string-downcase key) body) default))

(defun %api-respond (data &optional (code 200))
  (setf (hunchentoot:return-code*) code
        (hunchentoot:content-type*) "application/json")
  (%json-out (%json-alist data)))

(hunchentoot:define-easy-handler (api-health :uri "/v1/health") ()
  (%api-respond (list :ok t
                      :version *metis-version*
                      :codename *metis-codename*
                      :status (and *mind* (mind-status *mind*)))))

(hunchentoot:define-easy-handler (api-version :uri "/v1/version") ()
  (%api-respond (metis-build-info)))

(hunchentoot:define-easy-handler (api-ask :uri "/v1/ask") ()
  (unless (%api-authorized-p)
    (return-from api-ask (%api-respond (list :error "unauthorized") 401)))
  (unless (%api-rate-ok-p (or (hunchentoot:real-remote-addr) "local"))
    (return-from api-ask (%api-respond (list :error "rate-limit") 429)))
  (handler-case
      (let* ((body (%api-read-json))
             (pat-str (%api-body-field body "pattern"))
             (pat (if (stringp pat-str) (%api-safe-read pat-str) pat-str))
             (ans (ask *mind* pat)))
        (%api-respond (list :pattern pat-str :answer (prin1-to-string ans))))
    (error (e)
      (%api-respond (list :error (princ-to-string e)) 400))))

(hunchentoot:define-easy-handler (api-tell :uri "/v1/tell") ()
  (unless (%api-authorized-p)
    (return-from api-tell (%api-respond (list :error "unauthorized") 401)))
  (unless (%api-rate-ok-p (or (hunchentoot:real-remote-addr) "local"))
    (return-from api-tell (%api-respond (list :error "rate-limit") 429)))
  (handler-case
      (let* ((body (%api-read-json))
             (fact-str (%api-body-field body "fact"))
             (fact (%api-safe-read fact-str)))
        (assert-fact *mind* fact)
        (%api-respond (list :ok t :fact fact-str)))
    (error (e)
      (%api-respond (list :error (princ-to-string e)) 400))))

(hunchentoot:define-easy-handler (api-pursue :uri "/v1/pursue") ()
  (unless (%api-authorized-p)
    (return-from api-pursue (%api-respond (list :error "unauthorized") 401)))
  (unless (%api-rate-ok-p (or (hunchentoot:real-remote-addr) "local"))
    (return-from api-pursue (%api-respond (list :error "rate-limit") 429)))
  (handler-case
      (let* ((body (%api-read-json))
             (g-str (%api-body-field body "goal"))
             (goal (%api-safe-read g-str))
             (result (pursue *mind* goal)))
        (%api-respond (list :ok (getf result :success)
                            :remaining (prin1-to-string (getf result :remaining-goals))
                            :status (getf result :status))))
    (error (e)
      (%api-respond (list :error (princ-to-string e)) 400))))

(hunchentoot:define-easy-handler (api-reflect :uri "/v1/reflect") ()
  (unless (%api-authorized-p)
    (return-from api-reflect (%api-respond (list :error "unauthorized") 401)))
  (%api-respond (list :status (mind-status *mind*)
                      :self (prin1-to-string (self-model *mind*))
                      :logs (mapcar (lambda (e)
                                      (list :time (getf e :time)
                                            :level (symbol-name (getf e :level))
                                            :msg (getf e :msg)))
                                    (recent-logs 20)))))

(hunchentoot:define-easy-handler (api-interpret :uri "/v1/interpret") ()
  (unless (%api-authorized-p)
    (return-from api-interpret (%api-respond (list :error "unauthorized") 401)))
  (unless (%api-rate-ok-p (or (hunchentoot:real-remote-addr) "local"))
    (return-from api-interpret (%api-respond (list :error "rate-limit") 429)))
  (handler-case
      (let* ((body (%api-read-json))
             (form-str (%api-body-field body "form")))
        (multiple-value-bind (ok reason)
            (api-security-check-input form-str)
          (unless ok
            (return-from api-interpret
              (%api-respond (list :error reason) 400))))
        (let ((*read-eval* nil)
              (result (interpret *mind* form-str)))
          (%api-respond (list :result (prin1-to-string result)))))
    (error (e)
      (%api-respond (list :error (princ-to-string e)) 400))))

(hunchentoot:define-easy-handler (api-cycle :uri "/v1/cycle") ()
  (unless (%api-authorized-p)
    (return-from api-cycle (%api-respond (list :error "unauthorized") 401)))
  (%api-respond (list :result (prin1-to-string (cognitive-cycle *mind*)))))

(defun api-start (&key (port 7433) (address "127.0.0.1") (token nil))
  "Start production HTTP API. Default localhost only.
   If METIS_API_TOKEN or token is set, all mutating endpoints require it.
   If :api-require-token is T and no token, refuse to start."
  (when *api-acceptor*
    (api-stop))
  (setf *api-token* (or token (get-config :api-token)
                        (uiop:getenv "METIS_API_TOKEN")))
  (when (and (get-config :api-require-token nil) (null *api-token*))
    (error 'metis-error
           :message "api-require-token set but no token configured"))
  (unless (or (string= address "127.0.0.1")
              (string= address "::1")
              (string= address "localhost")
              *api-token*)
    (metis-log :warn "API bound to ~A without token — set METIS_API_TOKEN" address))
  (setf *api-acceptor*
        (make-instance 'hunchentoot:easy-acceptor
                       :port port
                       :address address))
  (hunchentoot:start *api-acceptor*)
  (metis-log :info "API listening on ~A:~A (token=~A)"
             address port (if *api-token* "yes" "no"))
  (list :port port :address address :token (and *api-token* t)))

(defun api-stop ()
  (when *api-acceptor*
    (hunchentoot:stop *api-acceptor*)
    (setf *api-acceptor* nil)
    (metis-log :info "API stopped")
    t))

(defun api-status ()
  (list :running (and *api-acceptor* t)
        :port (and *api-acceptor* (hunchentoot:acceptor-port *api-acceptor*))
        :token (and *api-token* t)))
