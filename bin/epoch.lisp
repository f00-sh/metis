;;;; epoch.lisp — Metis 3.0 flagship launcher (shipped entry point)
(ql:quickload :metis :silent t)
(in-package :metis)

(defun %epoch-cli-main (argv)
  (let* ((resume (member "--resume" argv :test #'string=))
         (path (or (second (member "--path" argv :test #'string=))
                   (uiop:getenv "METIS_EPOCH_PATH")))
         (steps (let ((s (second (member "--steps" argv :test #'string=))))
                  (if s (parse-integer s :junk-allowed t) 12)))
         (id (or (second (member "--id" argv :test #'string=)) "flagship")))
    (epoch-flagship :durable-path path
                    :id id
                    :max-steps (or steps 12)
                    :resume resume
                    :goals '((clear a))
                    :self-mod t)))

(%epoch-cli-main (uiop:command-line-arguments))
(uiop:quit 0)
