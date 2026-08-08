(:metis-symbol-pack 1
 :id "lang-en-conversation"
 :name "English Conversation (richer Use)"
 :version "1.0.0"
 :description "Stacked English dialogue pack — more Use-facet phrases on natural-language"
 :license "MIT"
 :kind :knowledge
 :weights-policy :reproducible-from-data
 :repro-level :best-effort
 :sources
 ((:url "local://metis/lang-en-conversation" :license "MIT" :date "2026"
   :content-hash "lang-en-conv-1" :note "nl-phrase banks for richer freeform"))
 :build-recipe
 (:steps ("assert nl-phrase facts" "depends on natural-language for core NL cap")
  :tool "metis")
 :created "2026"
 :category :language
 :capabilities (:nl :chitchat :language :conversation)
 :facets (:use :about)
 :depends-on ((:id "natural-language" :role :required)))
