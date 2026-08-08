;;;; llm.lisp — optional OpenAI-compatible completion bridge
(in-package :metis)

(defun llm-enabled-p ()
  "T when a usable API key is configured. Re-resolves env/.env each call so
   exporting XAI_API_KEY mid-session or after .env edit takes effect."
  (ignore-errors (configure-llm!))
  (and (get-config :llm-enabled)
       (get-config :llm-api-key)
       (plusp (length (string (get-config :llm-api-key))))))

(defun %json-bool (x)
  (if x 'yason:true 'yason:false))

(defun %encode-json (obj)
  (with-output-to-string (s)
    (yason:encode obj s)))

(defun llm-complete (prompt &key (system nil) (temperature nil) (model nil)
                              (max-tokens 1024))
  "Chat completion against OpenAI-compatible API.
   Returns assistant text string."
  (unless (get-config :llm-api-key)
    (error 'llm-error :message "No API key (METIS_LLM_API_KEY / OPENAI_API_KEY / XAI_API_KEY)"))
  (let* ((url (format nil "~A/chat/completions"
                      (string-right-trim
                       "/" (get-config :llm-base-url "https://api.openai.com/v1"))))
         (model (or model (get-config :llm-model "gpt-4o-mini")))
         (temperature (or temperature (get-config :llm-temperature 0.2)))
         (messages (remove nil
                           (list (when system
                                   (alexandria:alist-hash-table
                                    `(("role" . "system")
                                      ("content" . ,system))
                                    :test #'equal))
                                 (alexandria:alist-hash-table
                                  `(("role" . "user")
                                    ("content" . ,prompt))
                                  :test #'equal))))
         (body-ht (alexandria:alist-hash-table
                   `(("model" . ,model)
                     ("temperature" . ,temperature)
                     ("max_tokens" . ,max-tokens)
                     ("messages" . ,messages))
                   :test #'equal))
         (body (with-output-to-string (s)
                 (let ((yason:*symbol-encoder* #'yason:encode-symbol-as-string))
                   (yason:encode body-ht s)))))
    (multiple-value-bind (response status headers)
        (drakma:http-request
         url
         :method :post
         :content-type "application/json"
         :additional-headers
         `(("Authorization" . ,(format nil "Bearer ~A"
                                       (get-config :llm-api-key))))
         :content body
         :want-stream nil)
      (declare (ignore headers))
      (let ((text (cond ((stringp response) response)
                        ((vectorp response)
                         (map 'string #'code-char response))
                        (t (prin1-to-string response)))))
        (unless (= status 200)
          (error 'llm-error
                 :message (format nil "HTTP ~A: ~A" status
                                  (truncate-string text 500))))
        (let* ((yason:*parse-object-as* :hash-table)
               (data (yason:parse text))
               (choices (gethash "choices" data))
               (msg (and choices (gethash "message" (first choices))))
               (content (and msg (gethash "content" msg))))
          (or content ""))))))

(defun llm-extract-sexps (text)
  "Pull readable s-expressions from LLM text (``` blocks or bare)."
  (let ((forms nil)
        (s text))
    ;; fenced blocks
    (cl-ppcre:do-matches-as-strings
        (block "```(?:lisp|cl|scheme)?\\s*([\\s\\S]*?)```" s)
      (handler-case
          (with-input-from-string (in (cl-ppcre:regex-replace
                                       "```(?:lisp|cl|scheme)?\\s*" block ""))
            (loop for form = (read in nil :eof)
                  until (eq form :eof)
                  do (push form forms)))
        (error ())))
    (when forms
      (return-from llm-extract-sexps (nreverse forms)))
    ;; whole string
    (handler-case
        (with-input-from-string (in text)
          (loop for form = (read in nil :eof)
                until (eq form :eof)
                collect form))
      (error () nil))))

(defun llm-reason (mind prompt &key (use-context t))
  "Hybrid: LLM proposes; returns raw text + parsed forms."
  (let* ((system
          (when use-context
            (format nil
                    "You are the language cortex of Metis, a Common Lisp cognitive architecture.
Reply with concise reasoning. Prefer s-expressions for actions:
(assert FACT) (rule HEAD <- BODY...) (plan (GOAL...)) (tool NAME . ARGS) (answer X).
Known facts (sample): ~%~S~%"
                    (subseq (facts mind) 0 (min 30 (length (facts mind)))))))
         (text (llm-complete prompt :system system)))
    (list :text text :forms (llm-extract-sexps text))))
