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
  (set-config :llm-enabled nil)
  (set-config :llm-base-url (or (uiop:getenv "METIS_LLM_BASE_URL")
                                "https://api.openai.com/v1"))
  (set-config :llm-api-key (or (uiop:getenv "METIS_LLM_API_KEY")
                               (uiop:getenv "OPENAI_API_KEY")
                               (uiop:getenv "XAI_API_KEY")))
  (set-config :llm-model (or (uiop:getenv "METIS_LLM_MODEL") "gpt-4o-mini"))
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
  (set-config :forward-engine :agenda)
  (set-config :auto-forward :agenda)
  (set-config :api-require-token nil)
  (set-config :api-max-body 65536)
  (set-config :api-rate-limit 120)
  (ignore-errors (load-config-file))
  (when (get-config :log-level)
    (setf *log-level* (get-config :log-level)))
  *config*)
