;;;; image-ingest — photo/image attachment ingest for training & cognition
(in-package :cl-user)

(let* ((path (or (and (boundp '*symbol-load-path*)
                      (symbol-value '*symbol-load-path*))
                 (uiop:pathname-directory-pathname *load-truename*))))
  (metis.symbols:register-symbol!
   :id "image-ingest"
   :name "Image Ingest"
   :version "1.0.0"
   :description "Ingest session photos into KB + optional caption corpus text."
   :capabilities '(:tool :image-ingest :session)
   :priority 50
   :path path
   :hooks (metis.symbols:define-symbol-hooks
            :activate (lambda (rec)
                        (when (and (find-package :metis) metis:*mind*
                                   (fboundp 'metis::register-tool))
                          (metis::register-tool
                           metis:*mind* 'image-ingest
                           (lambda (&optional session-id)
                             (metis::image-ingest-session session-id))
                           :doc "Ingest all photo attachments in a session"
                           :schema '(&optional session-id)
                           :safe t))
                        (setf (getf (metis.symbols:sr-meta rec) :activated) t)
                        t)
            :deactivate (lambda (rec) (declare (ignore rec)) t))
   :meta (list :kind :category :category :image-ingest)))
