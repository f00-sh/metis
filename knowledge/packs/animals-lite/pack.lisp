(:metis-pack 1 :facts
 ((metis::animal "dolphin" "mammal") (metis::animal "eagle" "bird")
  (metis::animal "salmon" "fish") (metis::habitat "dolphin" "ocean")
  (metis::habitat "eagle" "sky") (metis::habitat "salmon" "river"))
 :rules common-lisp:nil :corpus-inline
 ("Dolphins are ocean mammals." "Eagles are birds of prey."
  "Salmon spawn in rivers."))
