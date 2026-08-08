(:METIS-SYMBOL-PACK 1 :ID "local-user" :NAME "Local User Knowledge" :VERSION
 "1.0.0" :DESCRIPTION
 "What you taught Metis (tell/context/train) — live, not frozen" :LICENSE
 "user" :KIND :KNOWLEDGE :WEIGHTS-POLICY :REPRODUCIBLE-FROM-DATA :REPRO-LEVEL
 :BEST-EFFORT :SOURCES
 ((:URL "local://user-session" :LICENSE "user" :DATE "2026" :CONTENT-HASH
   "live" :NOTE "session + mind facts with user support"))
 :BUILD-RECIPE
 (:STEPS
  ("assert facts/rules from pack.lisp" "optional: load ckpt if included") :TOOL
  "metis")
 :CREATED "2026" :CATEGORY :LOCAL :CAPABILITIES (:LOCAL-USER :USER-LEARNED)
 :VIRTUAL T :MUTABLE T)
