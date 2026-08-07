;;;; interface.lisp — full interactive product surface + self-accommodation
(in-package :metis)

(defparameter *iface-thesis*
  "METIS INTERFACE: multi-turn interactive cognition with first-class
file/context/photo session material and TMS-guarded self-accommodation
when the user requests an unknown capability.")

(defun iface-thesis ()
  *iface-thesis*)

(defun %iface-parse-turn (text)
  "Parse user turn into an action. Returns (values op payload)."
  (let ((s (string-trim '(#\Space #\Tab #\Newline) text)))
    (cond
      ((zerop (length s))
       (values :empty nil))
      ((char= (char s 0) #\()
       (values :form
               (let ((*package* (find-package :metis))
                     (*read-eval* nil))
                 (read-from-string s))))
      ((or (string-equal s "help") (string-equal s "?"))
       (values :help nil))
      ((or (string-equal s "quit") (string-equal s "exit"))
       (values :quit nil))
      ((or (string-equal s "status") (string-equal s "/status"))
       (values :status nil))
      ((cl-ppcre:scan "(?i)^/attach\\s+file\\s+(\\S+)(?:\\s+(.*))?$" s)
       (cl-ppcre:register-groups-bind (path cap)
           ("(?i)^/attach\\s+file\\s+(\\S+)(?:\\s+(.*))?$" s)
         (values :attach-file (list path cap))))
      ((cl-ppcre:scan "(?i)^/attach\\s+photo\\s+(\\S+)(?:\\s+(.*))?$" s)
       (cl-ppcre:register-groups-bind (path cap)
           ("(?i)^/attach\\s+photo\\s+(\\S+)(?:\\s+(.*))?$" s)
         (values :attach-photo (list path cap))))
      ((cl-ppcre:scan "(?i)^/context\\s+(.+)$" s)
       (cl-ppcre:register-groups-bind (ctx)
           ("(?i)^/context\\s+(.+)$" s)
         (values :attach-context ctx)))
      ((cl-ppcre:scan "(?i)^/attachments\\s*$" s)
       (values :list-attachments nil))
      ((cl-ppcre:scan "(?i)^/ask\\s+(.+)$" s)
       (cl-ppcre:register-groups-bind (q)
           ("(?i)^/ask\\s+(.+)$" s)
         (values :ask q)))
      ((cl-ppcre:scan "(?i)^/tell\\s+(.+)$" s)
       (cl-ppcre:register-groups-bind (q)
           ("(?i)^/tell\\s+(.+)$" s)
         (values :tell q)))
      ((cl-ppcre:scan "(?i)^/goal\\s+(.+)$" s)
       (cl-ppcre:register-groups-bind (q)
           ("(?i)^/goal\\s+(.+)$" s)
         (values :goal q)))
      ((cl-ppcre:scan "(?i)^/need\\s+(.+)$" s)
       (cl-ppcre:register-groups-bind (cap)
           ("(?i)^/need\\s+(.+)$" s)
         (values :need (string-trim '(#\Space) cap))))
      ((cl-ppcre:scan "(?i)^/read\\s+(\\S+)$" s)
       (cl-ppcre:register-groups-bind (id)
           ("(?i)^/read\\s+(\\S+)$" s)
         (values :read-attachment id)))
      (t
       (values :freeform s)))))

(defun %iface-capability-present-p (sess name)
  (let* ((n (string-upcase (string name)))
         (tool-sym (intern n :metis)))
    (or (member (intern n :keyword) (sess-capabilities sess))
        (find-skills (sess-mind sess) :pattern n)
        (some (lambda (r)
                (search (string-downcase n)
                        (string-downcase (symbol-name (rule-name r)))))
              (kb-all-rules (mind-kb (sess-mind sess))))
        (tr-get (mind-tools (sess-mind sess)) tool-sym))))
(defun iface-accommodate (sess capability-name &key (doc nil))
  "Self-accommodation: register skill+tool under TMS-guarded self-mod.
   Tool symbol is reader-normal (UPCASE) so (tool NAME …) resolves like core tools."
  (let* ((m (sess-mind sess))
         (cap (string-upcase (string capability-name)))
         (sym (intern (format nil "CAP-~A" cap) :metis))
         ;; Must match read-time symbols: (tool HYPER-TRANSLATOR …) → HYPER-TRANSLATOR
         (tool-sym (intern cap :metis))
         (head (list sym '?input))
         (body (list (list 'true))))
    (multiple-value-bind (mod-ok mod-detail)
        (epoch-guarded-self-mod m sym head body :kind :rule)
      (unless mod-ok
        (return-from iface-accommodate (values nil mod-detail)))
      (pm-install
       (mind-pm m)
       (make-skill
        :name sym
        :params '(input)
        :preconds '()
        :body `((list :handled t
                      :capability ',sym
                      :input input
                      :doc ,(or doc (format nil "Accommodated ~A" cap))))
        :kind :procedure
        :source :iface-accommodate
        :utility 1.0
        :meta (list :doc doc :capability cap)))
      (register-tool
       m tool-sym
       (lambda (&rest args)
         (list :ok t
               :capability tool-sym
               :args args
               :via :accommodated-tool))
       :doc (or doc (format nil "User-accommodated tool ~A" cap))
       :schema '(&rest args)
       :safe t)
      (pushnew (intern cap :keyword) (sess-capabilities sess))
      (incf (sess-accommodations sess))
      (assert-fact m
                   (list 'capability-accommodated
                         (intern (string-downcase cap) :metis))
                   :support :iface
                   :forward nil)
      (values t
              (list :accommodated cap
                    :rule sym
                    :tool tool-sym
                    :mod mod-detail)))))
(defun %iface-read-form-string (s)
  (let ((*package* (find-package :metis))
        (*read-eval* nil))
    (read-from-string s)))

(defun %iface-dispatch (sess op payload)
  "Execute one parsed op; returns result object."
  (let ((m (sess-mind sess)))
    (case op
      (:empty (list :ok t :note :empty))
      (:quit (list :quit t))
      (:help
       (list :help
             '("/attach file PATH [caption]"
               "/attach photo PATH [caption]"
               "/context TEXT"
               "/attachments"
               "/read ATT-ID"
               "/ask PATTERN"
               "/tell FACT"
               "/goal GOAL"
               "/need CAPABILITY"
               "/train text CORPUS"
               "/train file PATH [name]"
               "/train attachments [name]"
               "/generate MODEL [prompt]"
               "/nn list | /nn enable | /nn disable"
               "/symbols list | info ID | enable ID | disable ID"
               "/symbols install PATH [id] | backend"
               "(lisp forms…)"
               "status | help | quit")))
      (:status (session-status sess))
      (:attach-file
       (destructuring-bind (path &optional cap) payload
         (let ((a (session-attach-file sess path :caption cap)))
           (list :attached :file
                 :id (att-id a)
                 :size (att-size a)
                 :has-text (and (att-text a) t)))))
      (:attach-photo
       (destructuring-bind (path &optional cap) payload
         (let ((a (session-attach-photo sess path :caption cap)))
           (list :attached :photo
                 :id (att-id a)
                 :media-type (att-media-type a)
                 :size (att-size a)
                 :path (att-path a)))))
      (:attach-context
       (let ((a (session-attach-context sess payload)))
         (list :attached :context
               :id (att-id a)
               :size (att-size a))))
      (:list-attachments
       (session-list-attachments sess))
      (:read-attachment
       (let ((a (session-get-attachment sess payload)))
         (if a
             (list :id (att-id a)
                   :kind (att-kind a)
                   :text (att-text a)
                   :path (att-path a)
                   :media-type (att-media-type a)
                   :caption (att-caption a))
             (list :error :unknown-attachment :id payload))))
      (:ask
       (let* ((pat (handler-case (%iface-read-form-string payload)
                     (error () payload)))
              (ans (if (stringp pat)
                       (ask m (list 'about pat))
                       (ask m pat))))
         (list :ask pat :answer ans)))
      (:tell
       (let ((fact (%iface-read-form-string payload)))
         (tell m fact)
         (list :told fact)))
      (:goal
       (let* ((g (%iface-read-form-string payload))
              (ok (%epoch-try-achieve m g)))
         (list :goal g :achieved ok
               :holds (and (kb-holds-p (mind-kb m) g) t))))
      (:need
       (if (%iface-capability-present-p sess payload)
           (list :already payload)
           (multiple-value-bind (ok detail)
               (iface-accommodate sess payload)
             (list :accommodated ok
                   :detail detail
                   :present-after
                   (%iface-capability-present-p sess payload)))))
      (:form
       (list :form payload :result (interpret m payload)))
      (:freeform
       (let* ((hits
               (remove-if-not
                (lambda (a)
                  (or (and (att-text a)
                           (search payload (att-text a) :test #'char-equal))
                      (and (att-caption a)
                           (search payload (att-caption a) :test #'char-equal))
                      (and (att-name a)
                           (search payload (att-name a) :test #'char-equal))))
                (hash-table-values (sess-attachments sess))))
              (ans (ask m (list 'about payload))))
         (cond
           (hits
            (list :freeform :from-attachments
                  :matches
                  (mapcar (lambda (a)
                            (list :id (att-id a)
                                  :kind (att-kind a)
                                  :name (att-name a)))
                          hits)))
           (ans (list :freeform :kb :answer ans))
           (t
            (list :freeform :unknown
                  :hint
                  (format nil "Try /need ~A to self-accommodate"
                          (cl-ppcre:regex-replace-all "\\s+" payload "-")))))))
      (t (list :error :unknown-op op)))))

(defun iface-turn (sess text)
  "One interactive turn. Multi-turn: call repeatedly on same SESS."
  (bt:with-lock-held ((sess-lock sess))
    (incf (sess-turn-count sess))
    (let* ((m (sess-mind sess))
           (pre-facts (kb-count-facts (mind-kb m)))
           (result nil)
           (reply nil)
           (nn-cmd (ignore-errors (%iface-nn-commands sess text)))
           (sym-cmd (unless nn-cmd
                      (ignore-errors (%iface-symbol-commands text)))))
      (push (list :role :user :text text :time (now-iso))
            (sess-turns sess))
      (multiple-value-bind (op payload)
          (cond (nn-cmd (values :nn nn-cmd))
                (sym-cmd (values :symbols sym-cmd))
                (t (%iface-parse-turn text)))
        (setf result
              (handler-case
                  (cond
                    ((eq op :nn)
                     (case (first payload)
                       (:train-file
                        (nn-continuous-train
                         (uiop:read-file-string (second payload))
                         :name (or (third payload)
                                   (pathname-name (second payload)))
                         :epochs 4 :hidden 256 :seq-len 64 :depth 2))
                       (:train-text
                        (nn-continuous-train (second payload)
                                             :name "session-lm"
                                             :epochs 4 :hidden 256
                                             :seq-len 64 :depth 2))
                       (:train-attachments
                        (nn-train-from-session sess
                                               :name (or (second payload)
                                                         "session-lm")
                                               :epochs 4 :hidden 256
                                               :seq-len 64 :depth 2))
                       (:generate
                        (list :text
                              (nn-generate (second payload)
                                           :prompt (or (third payload) "")
                                           :length 200
                                           :mind m)))
                       (:nn-list (list :models (metis.nn:nn-registry-list)))
                       (:nn-enable (list :enabled (nn-enable-path m)))
                       (:nn-disable (list :disabled (nn-disable-path m)))
                       (t (list :error :bad-nn-cmd payload))))
                    ((eq op :symbols)
                     (case (first payload)
                       (:symbols-list (list :symbols (symbol-list-info)))
                       (:symbol-info (list :symbol (symbol-info (second payload))))
                       (:symbol-enable (enable-symbol! (second payload)))
                       (:symbol-disable (disable-symbol! (second payload)))
                       (:symbol-install
                        (install-symbol! (second payload)
                                         :id (third payload)))
                       (:nn-backend (list :backend (nn-backend-status)))
                       (t (list :error :bad-symbol-cmd payload))))
                    (t (%iface-dispatch sess op payload)))
                (error (e)
                  (list :error (princ-to-string e)))))
        (setf reply (prin1-to-string result))
        (push (list :role :assistant
                    :text reply
                    :result result
                    :time (now-iso)
                    :facts-delta (- (kb-count-facts (mind-kb m)) pre-facts))
              (sess-turns sess))
        (list :reply reply
              :result result
              :turn (sess-turn-count sess)
              :session (session-status sess)
              :facts-delta (- (kb-count-facts (mind-kb m)) pre-facts))))))

(defun iface-drive (turns &key (session nil))
  "Drive multi-turn without REPL. TURNS is list of user strings."
  (let ((s (or session (session-ensure))))
    (mapcar (lambda (turn) (iface-turn s turn)) turns)))

(defun iface-repl (&optional session)
  "Full interactive interface REPL (multi-turn, same process)."
  (let ((s (or session (session-ensure)))
        (*package* (find-package :metis)))
    (format t "~%╔══════════════════════════════════════════════════════════╗~%")
    (format t "║  METIS INTERACTIVE INTERFACE                             ║~%")
    (format t "╚══════════════════════════════════════════════════════════╝~%")
    (format t "~A~%" (metis-version-string))
    (format t "~A~%~%" (iface-thesis))
    (format t "Session ~A — type help for commands.~%~%" (sess-id s))
    (loop
      (format t "you> ")
      (finish-output)
      (let ((line (read-line *standard-input* nil :eof)))
        (when (or (eq line :eof) (null line))
          (return :eof))
        (let ((resp (iface-turn s line)))
          (format t "metis> ~A~%" (getf resp :reply))
          (when (and (consp (getf resp :result))
                     (getf (getf resp :result) :quit))
            (format t "Goodbye.~%")
            (return :quit)))))))

(defun iface-flagship (&key (turns nil))
  "Non-interactive multi-turn demo for logs/CI."
  (boot :bootstrap t :reset t)
  (let* ((s (session-create))
         (script (or turns
                     (list "help"
                           "status"
                           "(tell (iface-demo alive))"
                           "(ask (iface-demo ?x))"
                           "/need translator"
                           "/need translator"))))
    (format t "~%=== METIS IFACE FLAGSHIP ===~%")
    (format t "~A~%~%" (iface-thesis))
    (let ((out (iface-drive script :session s)))
      (dolist (r out)
        (format t "turn ~A: ~A~%" (getf r :turn) (getf r :reply)))
      (format t "session: ~S~%" (session-status s))
      (list :iface-flagship t
            :turns (length out)
            :session (session-status s)
            :responses out))))
