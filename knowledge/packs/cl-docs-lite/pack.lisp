(:metis-pack 1 :facts
 ((metis::cl-fn "cons" "construct a cons cell")
  (metis::cl-fn "car" "first element of a list")
  (metis::cl-fn "cdr" "rest of a list")
  (metis::cl-fn "defun" "define a named function")
  (metis::cl-concept "REPL" "read-eval-print loop"))
 :rules common-lisp:nil :corpus-inline
 ("CONS constructs pairs." "DEFUN defines functions."
  "The REPL reads, evaluates, prints."))
