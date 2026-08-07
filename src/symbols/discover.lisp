;;;; discover.lisp — find, load, install symbols from the filesystem
(in-package :metis.symbols)

(defun symbols-roots ()
  (or *symbols-roots*
      (list
       (merge-pathnames "symbols/"
                        (asdf:system-source-directory :metis))
       (merge-pathnames ".metis/symbols/"
                        (user-homedir-pathname)))))

(defun %manifest-path (root id)
  (merge-pathnames (format nil "~A/manifest.lisp" id)
                   (uiop:ensure-directory-pathname root)))

(defun %symbol-dir (root id)
  (merge-pathnames (format nil "~A/" id)
                   (uiop:ensure-directory-pathname root)))

(defun discover-symbols! (&key (roots nil))
  "Scan roots for symbols/*/manifest.lisp; register as :discovered if new."
  (let ((found nil))
    (dolist (root (or roots (symbols-roots)))
      (let ((root (probe-file root)))
        (when root
          (dolist (dir (directory (merge-pathnames "*/" root)))
            (let* ((id (car (last (pathname-directory dir))))
                   (manifest (merge-pathnames "manifest.lisp" dir)))
              (when (and id (probe-file manifest))
                (unless (symbol-get id)
                  (register-symbol!
                   :id id
                   :name id
                   :path dir
                   :meta (list :manifest (namestring manifest))
                   :hooks nil)
                  (setf (sr-state (symbol-get id)) :discovered))
                (push id found)))))))
    (remove-duplicates found :test #'equal)))

(defun load-symbol! (id &key (force nil))
  "Load symbol ID by evaluating its manifest.lisp (and optional symbol.lisp)."
  (let ((rec (symbol-get id)))
    (when (and rec (member (sr-state rec) '(:loaded :enabled)) (not force))
      (return-from load-symbol! (symbol-info id)))
    ;; find path
    (let ((path (or (and rec (sr-path rec))
                    (loop for root in (symbols-roots)
                          for d = (%symbol-dir root id)
                          when (probe-file (merge-pathnames "manifest.lisp" d))
                          return d))))
      (unless (and path (probe-file (merge-pathnames "manifest.lisp" path)))
        (error "cannot find manifest for symbol ~A" id))
      (let* ((manifest (merge-pathnames "manifest.lisp" path))
             (*package* (find-package :cl-user)))
        ;; Manifest should call metis.symbols:register-symbol! or metis:register-symbol
        (let ((*symbol-load-path* path))
          (declare (special *symbol-load-path*))
          (load manifest))
        (let ((rec2 (or (symbol-get id)
                        (error "manifest for ~A did not register the symbol" id))))
          (setf (sr-path rec2) path
                (sr-state rec2) (if (sr-enabled rec2) :enabled :loaded))
          ;; optional companion
          (let ((symfile (merge-pathnames "symbol.lisp" path)))
            (when (probe-file symfile)
              (let ((*symbol-load-path* path))
                (declare (special *symbol-load-path*))
                (load symfile))))
          (symbol-info id))))))

(defun %copy-tree (from to)
  "Recursive file tree copy (pure CL)."
  (let ((from (uiop:ensure-directory-pathname from))
        (to (uiop:ensure-directory-pathname to)))
    (ensure-directories-exist to)
    (dolist (p (directory (merge-pathnames "*.*" from)))
      (unless (uiop:directory-pathname-p p)
        (uiop:copy-file p (merge-pathnames (file-namestring p) to))))
    (dolist (d (directory (merge-pathnames "*/" from)))
      (let ((name (car (last (pathname-directory d)))))
        (when name
          (%copy-tree d (merge-pathnames (format nil "~A/" name) to)))))))

(defun install-symbol! (source &key (id nil) (enable nil))
  "Install a symbol from SOURCE (directory path) into the user symbols root.
   SOURCE must contain manifest.lisp. Returns symbol-info."
  (let* ((src (uiop:ensure-directory-pathname (truename source)))
         (manifest (merge-pathnames "manifest.lisp" src)))
    (unless (probe-file manifest)
      (error "install-symbol!: no manifest.lisp in ~A" src))
    (let* ((id (or id (car (last (pathname-directory src)))))
           (dest-root (merge-pathnames ".metis/symbols/"
                                       (user-homedir-pathname)))
           (dest (merge-pathnames (format nil "~A/" id) dest-root)))
      (ensure-directories-exist dest)
      (%copy-tree src dest)
      (register-symbol! :id id :path dest)
      (setf (sr-state (symbol-get id)) :discovered)
      (load-symbol! id :force t)
      (when enable (enable-symbol! id))
      (symbol-info id))))

(defun symbols-boot! ()
  "Discover, load built-ins, enable cpu-nn as default NN backend."
  (discover-symbols!)
  ;; Prefer in-tree built-ins
  (dolist (id (list +cpu-nn-id+ +gpu-nn-id+))
    (handler-case (load-symbol! id)
      (error (e)
        (format *error-output* "~&[symbols] load ~A: ~A~%" id e))))
  ;; Always enable CPU unless something else already active
  (handler-case (enable-symbol! +cpu-nn-id+ :force t)
    (error (e)
      (format *error-output* "~&[symbols] enable cpu-nn: ~A~%" e)
      (set-nn-backend! (make-cpu-nn-backend))))
  (list :symbols (symbol-list)
        :nn-backend (ignore-errors (nn-backend-status (active-nn-backend)))))
