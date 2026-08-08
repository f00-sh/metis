(:FACTS
 ((METIS::DOMAIN-DEF "trigonometry" "sine"
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
  (METIS::DEPENDS-ON METIS::TRIGONOMETRY METIS::ALGEBRA)))
