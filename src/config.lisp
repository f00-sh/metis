;;;; config.lisp
(in-package :metis)

(defparameter *config*
  (make-hash-table :test #'eq)
  "Runtime configuration knobs.")

(defun set-config (key value)
  (setf (gethash key *config*) value))

(defun get-config (key &optional default)
  (gethash key *config* default))

(defun load-config-file (&optional path)
  "Load key-value forms: (:key value) lines from file."
  (let ((path (or path
                  (uiop:getenv "METIS_CONFIG")
                  (merge-pathnames "metis.conf"
                                   (asdf:system-source-directory :metis)))))
    (when (probe-file path)
      (with-open-file (in path)
        (let ((*package* (find-package :metis)))
          (loop for form = (read in nil :eof)
                until (eq form :eof)
                when (and (consp form) (keywordp (first form)))
                do (set-config (first form) (second form)))))
      (metis-log :info "loaded config ~A" path)
      path)))

(defun %config-env (name)
  "Non-empty getenv or NIL."
  (let ((v (uiop:getenv name)))
    (when (and v (plusp (length (string-trim '(#\Space #\Tab #\Newline) v))))
      (string-trim '(#\Space #\Tab #\Newline) v))))

(defun %config-setenv (name value)
  "Best-effort putenv so later getenv sees VALUE."
  (when (and name value)
    #+sbcl (ignore-errors (sb-posix:setenv name value 1))
    #-sbcl (declare (ignore name value))
    value))

(defun load-dotenv (&optional path)
  "Load KEY=VALUE lines from .env files into the process environment.
   Searches project .env, cwd .env, ~/.metis/llm.env — never logs values."
  (let ((paths (remove nil
                       (list path
                             (ignore-errors
                               (merge-pathnames ".env"
                                                (asdf:system-source-directory :metis)))
                             (ignore-errors (merge-pathnames ".env" (uiop:getcwd)))
                             (merge-pathnames ".metis/llm.env" (user-homedir-pathname))
                             (merge-pathnames ".metis/.env" (user-homedir-pathname)))))
        (loaded 0))
    (dolist (p paths)
      (when (and p (probe-file p) (not (uiop:directory-pathname-p p)))
        (handler-case
            (with-open-file (in p :if-does-not-exist nil)
              (when in
                (loop for line = (read-line in nil :eof)
                      until (eq line :eof)
                      do (let ((line (string-trim '(#\Space #\Tab #\Return) line)))
                           (when (and (plusp (length line))
                                      (not (char= (char line 0) #\#))
                                      (find #\= line))
                             (let* ((eqpos (position #\= line))
                                    (k (string-trim '(#\Space #\Tab)
                                                    (subseq line 0 eqpos)))
                                    (v (string-trim '(#\Space #\Tab #\')
                                                    (string-trim '(#\")
                                                                (subseq line (1+ eqpos))))))
                               (when (and (plusp (length k)) (plusp (length v))
                                          (null (%config-env k)))
                                 (%config-setenv k v)
                                 (incf loaded))))))))
          (error () nil))))
    loaded))

(defun llm-keyfile-path ()
  (merge-pathnames ".metis/llm.key" (user-homedir-pathname)))

(defun %llm-read-keyfile ()
  "Single-line API key file ~/.metis/llm.key (git-ignored by convention)."
  (let ((p (llm-keyfile-path)))
    (when (probe-file p)
      (handler-case
          (with-open-file (in p)
            (let ((line (string-trim '(#\Space #\Tab #\Newline #\Return)
                                     (or (read-line in nil nil) ""))))
              (when (plusp (length line)) line)))
        (error () nil)))))

(defun %llm-mask-key (key)
  (let* ((k (or key ""))
         (n (length k)))
    (cond
      ((zerop n) "(none)")
      ((<= n 10) "********")
      (t (format nil "~A…~A" (subseq k 0 4) (subseq k (- n 4)))))))

(defun llm-save-key! (key &key (persist t))
  "Set API key in runtime config; when PERSIST, write ~/.metis/llm.key (mode 600).
   Enables LLM immediately. KEY is never logged."
  (let ((key (string-trim '(#\Space #\Tab #\Newline #\Return #\" #\')
                          (or key ""))))
    (when (< (length key) 8)
      (error 'metis-error :message "LLM key too short (refusing to save)"))
    (set-config :llm-api-key key)
    (set-config :llm-enabled t)
    (when persist
      (let* ((p (llm-keyfile-path))
             (dir (uiop:pathname-directory-pathname p)))
        (ensure-directories-exist dir)
        (with-open-file (out p :direction :output
                             :if-exists :supersede
                             :if-does-not-exist :create)
          (write-string key out)
          (terpri out))
        #+sbcl (ignore-errors (sb-posix:chmod (namestring p) #o600))))
    ;; pick provider defaults from key shape
    (when (or (eql 0 (search "xai-" key)) (eql 0 (search "xai_" key)))
      (unless (get-config :llm-base-url-locked)
        (set-config :llm-base-url "https://api.x.ai/v1"))
      (unless (get-config :llm-model-locked)
        (set-config :llm-model (or (get-config :llm-model) "grok-3"))))
    (configure-llm!)
    (list :ok t
          :persisted (and persist t)
          :path (and persist (namestring (llm-keyfile-path)))
          :key (%llm-mask-key key)
          :status (llm-status))))

(defun llm-clear-key! (&key (delete-file t))
  "Remove runtime key and optionally delete ~/.metis/llm.key."
  (set-config :llm-api-key nil)
  (set-config :llm-enabled nil)
  (when delete-file
    (let ((p (llm-keyfile-path)))
      (when (probe-file p)
        (ignore-errors (delete-file p)))))
  (configure-llm!)
  (list :ok t :cleared t :status (llm-status)))

(defun llm-set-model! (model)
  (let ((m (string-trim '(#\Space #\Tab) (or model ""))))
    (when (zerop (length m))
      (error 'metis-error :message "model name required"))
    (set-config :llm-model m)
    (set-config :llm-model-locked t)
    (configure-llm!)
    (list :ok t :model m :status (llm-status))))

(defun llm-set-base-url! (url)
  (let ((u (string-right-trim "/" (string-trim '(#\Space #\Tab) (or url "")))))
    (when (zerop (length u))
      (error 'metis-error :message "base URL required"))
    (set-config :llm-base-url u)
    (set-config :llm-base-url-locked t)
    (configure-llm!)
    (list :ok t :base-url u :status (llm-status))))

(defun configure-llm! (&key (force nil))
  "Resolve LLM key/provider/model and enable when a real key is available.
   Default provider = SpaceXAI / xAI (OpenAI-compatible). Call anytime — boot + freeform.
   Preference: runtime config (slash-set) → env → keyfile."
  (declare (ignore force))
  (load-dotenv)
  (let* ((key (or (let ((k (get-config :llm-api-key)))
                    (and k (plusp (length (string k))) k))
                  (%config-env "METIS_LLM_API_KEY")
                  (%config-env "XAI_API_KEY")
                  (%config-env "GROK_API_KEY")
                  (%config-env "OPENAI_API_KEY")
                  (%llm-read-keyfile)))
         (explicit-off
          (let ((e (%config-env "METIS_LLM_ENABLED")))
            (and e (member (string-downcase e) '("0" "false" "nil" "no")
                           :test #'string=))))
         (explicit-on
          (let ((e (%config-env "METIS_LLM_ENABLED")))
            (and e (not explicit-off))))
         (xai-key-p
          (or (%config-env "XAI_API_KEY")
              (%config-env "GROK_API_KEY")
              (and key
                   (or (eql 0 (search "xai-" key))
                       (%config-env "METIS_LLM_BASE_URL")))))
         (base (or (%config-env "METIS_LLM_BASE_URL")
                   (%config-env "OPENAI_BASE_URL")
                   (get-config :llm-base-url)
                   ;; SpaceXAI / xAI when using XAI/GROK keys; else OpenAI
                   (if (or (%config-env "XAI_API_KEY")
                           (%config-env "GROK_API_KEY")
                           (null (%config-env "OPENAI_API_KEY")))
                       "https://api.x.ai/v1"
                       "https://api.openai.com/v1")))
         (model (or (%config-env "METIS_LLM_MODEL")
                    (%config-env "XAI_MODEL")
                    (%config-env "OPENAI_MODEL")
                    (get-config :llm-model)
                    (if (search "x.ai" base :test #'char-equal)
                        "grok-3"
                        "gpt-4o-mini")))
         (has-key (and key (plusp (length key))))
         (enabled (and has-key (or explicit-on (not explicit-off)))))
    (declare (ignore xai-key-p))
    (when has-key (set-config :llm-api-key key))
    ;; respect slash-command locks for base/model
    (unless (get-config :llm-base-url-locked)
      (set-config :llm-base-url base))
    (unless (get-config :llm-model-locked)
      (set-config :llm-model model))
    ;; if locked, still fill defaults when empty
    (unless (get-config :llm-base-url)
      (set-config :llm-base-url base))
    (unless (get-config :llm-model)
      (set-config :llm-model model))
    (set-config :llm-temperature
                (or (let ((t0 (%config-env "METIS_LLM_TEMPERATURE")))
                      (and t0 (ignore-errors (read-from-string t0))))
                    (get-config :llm-temperature 0.2)))
    (set-config :llm-enabled (and enabled t))
    (set-config :llm-provider
                (cond
                  ((search "x.ai" (or base "") :test #'char-equal) :xai)
                  ((search "openai" (or base "") :test #'char-equal) :openai)
                  (t :openai-compatible)))
    (list :enabled (and (get-config :llm-enabled) t)
          :has-key has-key
          :provider (get-config :llm-provider)
          :model (get-config :llm-model)
          :base-url (get-config :llm-base-url))))

(defun llm-status ()
  "Human + machine status for the language cortex."
  (configure-llm!)
  (let* ((on (and (get-config :llm-enabled) (get-config :llm-api-key)))
         (prov (get-config :llm-provider :none))
         (model (get-config :llm-model))
         (key (get-config :llm-api-key)))
    (list :enabled (and on t)
          :provider prov
          :model model
          :has-key (and key t)
          :base-url (get-config :llm-base-url)
          :key-mask (%llm-mask-key key)
          :summary
          (if on
              (format nil "on · ~A · ~A" prov model)
              (format nil "off · /llm key <KEY>  (or XAI_API_KEY / ~~/.metis/llm.key)")))))

(defun init-config ()
  (clrhash *config*)
  (set-config :max-proof-depth 64)
  (set-config :max-forward-iterations 500)
  (set-config :max-plan-depth 24)
  (set-config :max-plan-nodes 5000)
  (set-config :working-memory-capacity 64)
  (set-config :activation-decay 0.05)
  (set-config :trace-reasoning t)
  (set-config :trace-limit 200)
  (set-config :llm-temperature 0.2)
  (set-config :safe-eval t)
  (set-config :tool-shell-enabled nil)
  (set-config :log-level :info)
  (set-config :log-to-stream t)
  (set-config :api-port 7433)
  (set-config :api-address "127.0.0.1")
  (set-config :api-token (uiop:getenv "METIS_API_TOKEN"))
  (set-config :daemon-interval 0.25)
  (set-config :world-dir
              (uiop:ensure-directory-pathname
               (merge-pathnames "worlds/"
                                (asdf:system-source-directory :metis))))
  (set-config :verbose nil)
  (set-config :local-learning t)   ; user-taught knowledge / local-user symbol
  (set-config :forward-engine :agenda)
  (set-config :auto-forward :agenda)
  (set-config :api-require-token nil)
  (set-config :api-max-body 65536)
  (set-config :api-rate-limit 120)
  ;; conf may set keys, but must not leave LLM disabled when a key exists
  (ignore-errors (load-config-file))
  ;; .env + env + keyfile → enable when key present (SpaceXAI/xAI default)
  (configure-llm!)
  (when (get-config :log-level)
    (setf *log-level* (get-config :log-level)))
  *config*)
