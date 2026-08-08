(:metis-pack 1 :facts
 ((metis::word-def "cat" "a small domesticated carnivorous mammal")
  (metis::word-def "dog" "a domesticated carnivorous mammal")
  (metis::word-def "metis" "cunning intelligence; Greek goddess of wisdom")
  (metis::word-def "symbol" "a knowledge pack unit in Metis"))
 :rules (((metis::wordp metis::?w) ((metis::word-def metis::?w metis::?d))))
 :corpus-inline
 ("cat: a small domesticated carnivorous mammal"
  "dog: a domesticated carnivorous mammal" "metis: cunning intelligence"))
