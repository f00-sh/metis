;;;; task-load.lisp — task-driven symbol classify / ensure / refuse / cascade
(in-package :metis/tests)

(def-suite :metis-task-load
  :description "Task-driven symbol activation: classify, ensure, trust refuse, cascade, suggest")
(in-suite :metis-task-load)

(defparameter *task-load-scratch*
  #P"/tmp/grok-goal-2c5a2d57fe65/implementer/task-load-tests/")

(defun %task-load-isolate-math! ()
  "Disable boot math/domain packs so sealed ensure is observable."
  (dolist (id '("math" "algebra" "geometry" "trigonometry" "calculus"
                "natural-language"))
    (ignore-errors (metis:symbol-pack-disable! id :mind metis:*mind*))
    (ignore-errors (metis:symbol-pack-overlay-unload! id :mind metis:*mind*))
    (ignore-errors (metis:symbol-seal-unload! id :mind metis:*mind*
                                              :cascade-unused-deps nil))
    (ignore-errors (metis::%symbol-unregister-caps! id)))
  (ignore-errors (metis:symbol-task-release! :mind metis:*mind*)))

(test task-load-classify-needs-and-diff
  "Shipped classify: calculus-shaped utterance + explicit demand; NL control."
  (metis:boot :bootstrap t :reset t)
  (%task-load-isolate-math!)
  (let* ((calc (metis:symbol-task-classify
                "What is the derivative of x^2? Explain the limit definition."))
         (needs (getf calc :needs))
         (ids (mapcar (lambda (n) (getf n :id)) needs))
         (missing (getf calc :missing))
         (loaded (getf calc :loaded)))
    (is (eq (getf calc :mode) :utterance))
    (is (member "calculus" ids :test #'string-equal)
        "calculus utterance must need calculus domain")
    (is (member "calculus" missing :test #'string-equal)
        "calculus must be missing when not loaded")
    (is-false (member "calculus" loaded :test #'string-equal))
    (is (every (lambda (n) (getf n :status)) needs)
        "each need must carry :status loaded|missing")
    (is (every (lambda (n) (numberp (getf n :confidence))) needs)))
  ;; explicit demand
  (let* ((ex (metis:symbol-task-classify nil :explicit '(:calculus :math)))
         (ids (mapcar (lambda (n) (getf n :id)) (getf ex :needs))))
    (is (eq (getf ex :mode) :explicit))
    (is (member "calculus" ids :test #'string-equal))
    (is (member "math" ids :test #'string-equal))
    (is (every (lambda (n) (= 1.0d0 (getf n :confidence))) (getf ex :needs))))
  ;; NL-shaped control (not a silent empty)
  (let* ((nl (metis:symbol-task-classify "hello — natural language chitchat please"))
         (ids (mapcar (lambda (n) (getf n :id)) (getf nl :needs))))
    (is (member "natural-language" ids :test #'string-equal))))

(test task-load-ensure-activates-auto-loaded
  "Ensure-on-miss loads installed sealed calculus (and deps); marks auto-loaded."
  (metis:boot :bootstrap t :reset t)
  (%task-load-isolate-math!)
  (is-true (metis:symbol-task-catalog-entry "calculus")
           "shipped knowledge/sealed/calculus must exist for this test")
  (is-false (metis:symbol-task-loaded-p "calculus"))
  (let* ((r (metis:symbol-task-ensure!
             :mind metis:*mind*
             :explicit '("calculus")
             :input nil))
         (activated (getf r :activated))
         (auto (getf r :auto-loaded)))
    (is (member (getf r :status) '(:ok :partial))
        (format nil "ensure status ~A refused=~A" (getf r :status) (getf r :refused)))
    (is (member "calculus" activated :test #'string-equal)
        "ensure must report calculus as activated")
    (is-true (metis:symbol-task-loaded-p "calculus"))
    (is-true (metis:symbol-auto-loaded-p "calculus")
             "task-activated pack must be auto-loaded (cascade-eligible)")
    (is (find "calculus" auto
              :key (lambda (x) (getf x :id)) :test #'string-equal))
    (is (getf (find "calculus" auto
                    :key (lambda (x) (getf x :id)) :test #'string-equal)
              :auto-loaded))
    ;; capability / dep side effects from real seal load
    (is-true (or (metis:symbol-capability-enabled-p :calculus)
                 (metis:symbol-capability-enabled-p :math)
                 (metis:symbol-task-loaded-p "math")
                 (metis:symbol-task-loaded-p "algebra")))
    (is (member "calculus" (metis:symbol-required-deps-of metis:*symbol-task-holder-id*)
                :test #'string-equal)
        "task holder must pin activated calculus")))

(test task-load-refuse-missing-and-trust
  "Ensure refuses missing catalog + unvetted/sideload with install/suggest hint."
  (metis:boot :bootstrap t :reset t)
  (%task-load-isolate-math!)
  ;; missing from catalog
  (let* ((r (metis:symbol-task-ensure!
             :mind metis:*mind*
             :explicit '("totally-missing-domain-xyz-999")))
         (ref (getf r :refused)))
    (is (eq (getf r :status) :refused))
    (is-false (getf r :activated))
    (is (find "totally-missing-domain-xyz-999" ref
              :key (lambda (x) (getf x :id)) :test #'string-equal))
    (let ((entry (find "totally-missing-domain-xyz-999" ref
                       :key (lambda (x) (getf x :id)) :test #'string-equal)))
      (is (eq (getf entry :reason) :not-installed))
      (is (stringp (getf entry :hint)))
      (is (search "not installed" (string-downcase (getf entry :hint))))))
  ;; trust: unvetted/sideload package under sealed root is refused by default
  (let* ((scratch (merge-pathnames "unvetted-task/" *task-load-scratch*))
         (id "task-unvetted-fixture")
         (root (merge-pathnames (format nil "~A/" id) (metis:symbol-sealed-root)))
         (src (list :id id :version "1.0.0" :license "MIT"
                    :capabilities '(:test)
                    :facts '((domain-def "task-unvetted-fixture" "x" "y")))))
    (ensure-directories-exist scratch)
    (ensure-directories-exist root)
    ;; :unvetted sets :sideload in header (seal honesty)
    (metis:symbol-seal! src scratch :mode :open-sealed :trust-tier :unvetted)
    (uiop:copy-file (merge-pathnames "header.lisp" scratch)
                    (merge-pathnames "header.lisp" root))
    (uiop:copy-file (merge-pathnames "body.mse" scratch)
                    (merge-pathnames "body.mse" root))
    (uiop:copy-file (merge-pathnames "symbol.sig" scratch)
                    (merge-pathnames "symbol.sig" root))
    (unwind-protect
         (progn
           (is (eq (getf (metis:symbol-seal-read-header root) :trust-tier)
                   :unvetted))
           (is-false (metis:symbol-task-trust-allows-p
                      (metis:symbol-seal-read-header root))
                     "default trust policy must block unvetted auto-activation")
           (let* ((r (metis:symbol-task-ensure!
                      :mind metis:*mind*
                      :explicit (list id)))
                  (ref (getf r :refused))
                  (entry (find id ref :key (lambda (x) (getf x :id))
                               :test #'string-equal)))
             (is-false (member id (getf r :activated) :test #'string-equal)
                       "unvetted must not auto-activate")
             (is-false (metis:symbol-task-loaded-p id))
             (is-true entry "must refuse with entry")
             (is (eq (getf entry :reason) :trust-blocked))
             (is (search "trust" (string-downcase (or (getf entry :hint) ""))))))
      ;; cleanup fixture from sealed root so suite is not polluted
      (ignore-errors
        (uiop:delete-directory-tree root :validate t :if-does-not-exist :ignore)))))

(test task-load-cascade-on-release
  "Task ensure auto-loads; symbol-task-release! / unload drops last pin → cascade."
  (metis:boot :bootstrap t :reset t)
  (%task-load-isolate-math!)
  (let* ((r (metis:symbol-task-ensure!
             :mind metis:*mind*
             :explicit '("calculus")))
         (holder metis:*symbol-task-holder-id*))
    (is (member "calculus" (getf r :activated) :test #'string-equal))
    (is-true (metis:symbol-task-loaded-p "calculus"))
    (is-true (metis:symbol-auto-loaded-p "calculus"))
    (is (member "calculus" (metis:symbol-required-deps-of holder)
                :test #'string-equal))
    (let ((rel (metis:symbol-task-release! :mind metis:*mind*)))
      (is-true (getf rel :released))
      (is-false (metis:symbol-task-loaded-p "calculus")
                "auto-loaded calculus must cascade unload when task holder releases")
      (is-false (metis:symbol-auto-loaded-p "calculus")))))

(test task-load-ambiguous-soft-suggest
  "Ambiguous multi-domain utterance → suggestions, no silent multi-load."
  (metis:boot :bootstrap t :reset t)
  (%task-load-isolate-math!)
  ;; Geometry + calculus keywords close together → ambiguous
  (let* ((text "derivative angle circle triangle integral geometry calculus")
         (c (metis:symbol-task-classify text))
         (sug (metis:symbol-task-suggest text))
         (before-calc (metis:symbol-task-loaded-p "calculus"))
         (r (metis:symbol-task-ensure! :mind metis:*mind* :input text))
         (activated (or (getf r :activated) '()))
         (scored (mapcar #'car (getf c :scores))))
    (is-true (or (getf c :ambiguous-p)
                 (>= (length (getf c :suggestions)) 2)
                 (>= (length (remove-if-not
                              (lambda (n)
                                (>= (getf n :confidence) 0.55d0))
                              (getf c :needs)))
                     2))
             "classifier should surface multi-domain ambiguity or multi needs")
    (is (consp (getf sug :suggestions)))
    ;; ensure must not silently multi-load all candidates on ambiguity
    (when (getf c :ambiguous-p)
      (is (member (getf r :status) '(:suggest-only :refused :partial)))
      (is-false
       (and (member "calculus" (getf r :activated) :test #'string-equal)
            (member "geometry" (getf r :activated) :test #'string-equal))
       "must not multi-load both calculus and geometry on ambiguous utterance")
      (when scored
        (is (< (length activated) (length scored))
            "ambiguous ensure must not activate every scored domain")))
    ;; baseline: calculus was not loaded before ensure of pure-ambiguous path
    (is-false before-calc)))

(test task-load-prepare-hybrid-hook
  "symbol-task-prepare! and cognitive-unit expose task-symbols integration."
  (metis:boot :bootstrap t :reset t)
  (%task-load-isolate-math!)
  (let ((p (metis:symbol-task-prepare!
            nil :mind metis:*mind* :explicit '("math") :ensure t)))
    (is-true (getf p :prepared))
    (is (member (getf p :status) '(:ok :partial))
        (format nil "prepare status ~A ~A" (getf p :status) (getf p :refused)))
    (is (member "math" (getf p :activated) :test #'string-equal)))
  (let ((u (metis:cognitive-unit metis:*mind*
                                 "compute the integral using calculus limits"
                                 :learn nil :task-symbols t)))
    (is (consp (getf u :task-symbols))
        "cognitive-unit must attach :task-symbols prepare result")))
