;;;; discover.lisp — find, load, install symbols (local / git / URL + trust)
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
    (let ((path (or (and rec (sr-path rec))
                    (loop for root in (symbols-roots)
                          for d = (%symbol-dir root id)
                          when (probe-file (merge-pathnames "manifest.lisp" d))
                          return d))))
      (unless (and path (probe-file (merge-pathnames "manifest.lisp" path)))
        (error "cannot find manifest for symbol ~A" id))
      (let* ((manifest (merge-pathnames "manifest.lisp" path))
             (*package* (find-package :cl-user)))
        (let ((*symbol-load-path* path))
          (declare (special *symbol-load-path*))
          (load manifest))
        (let ((rec2 (or (symbol-get id)
                        (error "manifest for ~A did not register the symbol" id))))
          (setf (sr-path rec2) path
                (sr-state rec2) (if (sr-enabled rec2) :enabled :loaded))
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

(defun %url-p (s)
  (and (stringp s)
       (or (eql 0 (search "http://" s))
           (eql 0 (search "https://" s))
           (eql 0 (search "file://" s))
           (eql 0 (search "git@" s))
           (eql 0 (search "git://" s))
           (search ".git" s))))

(defun %git-url-p (s)
  (and (stringp s)
       (or (eql 0 (search "git@" s))
           (eql 0 (search "git://" s))
           (and (or (eql 0 (search "http://" s))
                    (eql 0 (search "https://" s)))
                (or (search ".git" s)
                    (search "git+" s))))))

(defun %fetch-remote-to-tmpdir (source)
  "Fetch SOURCE (git URL, http(s) archive path, or file://) into a temp dir.
   Returns directory pathname containing manifest.lisp."
  (let* ((tmp (uiop:ensure-directory-pathname
               (merge-pathnames
                (format nil "metis-sym-fetch-~A/" (get-universal-time))
                (uiop:temporary-directory)))))
    (ensure-directories-exist tmp)
    (cond
      ((eql 0 (search "file://" source))
       (let* ((path (subseq source 7))
              (src (uiop:ensure-directory-pathname (truename path))))
         (%copy-tree src tmp)
         tmp))
      ((%git-url-p source)
       (uiop:run-program
        (list "git" "clone" "--depth" "1" source (namestring tmp))
        :output t :error-output t)
       ;; if clone put files in tmp/name/, find manifest
       (if (probe-file (merge-pathnames "manifest.lisp" tmp))
           tmp
           (let ((sub (first (directory (merge-pathnames "*/" tmp)))))
             (or sub tmp))))
      ((or (eql 0 (search "http://" source))
           (eql 0 (search "https://" source)))
       ;; expect a directory listing style: download tar/zip or raw tree via curl of a tarball
       ;; For tests we support URL to a .tar.gz or a directory served as tarball.
       (let ((archive (merge-pathnames "pkg.tar.gz" tmp)))
         (uiop:run-program
          (list "curl" "-fsSL" "-o" (namestring archive) source)
          :output t :error-output t)
         (uiop:run-program
          (list "tar" "-xzf" (namestring archive) "-C" (namestring tmp))
          :output t :error-output t)
         (if (probe-file (merge-pathnames "manifest.lisp" tmp))
             tmp
             (or (first (directory (merge-pathnames "*/" tmp))) tmp))))
      (t (error "unsupported remote source ~A" source)))))

(defun install-symbol! (source &key (id nil) (enable nil)
                                 (require-signature nil)
                                 (trust-remote t))
  "Install a symbol from SOURCE into the user symbols root.

   SOURCE may be:
   - local directory path
   - file:// path
   - git URL (git clone --depth 1)
   - http(s) URL to a .tar.gz package

   Remote sources require a valid symbol.sig when TRUST-REMOTE is true
   (default). Local directory installs require signature only when
   REQUIRE-SIGNATURE is true."
  (let* ((remote (and (stringp source) (%url-p source)))
         (require (if remote
                      (or trust-remote *symbol-trust-strict*)
                      require-signature))
         (src-dir
          (cond
            (remote (%fetch-remote-to-tmpdir source))
            (t (uiop:ensure-directory-pathname (truename source))))))
    (unless (probe-file (merge-pathnames "manifest.lisp" src-dir))
      (error "install-symbol!: no manifest.lisp in ~A" src-dir))
    (when require
      (verify-symbol-package src-dir :require t))
    (unless require
      ;; still record unsigned local installs
      (ignore-errors (verify-symbol-package src-dir :require nil)))
    (let* ((id (or id (car (last (pathname-directory src-dir)))))
           (dest-root (merge-pathnames ".metis/symbols/"
                                       (user-homedir-pathname)))
           (dest (merge-pathnames (format nil "~A/" id) dest-root)))
      (ensure-directories-exist dest)
      (%copy-tree src-dir dest)
      (register-symbol! :id id :path dest
                        :meta (list :source source
                                    :trusted (and require t)))
      (setf (sr-state (symbol-get id)) :discovered)
      (load-symbol! id :force t)
      (when enable (enable-symbol! id))
      (symbol-info id))))

(defparameter *builtin-symbol-ids*
  '("cpu-nn" "gpu-nn" "chat-ui" "image-ingest" "domain-pack" "curriculum"))

(defun symbols-boot! ()
  "Discover, load built-ins + category symbols, enable cpu-nn as default NN backend."
  (discover-symbols!)
  (dolist (id *builtin-symbol-ids*)
    (handler-case (load-symbol! id)
      (error (e)
        (format *error-output* "~&[symbols] load ~A: ~A~%" id e))))
  ;; also load any other discovered ids
  (dolist (id (discover-symbols!))
    (unless (member id *builtin-symbol-ids* :test #'string=)
      (handler-case (load-symbol! id)
        (error (e)
          (format *error-output* "~&[symbols] load ~A: ~A~%" id e)))))
  (handler-case (enable-symbol! +cpu-nn-id+ :force t)
    (error (e)
      (format *error-output* "~&[symbols] enable cpu-nn: ~A~%" e)
      (set-nn-backend! (make-cpu-nn-backend))))
  (list :symbols (symbol-list)
        :nn-backend (ignore-errors (nn-backend-status (active-nn-backend)))))
