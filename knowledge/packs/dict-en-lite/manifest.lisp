(:METIS-SYMBOL-PACK 1 :ID "dict-en-lite" :NAME "English Dictionary (lite)"
 :VERSION "0.1.0" :DESCRIPTION "Tiny open dictionary seed" :LICENSE "CC0-1.0"
 :KIND :KNOWLEDGE :WEIGHTS-POLICY :REPRODUCIBLE-FROM-DATA :REPRO-LEVEL
 :BEST-EFFORT :SOURCES
 ((:URL "https://example.invalid/dict-en-lite" :LICENSE "CC0-1.0" :DATE "2026"
   :CONTENT-HASH "seed-dict-en-lite" :NOTE "embedded seed entries"))
 :BUILD-RECIPE
 (:STEPS
  ("assert facts/rules from pack.lisp" "optional: load ckpt if included") :TOOL
  "metis")
 :CREATED "2026")
