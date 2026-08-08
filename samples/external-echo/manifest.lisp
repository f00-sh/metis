;;;; external-echo — signed marketplace sample (not a builtin in-tree enable)
(in-package :cl-user)

(let* ((path (or (and (boundp '*symbol-load-path*)
                      (symbol-value '*symbol-load-path*))
                 (uiop:pathname-directory-pathname *load-truename*))))
  (metis.symbols:register-symbol!
   :id "external-echo"
   :name "External Echo Sample"
   :version "1.0.0"
   :description "Signed external marketplace sample for install/trust demos."
   :capabilities '(:tool :demo :marketplace-sample)
   :priority 10
   :path path
   :hooks (metis.symbols:define-symbol-hooks
            :activate (lambda (rec)
                        (declare (ignore rec))
                        (when (and (find-package :metis)
                                   (boundp 'metis:*mind*)
                                   metis:*mind*
                                   (fboundp 'metis::register-tool))
                          (metis::register-tool
                           metis:*mind* 'external-echo
                           (lambda (&optional (msg "echo"))
                             (list :echo t :message msg
                                   :symbol "external-echo"))
                           :doc "External marketplace sample tool"
                           :schema '(&optional msg)
                           :safe t)
                          (metis:assert-fact metis:*mind*
                                             '(external-echo-loaded t)
                                             :support :external-echo
                                             :forward nil))
                        t)
            :deactivate (lambda (rec) (declare (ignore rec)) t))
   :meta (list :kind :sample :marketplace t)))
