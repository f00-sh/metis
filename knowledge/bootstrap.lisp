;;;; bootstrap.lisp — seed ontology, blocks world, self-knowledge, skills
(in-package :metis)

(defun load-bootstrap (mind)
  "Install a non-trivial initial theory: taxonomy, blocks world, self-model frames."
  (let ((m mind))
    ;; ---- taxonomic / commonsense rules ----
    (assert-rule m '(can-fly ?x) '((bird ?x) (not (penguin ?x)))
                 :name 'birds-fly :priority 10)
    (assert-rule m '(bird ?x) '((sparrow ?x)) :name 'sparrow-is-bird)
    (assert-rule m '(bird ?x) '((eagle ?x)) :name 'eagle-is-bird)
    (assert-rule m '(bird ?x) '((penguin ?x)) :name 'penguin-is-bird)
    (assert-rule m '(mortal ?x) '((human ?x)) :name 'humans-mortal)
    (assert-rule m '(human ?x) '((philosopher ?x)) :name 'philo-human)
    (assert-rule m '(block ?x) '((cube ?x)) :name 'cube-is-block)
    (assert-rule m '(clear ?x)
                 '((block ?x) (not (on ?y ?x)))
                 :name 'clear-if-nothing-on
                 :priority 5)
    (assert-rule m '(object ?x) '((block ?x)) :name 'block-object)
    (assert-rule m '(object ?x) '((table ?x)) :name 'table-object)

    ;; seed facts
    (tell m
          '(sparrow tweety)
          '(penguin opus)
          '(eagle aquila)
          '(philosopher socrates)
          '(table table)
          '(cube a) '(cube b) '(cube c)
          '(block a) '(block b) '(block c)
          '(on a table)
          '(on b table)
          '(on c a)
          '(arm-empty)
          '(clear b)
          '(clear c))

    ;; forward chain to derive consequences
    (forward-chain m)

    ;; ---- frames ----
    (deframe m 'thing
      '(kind :value physical))
    (deframe m 'agent
      '(:ako (thing))
      '(can-reason :value t)
      '(can-act :value t))
    (deframe m 'metis-self
      '(:ako (agent))
      '(name :value "Metis")
      '(architecture :value introspective-cognitive-architecture)
      '(languages :value (common-lisp s-expression))
      '(modules :value (unifier kb frames forward backward
                         planner working episodic procedural
                         meta tools llm introspection agent)))
    (deframe m 'block-proto
      '(:ako (thing))
      '(graspable :value t)
      '(supportable :value t))
    (deframe m 'a '(:ako (block-proto)) '(label :value a) '(color :value red))
    (deframe m 'b '(:ako (block-proto)) '(label :value b) '(color :value blue))
    (deframe m 'c '(:ako (block-proto)) '(label :value c) '(color :value green))

    ;; ---- STRIPS operators (blocks world) ----
    (define-operator m 'pickup
      :params '(?x)
      :preconds '((clear ?x) (on ?x table) (arm-empty))
      :add '((holding ?x))
      :del '((clear ?x) (on ?x table) (arm-empty)))

    (define-operator m 'putdown
      :params '(?x)
      :preconds '((holding ?x))
      :add '((on ?x table) (clear ?x) (arm-empty))
      :del '((holding ?x)))

    (define-operator m 'stack
      :params '(?x ?y)
      :preconds '((holding ?x) (clear ?y))
      :add '((on ?x ?y) (clear ?x) (arm-empty))
      :del '((holding ?x) (clear ?y)))

    (define-operator m 'unstack
      :params '(?x ?y)
      :preconds '((on ?x ?y) (clear ?x) (arm-empty) (block ?y))
      :add '((holding ?x) (clear ?y))
      :del '((on ?x ?y) (clear ?x) (arm-empty)))

    ;; ---- procedural skill: reflexive self-report ----
    (pm-install
     (mind-pm m)
     (make-skill
      :name 'report-self
      :params '()
      :preconds '()
      :body '((self-model *mind*))
      :kind :procedure
      :source :bootstrap
      :utility 0.5
      :meta '(:doc "Return structured self-model")))

    (pm-install
     (mind-pm m)
     (make-skill
      :name 'prove-query
      :params '(pattern)
      :preconds '()
      :body '((ask *mind* pattern))
      :kind :procedure
      :source :bootstrap
      :utility 0.8))

    ;; episode: birth
    (remember-episode m
                      :situation '(:bootstrap-complete)
                      :action 'load-bootstrap
                      :outcome :ok
                      :valence 0.6
                      :tags '(:birth :system))

    (mind-trace-push m :bootstrap-complete
                     (kb-count-facts (mind-kb m))
                     (length (kb-rules (mind-kb m))))
    m))
