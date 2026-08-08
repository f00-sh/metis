;;;; kinship domain pack — facts, rules, couple-templates
((facts
  (domain-pack-loaded kinship)
  (parent alice bob)
  (parent bob carol)
  (male bob)
  (female alice)
  (female carol))
 (rules
  ((grandparent ?x ?z) ((parent ?x ?y) (parent ?y ?z)))
  ((father ?x ?y) ((parent ?x ?y) (male ?x))))
 (couple-templates
  (parent ?x ?y)
  (grandparent ?x ?y)
  (father ?x ?y)
  (male ?x)
  (female ?x)
  (kinship-allowed ?x)))
