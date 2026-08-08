(:metis-symbol-pack 1
 :id "dict-en-lite"
 :name "English Dictionary (lite)"
 :version "0.2.0"
 :description "Open English word definitions for About-facet freeform"
 :license "CC0-1.0"
 :kind :knowledge
 :weights-policy :reproducible-from-data
 :repro-level :best-effort
 :sources
 ((:url "https://example.invalid/dict-en-lite" :license "CC0-1.0" :date "2026"
   :content-hash "seed-dict-en-lite-0.2" :note "embedded seed entries"))
 :build-recipe
 (:steps ("assert word-def facts from pack.lisp") :tool "metis")
 :created "2026"
 :category :language
 :capabilities (:nl :concepts :language :dictionary)
 :facets (:use :about))
