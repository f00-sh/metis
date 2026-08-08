(:FACTS
 ((METIS::DOMAIN-DEF "math" "natural-number"
   "positive whole counting number 1,2,3,...")
  (METIS::DOMAIN-DEF "math" "integer"
   "whole number that may be positive, negative, or zero")
  (METIS::DOMAIN-DEF "math" "rational-number"
   "number expressible as ratio of integers p/q with q≠0")
  (METIS::DOMAIN-DEF "math" "real-number" "number on the continuous real line")
  (METIS::DOMAIN-DEF "math" "pemdas"
   "order of operations: parentheses, exponents, multiply/divide, add/subtract")
  (METIS::DOMAIN-IDENTITY "math" "additive-identity" "a + 0 = a")
  (METIS::DOMAIN-IDENTITY "math" "multiplicative-identity" "a * 1 = a")
  (METIS::DOMAIN-IDENTITY "math" "commutative-add" "a + b = b + a")
  (METIS::DOMAIN-IDENTITY "math" "commutative-mul" "a * b = b * a")
  (METIS::DOMAIN-IDENTITY "math" "distributive" "a*(b+c) = a*b + a*c")
  (METIS::CAPABILITY METIS::MATH "basic arithmetic and number sense")
  (METIS::CAPABILITY METIS::PEMDAS "order of operations")))
