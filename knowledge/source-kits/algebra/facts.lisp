(:FACTS
 ((METIS::DOMAIN-DEF "algebra" "variable"
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
  (METIS::DEPENDS-ON METIS::ALGEBRA METIS::MATH)))
