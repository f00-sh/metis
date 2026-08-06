;;;; metis.asd — Metis 2.0 ARC cognitive architecture
(defsystem "metis"
  :description "Metis 2.0: Autopoietic Reflexive Continuum — RETE, durable LMDB, formal TMS, multi-agent CL intelligence"
  :author "Glenda"
  :license "MIT"
  :version "2.0.0"
  :depends-on ("alexandria"
               "bordeaux-threads"
               "cl-ppcre"
               "drakma"
               "yason"
               "uiop"
               "closer-mop"
               "hunchentoot"
               "lmdb")
  :serial t
  :components
  ((:module "src"
    :serial t
    :components
    ((:file "package")
     (:file "version")
     (:file "conditions")
     (:file "util")
     (:file "log")
     (:file "config")
     (:file "unifier")
     (:file "kb")
     (:file "frames")
     (:file "forward")
     (:file "rete")
     (:file "backward")
     (:file "planner")
     (:file "htn")
     (:file "constraint")
     (:file "memory")
     (:file "belief")
     (:file "tms")
     (:file "tms-formal")
     (:file "tools")
     (:file "llm")
     (:file "security")
     (:file "durable")
     (:file "introspection")
     (:file "meta")
     (:file "learn")
     (:file "explain")
     (:file "language")
     (:file "blackboard")
     (:file "tx")
     (:file "agent")
     (:file "society")
     (:file "daemon")
     (:file "api")
     (:file "arc")
     (:file "world")
     (:file "repl")))
   (:module "knowledge"
    :serial t
    :components
    ((:file "bootstrap")
     (:file "domains")
     (:file "large-corpus"))))
  :in-order-to ((test-op (test-op "metis/tests"))))

(defsystem "metis/tests"
  :depends-on ("metis" "fiveam")
  :components
  ((:module "tests"
    :serial t
    :components
    ((:file "suite")
     (:file "production")
     (:file "bench")
     (:file "further-paths"))))
  :perform (test-op (o c)
             (symbol-call :fiveam :run! :metis)
             (symbol-call :fiveam :run! :metis-production)
             (symbol-call :fiveam :run! :metis-further)))
