;;;; domains.lisp — production domain packs (HTN + extra knowledge)
(in-package :metis)

(defun load-blocks-htn (mind)
  "Hierarchical methods for blocks world."
  (let ((htn (mind-htn mind)))
    (htn-defprimitive htn 'pickup 'pickup)
    (htn-defprimitive htn 'putdown 'putdown)
    (htn-defprimitive htn 'stack 'stack)
    (htn-defprimitive htn 'unstack 'unstack)

    (htn-defmethod htn 'make-clear
                   '(make-clear ?x)
                   '()
                   '((clear-rec ?x))
                   :priority 10)

    (htn-defmethod htn 'clear-rec-already
                   '(clear-rec ?x)
                   '((clear ?x))
                   '()
                   :priority 20)

    (htn-defmethod htn 'clear-rec-unstack
                   '(clear-rec ?x)
                   '((on ?y ?x))
                   '((clear-rec ?y)
                     (unstack ?y ?x)
                     (putdown ?y))
                   :priority 5)

    (htn-defmethod htn 'move-to-table
                   '(move-to ?x table)
                   '()
                   '((clear-rec ?x)
                     (pickup ?x)
                     (putdown ?x))
                   :priority 10)

    (htn-defmethod htn 'move-onto
                   '(move-to ?x ?y)
                   '((block ?y))
                   '((clear-rec ?x)
                     (clear-rec ?y)
                     (pickup ?x)
                     (stack ?x ?y))
                   :priority 10)

    (htn-defmethod htn 'achieve-on
                   '(achieve-on ?x ?y)
                   '()
                   '((move-to ?x ?y))
                   :priority 10)
    htn))

(defun load-kinship-domain (mind)
  (assert-rule mind '(parent ?x ?y) '((father ?x ?y)) :name 'father-parent)
  (assert-rule mind '(parent ?x ?y) '((mother ?x ?y)) :name 'mother-parent)
  (assert-rule mind '(grandparent ?x ?z)
               '((parent ?x ?y) (parent ?y ?z))
               :name 'grandparent-def)
  (assert-rule mind '(sibling ?x ?y)
               '((parent ?p ?x) (parent ?p ?y) (\\= ?x ?y))
               :name 'sibling-def)
  (tell mind
        '(father zeus ares)
        '(mother hera ares)
        '(father ares harmonia)
        '(mother aphrodite harmonia)
        '(father cronus zeus)
        '(mother rhea zeus))
  (forward-chain mind)
  mind)

(defun load-circuit-domain (mind)
  "Simple digital circuit reasoning facts/rules."
  (assert-rule mind '(signal ?w on)
               '((connected ?g ?w) (gate-type ?g and)
                 (input ?g ?a) (input ?g ?b)
                 (signal ?a on) (signal ?b on))
               :name 'and-gate-on)
  (assert-rule mind '(signal ?w on)
               '((connected ?g ?w) (gate-type ?g or)
                 (input ?g ?a) (signal ?a on))
               :name 'or-gate-on-a)
  (assert-rule mind '(signal ?w on)
               '((connected ?g ?w) (gate-type ?g or)
                 (input ?g ?b) (signal ?b on))
               :name 'or-gate-on-b)
  (assert-rule mind '(signal ?w on)
               '((connected ?g ?w) (gate-type ?g not)
                 (input ?g ?a) (signal ?a off))
               :name 'not-gate-on)
  (tell mind
        '(gate-type g1 and)
        '(input g1 w1)
        '(input g1 w2)
        '(connected g1 w3)
        '(signal w1 on)
        '(signal w2 on)
        '(gate-type g2 not)
        '(input g2 w3)
        '(connected g2 w4))
  (forward-chain mind)
  mind)

(defun load-csp-demo (mind)
  "Store a map-coloring CSP as frames for API/demo."
  (deframe mind 'map-coloring
    '(problem :value graph-coloring)
    '(variables :value (wa nt sa q nsw v t))
    '(colors :value (red green blue)))
  mind)

(defun load-domains (mind)
  "Install all production domain packs."
  (load-blocks-htn mind)
  (load-kinship-domain mind)
  (load-circuit-domain mind)
  (load-csp-demo mind)
  (metis-log :info "domains loaded (htn+kinship+circuit+csp)")
  mind)
