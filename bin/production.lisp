;;;; production entry — full stack boot
(ql:quickload :metis :silent t)
(in-package :metis)

(defun main ()
  (let* ((args (uiop:command-line-arguments))
         (api (member "--api" args :test #'string=))
         (daemon (member "--daemon" args :test #'string=))
         (society (member "--society" args :test #'string=))
         (repl (or (member "--repl" args :test #'string=)
                   (and (not api) (not daemon)))))
    (production-boot :api api :daemon daemon :society society)
    (format t "~&~A ready.~%" (metis-version-string))
    (when repl
      (run))
    (when (or api daemon)
      (format t "Serving (Ctrl+C to stop).~%")
      (loop (sleep 3600)))))

(main)
