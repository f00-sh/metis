(:METIS-SYMBOL-PACK 1 :ID "math" :NAME "Mathematics" :VERSION "1.0.0"
 :DESCRIPTION "Arithmetic & linear algebra with worked steps (PEMDAS)" :LICENSE
 "MIT" :KIND :KNOWLEDGE :WEIGHTS-POLICY :REPRODUCIBLE-FROM-DATA :REPRO-LEVEL
 :BEST-EFFORT :SOURCES
 ((:URL "local://metis/math" :LICENSE "MIT" :DATE "2026" :CONTENT-HASH
   "math-engine" :NOTE "engine: eval-math-expression"))
 :BUILD-RECIPE
 (:STEPS
  ("assert facts/rules from pack.lisp" "optional: load ckpt if included") :TOOL
  "metis")
 :CREATED "2026" :CATEGORY :REASONING :CAPABILITIES (:MATH :REASONING))
