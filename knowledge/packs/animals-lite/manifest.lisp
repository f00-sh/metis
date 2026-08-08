(:METIS-SYMBOL-PACK 1 :ID "animals-lite" :NAME "Animals (lite)" :VERSION
 "0.1.0" :DESCRIPTION "Sample animal encyclopedia seed" :LICENSE "CC0-1.0"
 :KIND :KNOWLEDGE :WEIGHTS-POLICY :REPRODUCIBLE-FROM-DATA :REPRO-LEVEL
 :BEST-EFFORT :SOURCES
 ((:URL "https://example.invalid/animals-lite" :LICENSE "CC0-1.0" :DATE "2026"
   :CONTENT-HASH "seed-animals-lite" :NOTE "embedded seed"))
 :BUILD-RECIPE
 (:STEPS
  ("assert facts/rules from pack.lisp" "optional: load ckpt if included") :TOOL
  "metis")
 :CREATED "2026")
