(:FACTS
 ((METIS::SYMBOL-TRAINED "trigonometry" "1.0.0" 8 8)
  (METIS::DOMAIN-DEF "trigonometry" "sine"
   "opposite/hypotenuse in a right triangle; also unit-circle y-coordinate")
  (METIS::DOMAIN-DEF "trigonometry" "cosine"
   "adjacent/hypotenuse; unit-circle x-coordinate")
  (METIS::DOMAIN-DEF "trigonometry" "tangent" "sine/cosine; opposite/adjacent")
  (METIS::DOMAIN-IDENTITY "trigonometry" "pythagorean-trig"
   "sin^2 θ + cos^2 θ = 1")
  (METIS::DOMAIN-IDENTITY "trigonometry" "angle-sum-sin"
   "sin(a+b) = sin a cos b + cos a sin b")
  (METIS::DOMAIN-IDENTITY "trigonometry" "angle-sum-cos"
   "cos(a+b) = cos a cos b - sin a sin b")
  (METIS::DOMAIN-IDENTITY "trigonometry" "double-angle-sin"
   "sin(2θ) = 2 sin θ cos θ")
  (METIS::CAPABILITY METIS::TRIGONOMETRY
   "trigonometric functions and identities")
  (METIS::DEPENDS-ON METIS::TRIGONOMETRY METIS::GEOMETRY)
  (METIS::DEPENDS-ON METIS::TRIGONOMETRY METIS::ALGEBRA)
  (METIS::DOMAIN-DEF "trigonometry" "sine"
   "opposite over hypotenuse in a right triangle")
  (METIS::DOMAIN-DEF "trigonometry" "cosine" "adjacent over hypotenuse")
  (METIS::DOMAIN-DEF "trigonometry" "tangent" "sine over cosine")
  (METIS::DOMAIN-DEF "trigonometry" "Pythagorean identity"
   "sin^2 θ + cos^2 θ = 1")
  (METIS::DOMAIN-DEF "trigonometry" "angle sum sine"
   "sin(a+b) = sin a cos b + cos a sin b")
  (METIS::DOMAIN-DEF "trigonometry" "angle sum cosine"
   "cos(a+b) = cos a cos b - sin a sin b")
  (METIS::DOMAIN-DEF "trigonometry" "double angle sine"
   "sin(2θ) = 2 sin θ cos θ")
  (METIS::DOMAIN-DEF "trigonometry" "Source orientation"
   "OpenStax Algebra and Trigonometry (CC-BY)."))
 :RULES COMMON-LISP:NIL :EXTRACTED 8 :CORPUS-LINES 8)
