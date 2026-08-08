;;;; repl.lisp — interactive mind console (product-first: English + forms)
(in-package :metis)

(defun %repl-banner (mind)
  (format t "~%╔══════════════════════════════════════════════════════╗~%")
  (format t "║  METIS — chat + mind (English, @files, (forms))      ║~%")
  (format t "╚══════════════════════════════════════════════════════╝~%")
  (format t "~A~%~%" (mind-status mind))
  (format t "English:  tell me about dolphins~%")
  (format t "Files:    @./notes.txt   /attach PATH   /ingest DIR~%")
  (format t "Live:     /watch folder DIR   /brain status~%")
  (format t "Train:    /train text …   /train attachments   /nn enable~%")
  (format t "Forms:    (tell FACT) (ask PAT) (goal G) (reflect) (help)~%")
  (format t "          (quit) or quit~%~%"))

(defun %repl-line-is-form-p (line)
  "True when LINE is a Lisp/mind-language s-expression (starts with '(')."
  (let ((s (string-left-trim '(#\Space #\Tab) (or line ""))))
    (and (plusp (length s)) (char= (char s 0) #\())))

(defun %repl-session (mind)
  "Session bound to MIND for freeform / slash / @ commands."
  (let ((s (or (and *session*
                    (eq (sess-mind *session*) mind)
                    *session*)
               (session-create :mind mind :boot nil))))
    (setf *session* s)
    s))

(defun metis-repl (&optional mind)
  "Product console: natural English + slash/@ commands + (s-expression) forms.
   Non-form lines go through iface-turn (brain, attach, freeform English)."
  (let* ((m (or mind *mind* (boot)))
         (*package* (find-package :metis))
         (*print-pretty* t)
         (*print-circle* t)
         (sess (%repl-session m)))
    (ignore-errors (nn-enable-path m))
    (when *brain-auto-start* (brain-start!))
    (%repl-banner m)
    (format t "Session ~A — brain ~A~%~%"
            (sess-id sess)
            (if (getf (brain-status) :running) "LIVE" "off"))
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
               ((member line '("quit" "exit" "/quit" "/exit" ":q" ":quit" ":exit")
                        :test #'string-equal)
                (format t "Sleeping.~%")
                (return :quit))
               ;; Classic mind language: (tell …) (ask …) …
               ((%repl-line-is-form-p line)
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
                    (format t ";; error: ~A~%" e))))
               ;; Product surface: English, /commands, @files
               (t
                (handler-case
                    (let ((resp (iface-turn sess line)))
                      (format t "~A~%" (or (getf resp :reply) ""))
                      (when (and (consp (getf resp :result))
                                 (getf (getf resp :result) :quit))
                        (format t "Sleeping.~%")
                        (return :quit)))
                  (error (e)
                    (format t ";; error: ~A~%" e))))))))))))
