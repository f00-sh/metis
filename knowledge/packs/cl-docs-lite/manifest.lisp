(:METIS-SYMBOL-PACK 1 :ID "cl-docs-lite" :NAME "Common Lisp Docs (lite)"
 :VERSION "0.1.0" :DESCRIPTION "Tiny CL reference seed (not full HyperSpec)"
 :LICENSE "MIT" :KIND :KNOWLEDGE :WEIGHTS-POLICY :REPRODUCIBLE-FROM-DATA
 :REPRO-LEVEL :BEST-EFFORT :SOURCES
 ((:URL "https://www.lispworks.com/documentation/HyperSpec/Front/" :LICENSE
   "see-vendor" :DATE "2026" :CONTENT-HASH "seed-cl-docs-lite" :NOTE
   "educational subset only; not full HyperSpec copy"))
 :BUILD-RECIPE
 (:STEPS
  ("assert facts/rules from pack.lisp" "optional: load ckpt if included") :TOOL
  "metis")
 :CREATED "2026")
