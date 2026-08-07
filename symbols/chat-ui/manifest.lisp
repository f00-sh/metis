;;;; chat-ui — interactive chat surface helpers for Metis sessions
(in-package :cl-user)

(let* ((path (or (and (boundp '*symbol-load-path*)
                      (symbol-value '*symbol-load-path*))
                 (uiop:pathname-directory-pathname *load-truename*))))
  (metis.symbols:register-symbol!
   :id "chat-ui"
   :name "Chat UI"
   :version "1.0.0"
   :description "Session chat summary, transcript, and multi-turn helpers."
   :capabilities '(:iface :tool :chat-ui)
   :priority 50
   :path path
   :hooks (metis.symbols:define-symbol-hooks
            :activate (lambda (rec)
                        (when (and (find-package :metis)
                                   (boundp 'metis:*mind*)
                                   metis:*mind*
                                   (fboundp 'metis::register-tool))
                          (metis::register-tool
                           metis:*mind* 'chat-summary
                           (lambda (&optional session-id)
                             (metis::chat-ui-summary session-id))
                           :doc "Summarize session chat turns"
                           :schema '(&optional session-id)
                           :safe t)
                          (metis::register-tool
                           metis:*mind* 'chat-transcript
                           (lambda (&optional session-id)
                             (metis::chat-ui-transcript session-id))
                           :doc "Full chat transcript for a session"
                           :schema '(&optional session-id)
                           :safe t))
                        (setf (getf (metis.symbols:sr-meta rec) :activated) t)
                        t)
            :deactivate (lambda (rec) (declare (ignore rec)) t))
   :meta (list :kind :category :category :chat-ui)))
