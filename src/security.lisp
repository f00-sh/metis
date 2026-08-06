;;;; security.lisp — sandbox policy for eval, tools, and self-mod
(in-package :metis)

(defparameter *forbidden-eval-ops*
  '(uiop:run-program uiop:launch-program sb-ext:run-program
    delete-file rename-file ensure-directories-exist
    open with-open-file load compile-file
    sb-posix:chdir sb-posix:setuid
    quit sb-ext:quit sb-ext:exit uiop:quit)
  "Symbols disallowed inside sandboxed eval by default.")

(defparameter *allowed-eval-packages*
  '(:metis :cl :common-lisp :keyword :alexandria)
  "Packages whose symbols may appear in sandboxed forms.")

(defun form-symbols (form)
  (let ((out nil))
    (labels ((walk (x)
               (cond ((symbolp x) (push x out))
                     ((consp x) (walk (car x)) (walk (cdr x))))))
      (walk form)
      (remove-duplicates out))))

(defun sandbox-check-form (form &key (strict t))
  "Return (values ok reasons). OK means form may be evaluated under policy."
  (let ((reasons nil)
        (syms (form-symbols form)))
    (dolist (s syms)
      (when (member s *forbidden-eval-ops* :test #'eq)
        (push (format nil "forbidden operator ~S" s) reasons))
      (when strict
        (let ((pkg (symbol-package s)))
          (when (and pkg
                     (not (member (intern (package-name pkg) :keyword)
                                  *allowed-eval-packages*)))
            ;; allow local metis gensyms / uninterned
            (unless (or (null pkg)
                        (eq pkg (find-package :metis))
                        (eq pkg (find-package :cl))
                        (eq pkg (find-package :keyword)))
              (let ((name (package-name pkg)))
                (unless (member name '("METIS" "COMMON-LISP" "KEYWORD" "ALEXANDRIA")
                                :test #'string-equal)
                  (push (format nil "package not allowed: ~A (~S)" name s)
                        reasons))))))))
    (values (null reasons) (nreverse reasons))))

(defun sandboxed-eval (form &key (strict t))
  "Evaluate FORM only if sandbox-check-form passes."
  (unless (get-config :safe-eval t)
    (return-from sandboxed-eval
      (let ((*package* (find-package :metis)))
        (eval form))))
  (multiple-value-bind (ok reasons)
      (sandbox-check-form form :strict strict)
    (unless ok
      (error 'metis-error
             :message (format nil "sandbox rejected form: ~{~A~^; ~}" reasons)))
    (let ((*package* (find-package :metis)))
      (eval form))))

(defun security-profile ()
  (list :safe-eval (get-config :safe-eval t)
        :shell-enabled (get-config :tool-shell-enabled nil)
        :llm-enabled (llm-enabled-p)
        :forbidden-ops (length *forbidden-eval-ops*)
        :allowed-packages *allowed-eval-packages*))
