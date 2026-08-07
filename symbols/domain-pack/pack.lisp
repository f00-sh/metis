;;;; pack.lisp — domain facts/rules for domain-pack symbol
;;;; Loaded by metis::domain-pack-load — not evaluated as a top-level system file.
((facts
  (domain-pack-loaded metis-frontier)
  (species dolphin mammal)
  (species eagle bird)
  (habitat dolphin ocean)
  (habitat eagle sky)
  (tool-use dolphin sonar)
  (tool-use eagle vision))
 (rules
  ((mammal-swims ?x) ((species ?x mammal) (habitat ?x ocean)))
  ((bird-flies ?x) ((species ?x bird) (habitat ?x sky)))))
