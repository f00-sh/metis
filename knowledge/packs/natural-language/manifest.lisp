(:METIS-SYMBOL-PACK 1 :ID "natural-language" :NAME "Natural Language" :VERSION
 "1.0.0" :DESCRIPTION "English chitchat, identity, concepts — freeform surface"
 :LICENSE "MIT" :KIND :KNOWLEDGE :WEIGHTS-POLICY :REPRODUCIBLE-FROM-DATA
 :REPRO-LEVEL :BEST-EFFORT :SOURCES
 ((:URL "local://metis/nl" :LICENSE "MIT" :DATE "2026" :CONTENT-HASH "nl-core"
   :NOTE "chitchat + concept lexicon"))
 :BUILD-RECIPE
 (:STEPS
  ("assert facts/rules from pack.lisp" "optional: load ckpt if included") :TOOL
  "metis")
 :CREATED "2026" :CATEGORY :LANGUAGE :CAPABILITIES
 (:NL :CHITCHAT :CONCEPTS :LANGUAGE))
