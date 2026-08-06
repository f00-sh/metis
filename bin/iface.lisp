;;;; iface.lisp — interactive multi-turn product entry
(ql:quickload :metis :silent t)
(in-package :metis)

(defun %iface-cli (argv)
  (cond
    ((member "--demo" argv :test #'string=)
     (iface-flagship)
     (uiop:quit 0))
    ((member "--drive" argv :test #'string=)
     ;; --drive followed by turns as remaining args
     (let* ((rest (cdr (member "--drive" argv :test #'string=)))
            (s (progn (boot) (session-create)))
            (res (iface-drive rest :session s)))
       (dolist (r res)
         (format t "turn ~A: ~A~%" (getf r :turn) (getf r :reply)))
       (format t "session: ~S~%" (session-status s))
       (uiop:quit 0)))
    (t
     (boot)
     (iface-repl)
     (uiop:quit 0))))

(%iface-cli (uiop:command-line-arguments))
