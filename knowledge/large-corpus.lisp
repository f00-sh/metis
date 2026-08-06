;;;; large-corpus.lisp — larger-than-1.0.0 knowledge base generator
(in-package :metis)

(defun load-large-taxonomy (mind &key (size 500))
  "Generate SIZE entities in a multi-level taxonomy with rules.
   Materially larger than bootstrap (~30 facts)."
  (let ((m mind))
    (assert-rule m '(animal ?x) '((mammal ?x)) :name 'mammal-animal)
    (assert-rule m '(animal ?x) '((bird-kind ?x)) :name 'bird-animal)
    (assert-rule m '(mammal ?x) '((dog-kind ?x)) :name 'dog-mammal)
    (assert-rule m '(mammal ?x) '((cat-kind ?x)) :name 'cat-mammal)
    (assert-rule m '(warm-blooded ?x) '((animal ?x)) :name 'animal-warm)
    (assert-rule m '(can-bark ?x) '((dog-kind ?x)) :name 'dog-bark)
    (dotimes (i size)
      (let* ((kind (if (evenp i) 'dog-kind 'cat-kind))
             (name (intern (format nil "ENT-~D" i) :metis)))
        (assert-fact m (list kind name) :support :corpus)
        (when (zerop (mod i 10))
          (assert-fact m (list 'famous name) :support :corpus))))
    (forward-chain m)
    (metis-log :info "large taxonomy loaded size=~D facts=~D"
               size (kb-count-facts (mind-kb m)))
    (list :size size :facts (kb-count-facts (mind-kb m)))))

(defun load-large-graph (mind &key (nodes 200) (edges 400))
  "Random-ish edge graph for path-ish rules."
  (assert-rule mind '(connected ?a ?c)
               '((link ?a ?b) (link ?b ?c))
               :name 'link-trans-1)
  (dotimes (i nodes)
    (assert-fact mind (list 'node (intern (format nil "N~D" i) :metis))
                 :support :corpus))
  (loop for e from 0 below edges
        for a = (intern (format nil "N~D" (mod e nodes)) :metis)
        for b = (intern (format nil "N~D" (mod (+ e 1 (mod e 7)) nodes)) :metis)
        do (assert-fact mind (list 'link a b) :support :corpus))
  (forward-chain mind)
  (list :nodes nodes :edges edges :facts (kb-count-facts (mind-kb mind))))

(defun load-large-corpus (mind &key (taxonomy 500) (graph-nodes 200))
  "Full large corpus pack."
  (let ((a (load-large-taxonomy mind :size taxonomy))
        (b (load-large-graph mind :nodes graph-nodes)))
    (list :taxonomy a :graph b :total-facts (kb-count-facts (mind-kb mind)))))
