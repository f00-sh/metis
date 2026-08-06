;;;; frames.lisp — frame system with inheritance and demons
(in-package :metis)

(defstruct (frame (:conc-name fr-))
  name
  (slots (make-hash-table :test #'eq))  ; slot-name -> slot-struct
  (ako nil)                              ; a-kind-of parents (list)
  (meta nil)
  (created 0))

(defstruct (slot (:conc-name sl-))
  name
  value
  (default nil)
  (if-needed nil)   ; function (frame slot) -> value
  (if-added nil)    ; function (frame slot old new)
  (if-removed nil)
  (cardinality :single) ; :single | :multiple
  (source nil))

(defstruct (frame-system (:conc-name fs-))
  (frames (make-hash-table :test #'eq))
  (lock (bt:make-lock "metis-frames")))

(defun make-empty-frame-system ()
  (make-frame-system))

(defun fs-get-frame (fs name)
  (gethash name (fs-frames fs)))

(defun fs-ensure-frame (fs name)
  (or (fs-get-frame fs name)
      (let ((f (make-frame :name name :created (now-universal))))
        (setf (gethash name (fs-frames fs)) f)
        f)))

(defun fs-all-frames (fs)
  (hash-table-values (fs-frames fs)))

(defun %slot-of (frame slot-name)
  (gethash slot-name (fr-slots frame)))

(defun %ensure-slot (frame slot-name)
  (or (%slot-of frame slot-name)
      (let ((s (make-slot :name slot-name :value :unbound)))
        (setf (gethash slot-name (fr-slots frame)) s)
        s)))

(defun frame-ancestors (fs frame)
  "DFS inheritance chain including self."
  (let ((seen (make-hash-table :test #'eq))
        (out nil))
    (labels ((walk (f)
               (when (and f (not (gethash (fr-name f) seen)))
                 (setf (gethash (fr-name f) seen) t)
                 (push f out)
                 (dolist (p (fr-ako f))
                   (walk (fs-get-frame fs p))))))
      (walk frame)
      (nreverse out))))

(defun fs-get (fs frame-name slot-name &optional default)
  "Get slot with inheritance and if-needed demons."
  (let ((frame (fs-get-frame fs frame-name)))
    (unless frame
      (return-from fs-get default))
    (dolist (f (frame-ancestors fs frame) default)
      (let ((slot (%slot-of f slot-name)))
        (when slot
          (cond ((not (eq (sl-value slot) :unbound))
                 (return-from fs-get (sl-value slot)))
                ((sl-if-needed slot)
                 (let ((v (funcall (sl-if-needed slot) f slot)))
                   (when v
                     (setf (sl-value slot) v)
                     (return-from fs-get v))))
                ((sl-default slot)
                 (return-from fs-get (sl-default slot)))))))))

(defun fs-set (fs frame-name slot-name value &key source)
  (let* ((frame (fs-ensure-frame fs frame-name))
         (slot (%ensure-slot frame slot-name))
         (old (sl-value slot)))
    (setf (sl-value slot) value)
    (when source (setf (sl-source slot) source))
    (when (sl-if-added slot)
      (funcall (sl-if-added slot) frame slot old value))
    value))

(defun fs-ako (fs frame-name parents)
  (let ((frame (fs-ensure-frame fs frame-name)))
    (setf (fr-ako frame) (ensure-list parents))
    frame))

(defun fs-deframe (fs name &rest slot-specs)
  "Define/update a frame.
   Slot specs: (slot-name value) or
   (slot-name :value v :default d :if-needed fn :if-added fn :ako parents)"
  (let ((frame (fs-ensure-frame fs name))
        (ako nil))
    (loop for spec in slot-specs do
      (cond
        ((and (consp spec) (member (car spec) '(:ako :a-kind-of :is-a)))
         (setf ako (ensure-list (second spec))))
        ((and (consp spec) (keywordp (car spec)))
         nil)
        ((and (consp spec) (= (length spec) 2)
              (not (keywordp (second spec))))
         (fs-set fs name (first spec) (second spec) :source :deframe))
        ((consp spec)
         (let* ((sname (first spec))
                (plist (rest spec))
                (slot (%ensure-slot frame sname)))
           (when (getf plist :value)
             (setf (sl-value slot) (getf plist :value)))
           (when (member :default plist)
             (setf (sl-default slot) (getf plist :default)))
           (when (getf plist :if-needed)
             (setf (sl-if-needed slot) (getf plist :if-needed)))
           (when (getf plist :if-added)
             (setf (sl-if-added slot) (getf plist :if-added)))
           (when (getf plist :if-removed)
             (setf (sl-if-removed slot) (getf plist :if-removed)))))
        (t nil)))
    (when ako (setf (fr-ako frame) ako))
    ;; also accept :ako at top of specs as plist style was mixed
    frame))

(defun fs-slots-plist (fs frame-name)
  (let ((frame (fs-get-frame fs frame-name)))
    (when frame
      (loop for s being the hash-values of (fr-slots frame)
            collect (list (sl-name s)
                          (if (eq (sl-value s) :unbound)
                              :unbound
                              (sl-value s)))))))

(defun fs-snapshot (fs)
  (loop for f in (fs-all-frames fs)
        collect (list :name (fr-name f)
                      :ako (fr-ako f)
                      :slots (fs-slots-plist fs (fr-name f))
                      :meta (fr-meta f))))

(defun fs-restore (fs snapshot)
  (clrhash (fs-frames fs))
  (dolist (entry snapshot)
    (let ((name (getf entry :name)))
      (fs-ensure-frame fs name)
      (when (getf entry :ako)
        (fs-ako fs name (getf entry :ako)))
      (dolist (sp (getf entry :slots))
        (unless (eq (second sp) :unbound)
          (fs-set fs name (first sp) (second sp) :source :restore)))
      (when (getf entry :meta)
        (setf (fr-meta (fs-get-frame fs name)) (getf entry :meta)))))
  fs)

(defun fs-describe (fs frame-name)
  (let ((f (fs-get-frame fs frame-name)))
    (when f
      (list :frame (fr-name f)
            :ako (fr-ako f)
            :own (fs-slots-plist fs frame-name)
            :inherited
            (loop for anc in (cdr (frame-ancestors fs f))
                  append (fs-slots-plist fs (fr-name anc)))))))
