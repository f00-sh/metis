;;;; repl.lisp — interactive mind console
(in-package :metis)

(defun %repl-banner (mind)
  (format t "~%╔══════════════════════════════════════════════════════╗~%")
  (format t "║  METIS — introspective Common Lisp mind              ║~%")
  (format t "╚══════════════════════════════════════════════════════╝~%")
  (format t "~A~%~%" (mind-status mind))
  (format t "Forms: (tell FACT...) (ask PAT) (rule HEAD BODY...)~%")
  (format t "       (goal G...) (pursue G...) (plan G...) (cycle)~%")
  (format t "       (reflect) (self) (explain TOPIC) (tool NAME args...)~%")
  (format t "       (save NAME) (load NAME) (help) (quit)~%~%"))

(defun metis-repl (&optional mind)
  (let ((m (or mind *mind* (boot)))
        (*package* (find-package :metis))
        (*print-pretty* t)
        (*print-circle* t))
    (%repl-banner m)
    (loop
      (format t "metis> ")
      (finish-output)
      (let ((line (read-line *standard-input* nil :eof)))
        (cond
          ((or (eq line :eof) (null line))
           (return :eof))
          (t
           (let ((line (string-trim '(#\Space #\Tab) line)))
             (cond
               ((string= line "")
                nil)
               ((member line '("quit" "exit" ":q") :test #'string-equal)
                (format t "Sleeping.~%")
                (return :quit))
               (t
                (handler-case
                    (let* ((form (read-from-string line))
                           (result (interpret m form)))
                      (when (eq result :quit)
                        (format t "Sleeping.~%")
                        (return :quit))
                      (format t "~S~%" result))
                  (end-of-file ()
                    (format t ";; incomplete form~%"))
                  (error (e)
                    (format t ";; error: ~A~%" e))))))))))))
