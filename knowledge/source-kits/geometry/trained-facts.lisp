(:FACTS
 ((METIS::SYMBOL-TRAINED "geometry" "1.0.0" 9 9)
  (METIS::DOMAIN-DEF "geometry" "point" "location in space with no size")
  (METIS::DOMAIN-DEF "geometry" "line"
   "straight one-dimensional figure extending without end")
  (METIS::DOMAIN-DEF "geometry" "triangle"
   "polygon with three sides and three angles")
  (METIS::DOMAIN-DEF "geometry" "circle"
   "set of points at fixed distance (radius) from a center")
  (METIS::DOMAIN-IDENTITY "geometry" "pythagorean"
   "in right triangle, a^2 + b^2 = c^2")
  (METIS::DOMAIN-IDENTITY "geometry" "triangle-angle-sum"
   "angles of a triangle sum to 180 degrees (Euclidean)")
  (METIS::DOMAIN-IDENTITY "geometry" "circle-circumference" "C = 2*pi*r")
  (METIS::DOMAIN-IDENTITY "geometry" "circle-area" "A = pi*r^2")
  (METIS::CAPABILITY METIS::GEOMETRY "euclidean geometry")
  (METIS::DEPENDS-ON METIS::GEOMETRY METIS::MATH)
  (METIS::DOMAIN-DEF "geometry" "point" "location in space with no size")
  (METIS::DOMAIN-DEF "geometry" "line"
   "straight one-dimensional figure extending without end")
  (METIS::DOMAIN-DEF "geometry" "triangle"
   "polygon with three sides and three angles")
  (METIS::DOMAIN-DEF "geometry" "circle"
   "set of points at fixed distance radius from a center")
  (METIS::DOMAIN-DEF "geometry" "Pythagorean theorem"
   "in a right triangle a^2 + b^2 = c^2")
  (METIS::DOMAIN-DEF "geometry" "triangle angle sum"
   "interior angles sum to 180 degrees in Euclidean geometry")
  (METIS::DOMAIN-DEF "geometry" "circumference" "C = 2*pi*r")
  (METIS::DOMAIN-DEF "geometry" "circle area" "A = pi*r^2")
  (METIS::DOMAIN-DEF "geometry" "Sources"
   "Euclid Elements (public domain) + standard open geometry curricula."))
 :RULES COMMON-LISP:NIL :EXTRACTED 9 :CORPUS-LINES 9)
