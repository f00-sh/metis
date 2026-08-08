(:FACTS
 ((METIS::DOMAIN-DEF "calculus" "limit"
   "value a function approaches as input approaches a point")
  (METIS::DOMAIN-DEF "calculus" "derivative"
   "instantaneous rate of change; limit of difference quotient")
  (METIS::DOMAIN-DEF "calculus" "integral"
   "accumulation of quantities; inverse of differentiation (FTC)")
  (METIS::DOMAIN-DEF "calculus" "continuity"
   "function matches its limit at a point (informal open-course sense)")
  (METIS::DOMAIN-IDENTITY "calculus" "power-rule" "d/dx [x^n] = n x^(n-1)")
  (METIS::DOMAIN-IDENTITY "calculus" "sum-rule" "d/dx [f+g] = f' + g'")
  (METIS::DOMAIN-IDENTITY "calculus" "ftc"
   "d/dx ∫_a^x f(t) dt = f(x) under suitable conditions")
  (METIS::DOMAIN-IDENTITY "calculus" "chain-rule"
   "d/dx f(g(x)) = f'(g(x)) g'(x)")
  (METIS::CAPABILITY METIS::CALCULUS "limits derivatives integrals")
  (METIS::DEPENDS-ON METIS::CALCULUS METIS::ALGEBRA)
  (METIS::DEPENDS-ON METIS::CALCULUS METIS::TRIGONOMETRY)))
