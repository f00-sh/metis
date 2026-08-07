;;;; registry.lisp — register, enable/disable, capability query
(in-package :metis.symbols)

(defun register-symbol! (&key id name version description capabilities
                           priority path hooks meta backend)
  (unless (and id (stringp id) (plusp (length id)))
    (error "symbol id must be a non-empty string"))
  (let* ((existing (gethash id *symbol-registry*))
         (rec (or existing (make-symbol-record :id id))))
    (setf (sr-name rec) (or name id)
          (sr-version rec) (or version "0.0.0")
          (sr-description rec) (or description "")
          (sr-capabilities rec) (copy-list capabilities)
          (sr-priority rec) (or priority 0)
          (sr-path rec) path
          (sr-hooks rec) hooks
          (sr-meta rec) meta
          (sr-state rec) (if existing (sr-state rec) :loaded)
          (sr-backend rec) (or backend (sr-backend rec)))
    (setf (gethash id *symbol-registry*) rec)
    rec))

(defun symbol-get (id)
  (gethash id *symbol-registry*))

(defun symbol-list ()
  (hash-table-keys *symbol-registry*))

(defun symbol-list-records ()
  (hash-table-values *symbol-registry*))

(defun symbol-info (id)
  (let ((r (symbol-get id)))
    (unless r
      (return-from symbol-info nil))
    (list :id (sr-id r)
          :name (sr-name r)
          :version (sr-version r)
          :description (sr-description r)
          :capabilities (sr-capabilities r)
          :priority (sr-priority r)
          :enabled (sr-enabled r)
          :state (sr-state r)
          :path (and (sr-path r) (namestring (sr-path r)))
          :error (sr-error r)
          :meta (sr-meta r)
          :backend (when (sr-backend r)
                     (ignore-errors (nn-backend-status (sr-backend r)))))))

(defun capability-providers (capability &key (enabled-only t))
  (sort
   (remove-if-not
    (lambda (r)
      (and (member capability (sr-capabilities r) :test #'eq)
           (or (not enabled-only) (sr-enabled r))))
    (symbol-list-records))
   #'> :key #'sr-priority))

(defun %call-hook (rec key &rest args)
  (let ((fn (getf (sr-hooks rec) key)))
    (when fn (apply fn rec args))))

(defun enable-symbol! (id &key (force nil))
  "Enable symbol ID. For :nn-backend symbols, becomes the active compute backend."
  (let ((rec (or (symbol-get id)
                 (progn (load-symbol! id) (symbol-get id)))))
    (unless rec
      (error "unknown symbol ~A" id))
    (when (and (sr-enabled rec) (not force))
      (return-from enable-symbol! (symbol-info id)))
    (handler-case
        (progn
          (%call-hook rec :activate)
          (setf (sr-enabled rec) t
                (sr-state rec) :enabled
                (sr-error rec) nil)
          ;; nn-backend: exclusive activation by priority selection
          (when (member :nn-backend (sr-capabilities rec) :test #'eq)
            (dolist (other (symbol-list-records))
              (when (and (not (equal (sr-id other) id))
                         (sr-enabled other)
                         (member :nn-backend (sr-capabilities other) :test #'eq))
                (setf (sr-enabled other) nil
                      (sr-state other) :loaded)
                (%call-hook other :deactivate)))
            (let ((be (or (sr-backend rec)
                          (getf (sr-hooks rec) :backend)
                          (%call-hook rec :backend))))
              (when be
                (setf (sr-backend rec) be)
                (set-nn-backend! be))))
          (symbol-info id))
      (error (e)
        (setf (sr-state rec) :error
              (sr-enabled rec) nil
              (sr-error rec) (princ-to-string e))
        (error e)))))

(defun disable-symbol! (id)
  (let ((rec (symbol-get id)))
    (unless rec
      (error "unknown symbol ~A" id))
    (when (sr-enabled rec)
      (%call-hook rec :deactivate)
      (setf (sr-enabled rec) nil
            (sr-state rec) :loaded)
      (when (and (member :nn-backend (sr-capabilities rec) :test #'eq)
                 *active-nn-backend*
                 (equal (nn-backend-id *active-nn-backend*) id))
        ;; fall back to cpu-nn if present
        (let ((cpu (symbol-get +cpu-nn-id+)))
          (if (and cpu (not (equal id +cpu-nn-id+)))
              (enable-symbol! +cpu-nn-id+ :force t)
              (set-nn-backend! (make-cpu-nn-backend))))))
    (symbol-info id)))
