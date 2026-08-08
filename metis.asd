;;;; metis.asd — Metis: symbolic mind + neural substrate + symbols (plugins)
(defsystem "metis"
  :description "Metis: cognitive architecture with pure-CL neural training, symbols plugins, optional GPU"
  :author "Glenda"
  :license "MIT"
  :version "4.5.0"
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
     (:module "nn"
      :serial t
      :components
      ((:file "package")
       (:file "tensor")
       (:file "ops")
       (:file "module")
       (:file "train")))
     (:module "symbols"
      :serial t
      :components
      ((:file "package")
       (:file "protocol")
       (:file "registry")
       (:file "trust")
       (:file "discover")
       (:file "cuda")
       (:file "capabilities")
       (:file "packs")
       (:file "runtime")
       (:file "seal")
       (:file "train")
       (:file "bridge")))
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
     (:file "epoch")
     (:file "session")
     (:file "nn/bridge")
     (:file "interface")
     (:file "tui")
     (:file "hybrid")
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
     (:file "further-paths")
     (:file "epoch")
     (:file "interface")
     (:file "nn")
     (:file "symbols")
     (:file "packs")
     (:file "seals")
     (:file "install")
     (:file "frontiers")
     (:file "hybrid"))))
  :perform (test-op (o c)
             (symbol-call :fiveam :run! :metis)
             (symbol-call :fiveam :run! :metis-production)
             (symbol-call :fiveam :run! :metis-further)
             (symbol-call :fiveam :run! :metis-epoch)
             (symbol-call :fiveam :run! :metis-iface)
             (symbol-call :fiveam :run! :metis-nn)
             (symbol-call :fiveam :run! :metis-symbols)
             (symbol-call :fiveam :run! :metis-packs)
             (symbol-call :fiveam :run! :metis-seals)
             (symbol-call :fiveam :run! :metis-install)
             (symbol-call :fiveam :run! :metis-frontiers)
             (symbol-call :fiveam :run! :metis-hybrid)))
