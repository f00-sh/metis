(:FACTS
 ((METIS::SYMBOL-TRAINED "algebra" "1.0.0" 3995145213 9 9)
  (METIS::DOMAIN-DEF "algebra" "variable"
   "symbol standing for an unknown or varying quantity")
  (METIS::DOMAIN-DEF "algebra" "polynomial"
   "sum of terms of the form a_i x^i with nonnegative integer powers")
  (METIS::DOMAIN-DEF "algebra" "linear-equation"
   "equation of degree one in the unknown")
  (METIS::DOMAIN-DEF "algebra" "quadratic-equation"
   "equation of degree two; ax^2+bx+c=0")
  (METIS::DOMAIN-IDENTITY "algebra" "difference-of-squares"
   "a^2 - b^2 = (a-b)(a+b)")
  (METIS::DOMAIN-IDENTITY "algebra" "perfect-square"
   "(a+b)^2 = a^2 + 2ab + b^2")
  (METIS::DOMAIN-IDENTITY "algebra" "quadratic-formula"
   "x = (-b ± sqrt(b^2-4ac))/(2a) for ax^2+bx+c=0")
  (METIS::DOMAIN-IDENTITY "algebra" "zero-product" "if ab=0 then a=0 or b=0")
  (METIS::CAPABILITY METIS::ALGEBRA "symbolic algebra")
  (METIS::DEPENDS-ON METIS::ALGEBRA METIS::MATH)
  (METIS::DOMAIN-DEF "algebra" "variable"
   "symbol standing for an unknown or varying quantity")
  (METIS::DOMAIN-DEF "algebra" "polynomial"
   "sum of terms a_i x^i with nonnegative integer powers")
  (METIS::DOMAIN-DEF "algebra" "linear-equation"
   "equation of degree one in the unknown")
  (METIS::DOMAIN-DEF "algebra" "quadratic-equation" "ax^2 + bx + c = 0")
  (METIS::DOMAIN-DEF "algebra" "difference of squares"
   "a^2 - b^2 = (a-b)(a+b)")
  (METIS::DOMAIN-DEF "algebra" "perfect square" "(a+b)^2 = a^2 + 2ab + b^2")
  (METIS::DOMAIN-DEF "algebra" "quadratic formula"
   "x = (-b ± sqrt(b^2-4ac))/(2a)")
  (METIS::DOMAIN-DEF "algebra" "zero product property"
   "if ab=0 then a=0 or b=0")
  (METIS::DOMAIN-DEF "algebra" "Source orientation"
   "OpenStax Algebra and Trigonometry / College Algebra (CC-BY)."))
 :RULES COMMON-LISP:NIL :EXTRACTED 9 :CORPUS-LINES 9)
