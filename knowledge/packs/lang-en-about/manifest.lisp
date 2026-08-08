(:metis-symbol-pack 1
 :id "lang-en-about"
 :name "English About (metalanguage)"
 :version "1.0.0"
 :description "About-facet pack — grammar, parts of speech, English metalanguage"
 :license "MIT"
 :kind :knowledge
 :weights-policy :reproducible-from-data
 :repro-level :best-effort
 :sources
 ((:url "local://metis/lang-en-about" :license "MIT" :date "2026"
   :content-hash "lang-en-about-1" :note "nl-concept + word-def metalanguage"))
 :build-recipe
 (:steps ("assert nl-concept and word-def facts") :tool "metis")
 :created "2026"
 :category :language
 :capabilities (:nl :concepts :language :about)
 :facets (:use :about)
 :depends-on ((:id "natural-language" :role :required)))
