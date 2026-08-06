;;;; daemon.lisp — continuous cognitive loop as background service
(in-package :metis)

(defstruct (daemon (:conc-name dae-))
  mind
  (running nil)
  (thread nil)
  (interval 0.25)
  (cycles 0)
  (last-error nil)
  (on-cycle nil))

(defvar *daemon* nil)

(defun daemon-start (&optional mind &key (interval 0.25) on-cycle)
  (when (and *daemon* (dae-running *daemon*))
    (return-from daemon-start *daemon*))
  (let* ((m (ensure-mind (or mind *mind*)))
         (d (make-daemon :mind m :interval interval :on-cycle on-cycle
                         :running t)))
    (setf *daemon* d)
    (setf (dae-thread d)
          (bt:make-thread
           (lambda ()
             (metis-log :info "daemon started")
             (loop while (dae-running d)
                   do (handler-case
                          (progn
                            (when (mind-goals (dae-mind d))
                              (cognitive-cycle (dae-mind d)))
                            (incf (dae-cycles d))
                            (when (dae-on-cycle d)
                              (funcall (dae-on-cycle d) (dae-mind d) (dae-cycles d)))
                            ;; soft belief decay
                            (belief-decay-all (mind-beliefs (dae-mind d)) 0.999)
                            (sleep (dae-interval d)))
                        (error (e)
                          (setf (dae-last-error d) (princ-to-string e))
                          (metis-log :error "daemon: ~A" e)
                          (sleep 1.0))))
             (metis-log :info "daemon stopped"))
           :name "metis-daemon"))
    d))

(defun daemon-stop ()
  (when *daemon*
    (setf (dae-running *daemon*) nil)
    (when (and (dae-thread *daemon*)
               (bt:thread-alive-p (dae-thread *daemon*)))
      (bt:join-thread (dae-thread *daemon*)))
    (setf (dae-thread *daemon*) nil)
    (metis-log :info "daemon stop requested")
    t))

(defun daemon-status ()
  (when *daemon*
    (list :running (dae-running *daemon*)
          :cycles (dae-cycles *daemon*)
          :interval (dae-interval *daemon*)
          :last-error (dae-last-error *daemon*)
          :mind (and (dae-mind *daemon*) (mind-status (dae-mind *daemon*))))))
