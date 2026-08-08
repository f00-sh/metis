(:metis-pack 1
 :facts
 ((capability natural-language "english freeform surface dual-facet use+about")
  (capability chitchat "greetings identity creative play")
  (nl-concept "noun" "A noun names a person, place, thing, or idea (cat, Metis, freedom).")
  (nl-concept "verb" "A verb expresses action or state (run, is, load).")
  (nl-concept "adjective" "An adjective modifies a noun (quick, sealed, dual-facet).")
  (nl-concept "adverb" "An adverb modifies a verb, adjective, or other adverb (quickly, very).")
  (nl-concept "pronoun" "A pronoun stands in for a noun (I, you, they, it).")
  (nl-concept "sentence" "A sentence is a complete thought, usually subject + predicate.")
  (nl-concept "english" "English is a West Germanic language. Metis language packs expose Use (speak/read) and About (metalanguage) facets.")
  (nl-concept "language" "A language is a structured system of communication. In Metis, language symbols are dual-facet packs, not kitchen-sink weights.")
  (nl-concept "slang" "Slang is informal, group-specific language. Load slang-en-lite for a dual-facet slang register stacked on core English.")
  (word-def "symbol" "in Metis: a sealed knowledge pack you load on demand")
  (word-def "facet" "a dual surface of a symbol: use/about for language, process/knowledge for math")
  (word-def "metis" "cunning intelligence; this hybrid Common Lisp cognitive architecture")
  (nl-phrase "sing" "♪ Another verse from the natural-language pack: load what you need, leave the rest asleep. ♪")
  (nl-phrase "joke" "Pack joke: Why did the sealed symbol blush? Someone tried to read its body.mse as plaintext."))
 :rules
 (((wordp ?w) ((word-def ?w ?d))))
 :corpus-inline
 ("Natural language = Use (dialogue) + About (metalanguage)."
  "Stack richer packs: lang-en-conversation, dict-en-lite, slang-en-lite, lang-en-about."
  "Ask: sing a song, tell a joke, what is a noun, define symbol."))
