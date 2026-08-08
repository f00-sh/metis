(:metis-symbol-pack 1
 :id "slang-en-lite"
 :name "English Slang (lite)"
 :version "1.0.0"
 :description "Dual-facet slang register stacked on core English (Use+About)"
 :license "MIT"
 :kind :knowledge
 :weights-policy :reproducible-from-data
 :repro-level :best-effort
 :sources
 ((:url "local://metis/slang-en-lite" :license "MIT" :date "2026"
   :content-hash "slang-en-lite-1" :note "informal register + about slang"))
 :build-recipe
 (:steps ("assert slang phrases and about facts") :tool "metis")
 :created "2026"
 :category :language
 :capabilities (:nl :language :slang :chitchat :concepts)
 :facets (:use :about)
 :depends-on ((:id "natural-language" :role :required)))
