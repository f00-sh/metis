(:metis-symbol-pack 1
 :id "natural-language"
 :name "Natural Language"
 :version "1.1.0"
 :description "English dual-facet core — Use (dialogue) + About (metalanguage)"
 :license "MIT"
 :kind :knowledge
 :weights-policy :reproducible-from-data
 :repro-level :best-effort
 :sources
 ((:url "local://metis/nl" :license "MIT" :date "2026"
   :content-hash "nl-core-1.1" :note "chitchat + concepts + creative use"))
 :build-recipe
 (:steps ("assert facts/rules from pack.lisp") :tool "metis")
 :created "2026"
 :category :language
 :capabilities (:nl :chitchat :concepts :language)
 :facets (:use :about))
