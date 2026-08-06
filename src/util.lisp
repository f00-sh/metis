;;;; util.lisp
(in-package :metis)

;; ensure-list, with-gensyms, hash-table-keys/values from Alexandria (:use)

(defun variablep (x)
  "Logic variables: symbols starting with ? (e.g. ?x, ?WHO)."
  (and (symbolp x)
       (let ((n (symbol-name x)))
         (and (plusp (length n))
              (char= (char n 0) #\?)))))

(defun anonymous-var-p (x)
  (and (variablep x)
       (string= (symbol-name x) "?")))

(defun groundp (x)
  (cond ((variablep x) nil)
        ((consp x) (and (groundp (car x)) (groundp (cdr x))))
        (t t)))

(defun tree-find-if (pred tree)
  (cond ((funcall pred tree) (list tree))
        ((consp tree)
         (append (tree-find-if pred (car tree))
                 (tree-find-if pred (cdr tree))))
        (t nil)))

(defun collect-variables (tree)
  (remove-duplicates (tree-find-if #'variablep tree)))

(defun deep-copy (x)
  (cond ((consp x) (cons (deep-copy (car x)) (deep-copy (cdr x))))
        ((hash-table-p x)
         (let ((h (make-hash-table :test (hash-table-test x))))
           (maphash (lambda (k v) (setf (gethash k h) (deep-copy v))) x)
           h))
        (t x)))

(defun alist-get (key alist &optional default)
  (let ((pair (assoc key alist :test #'equal)))
    (if pair (cdr pair) default)))

(defun alist-set (key value alist)
  (let ((pair (assoc key alist :test #'equal)))
    (if pair
        (progn (setf (cdr pair) value) alist)
        (acons key value alist))))

(defun now-universal ()
  (get-universal-time))

(defun now-iso ()
  (multiple-value-bind (s m h d mo y)
      (decode-universal-time (get-universal-time) 0)
    (format nil "~4,'0D-~2,'0D-~2,'0DT~2,'0D:~2,'0D:~2,'0DZ"
            y mo d h m s)))

(defun stable-sxhash (x)
  "Structural hash for indexing facts (equal-based)."
  (sxhash (prin1-to-string x)))

(defun indent-string (n &optional (ch #\Space))
  (make-string n :initial-element ch))

(defun truncate-string (s len)
  (if (<= (length s) len)
      s
      (concatenate 'string (subseq s 0 (max 0 (- len 3))) "...")))

(defun truthy (x)
  (and x (not (eql x :fail)) (not (eql x :unknown))))
