;;;; bridge.lisp — Metis API for symbols + wire NN matmul to active backend
(in-package :metis)

;;; Re-export / wrap metis.symbols for the product surface.

(defun symbols-roots ()
  (metis.symbols:symbols-roots))

(defun discover-symbols! (&rest args)
  (apply #'metis.symbols:discover-symbols! args))

(defun symbol-list ()
  (metis.symbols:symbol-list))

(defun symbol-info (id)
  (metis.symbols:symbol-info id))

(defun symbol-list-info ()
  (mapcar #'metis.symbols:symbol-info (metis.symbols:symbol-list)))

(defun load-symbol! (id &rest args)
  (apply #'metis.symbols:load-symbol! id args))

(defun enable-symbol! (id &rest args)
  (apply #'metis.symbols:enable-symbol! id args))

(defun disable-symbol! (id)
  (metis.symbols:disable-symbol! id))

(defun install-symbol! (source &rest args)
  (apply #'metis.symbols:install-symbol! source args))

(defun nn-backend-status ()
  (metis.symbols:nn-backend-status (metis.symbols:active-nn-backend)))

(defun symbols-boot! ()
  (metis.symbols:symbols-boot!))

(defun install-symbol-tools (mind)
  (register-tool
   mind 'symbols-list
   (lambda () (symbol-list-info))
   :doc "List installed Metis symbols (plugins)"
   :safe t)
  (register-tool
   mind 'symbol-info
   (lambda (id) (or (symbol-info id) (list :error :unknown id)))
   :doc "Show symbol metadata"
   :schema '(id)
   :safe t)
  (register-tool
   mind 'symbol-enable
   (lambda (id) (enable-symbol! id))
   :doc "Enable a symbol (nn-backend symbols switch compute path)"
   :schema '(id)
   :safe t)
  (register-tool
   mind 'symbol-disable
   (lambda (id) (disable-symbol! id))
   :doc "Disable a symbol"
   :schema '(id)
   :safe t)
  (register-tool
   mind 'symbol-install
   (lambda (path &optional id)
     (if id
         (install-symbol! path :id id)
         (install-symbol! path)))
   :doc "Install a symbol from a directory containing manifest.lisp"
   :schema '(path &optional id)
   :safe t)
  (register-tool
   mind 'nn-backend
   (lambda () (nn-backend-status))
   :doc "Active neural compute backend (cpu-nn or gpu-nn symbol)"
   :safe t)
  t)

(defun %iface-symbol-commands (text)
  (cond
    ((cl-ppcre:scan "(?i)^/symbols(?:\\s+list)?\\s*$" text)
     (list :symbols-list))
    ((cl-ppcre:scan "(?i)^/symbols\\s+info\\s+(\\S+)\\s*$" text)
     (cl-ppcre:register-groups-bind (id)
         ("(?i)^/symbols\\s+info\\s+(\\S+)\\s*$" text)
       (list :symbol-info id)))
    ((cl-ppcre:scan "(?i)^/symbols\\s+enable\\s+(\\S+)\\s*$" text)
     (cl-ppcre:register-groups-bind (id)
         ("(?i)^/symbols\\s+enable\\s+(\\S+)\\s*$" text)
       (list :symbol-enable id)))
    ((cl-ppcre:scan "(?i)^/symbols\\s+disable\\s+(\\S+)\\s*$" text)
     (cl-ppcre:register-groups-bind (id)
         ("(?i)^/symbols\\s+disable\\s+(\\S+)\\s*$" text)
       (list :symbol-disable id)))
    ((cl-ppcre:scan "(?i)^/symbols\\s+install\\s+(\\S+)(?:\\s+(\\S+))?\\s*$" text)
     (cl-ppcre:register-groups-bind (path id)
         ("(?i)^/symbols\\s+install\\s+(\\S+)(?:\\s+(\\S+))?\\s*$" text)
       (list :symbol-install path id)))
    ((cl-ppcre:scan "(?i)^/symbols\\s+backend\\s*$" text)
     (list :nn-backend))
    (t nil)))
