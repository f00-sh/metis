;;;; task-load.lisp — task-driven symbol activation (classify + ensure-on-miss)
;;;; Policy layer above seal load/unload: catalog stays human-owned; runtime
;;;; only activates installed packages for the task under trust rules.
;;;; Default auto-trust includes :community (installed sealed catalog is
;;;; user-owned); :unvetted / sideload still need explicit consent.
(in-package :metis)

(defparameter *symbol-task-holder-id* "#task"
  "Synthetic holder that pins task-activated packs for cascade unload.")

(defparameter *symbol-task-auto-trust-tiers*
  '(:core :vetted :org :community :local)
  "Trust tiers allowed for automatic task activation.
   Installed sealed catalog under knowledge/sealed/ is treated as user-owned;
   community is allowed by default. :unvetted / sideload are refused without
   explicit consent (pass :allow-tiers or load manually).")

(defparameter *symbol-task-min-confidence* 0.75
  "Minimum confidence to auto-load a need. Below this → soft-suggest only.")

(defparameter *symbol-task-ambiguous-margin* 0.12
  "When top two domain scores differ by less than this, treat as ambiguous.")

;;; Domain signal table: id, caps, keyword/phrase weights for heuristic classify.
;;; Pure policy — does not load packs. Catalog presence checked separately.
(defparameter *symbol-task-domain-signals*
  '(("calculus"
     :capabilities (:calculus :math :reasoning)
     :keywords (("derivative" . 0.95) ("integral" . 0.95) ("integration" . 0.9)
                ("limit" . 0.85) ("limits" . 0.85) ("differenti" . 0.95)
                ("calculus" . 1.0) ("antiderivative" . 0.95) ("dx/dt" . 0.9)
                ("partial derivative" . 0.95) ("chain rule" . 0.85)))
    ("algebra"
     :capabilities (:algebra :math :reasoning)
     :keywords (("algebra" . 1.0) ("polynomial" . 0.9) ("quadratic" . 0.9)
                ("linear equation" . 0.9) ("solve for" . 0.8) ("factor" . 0.7)
                ("equation" . 0.65) ("variable" . 0.55)))
    ("geometry"
     :capabilities (:geometry :math :reasoning)
     :keywords (("geometry" . 1.0) ("triangle" . 0.85) ("circle" . 0.8)
                ("angle" . 0.75) ("polygon" . 0.85) ("theorem" . 0.55)
                ("perpendicular" . 0.85) ("congruent" . 0.85) ("area of" . 0.7)))
    ("trigonometry"
     :capabilities (:trigonometry :math :reasoning)
     :keywords (("trigonometry" . 1.0) ("trig" . 0.9) ("sine" . 0.85)
                ("cosine" . 0.85) ("tangent" . 0.8) ("sin(" . 0.9)
                ("cos(" . 0.9) ("tan(" . 0.9) ("radian" . 0.8)))
    ("math"
     :capabilities (:math :arithmetic :reasoning)
     :keywords (("arithmetic" . 0.9) ("pemdas" . 0.95) ("bodmas" . 0.9)
                ("math" . 0.8) ("mathematics" . 0.85) ("calculate" . 0.75)
                ("compute" . 0.75) ("what is 2" . 0.7) ("plus" . 0.55)
                ("times" . 0.55) ("multiply" . 0.6) ("divide" . 0.6)))
    ("natural-language"
     :capabilities (:nl :chitchat :language :concepts)
     :keywords (("grammar" . 0.85) ("noun" . 0.7) ("verb" . 0.7)
                ("adjective" . 0.75) ("english" . 0.75) ("slang" . 0.8)
                ("hello" . 0.6) ("chitchat" . 0.9) ("natural language" . 0.95)
                ("how do you say" . 0.8))))
  "Heuristic domain → keyword weight table for utterance classification.")

(defun %task-cap-key (c)
  (intern (string-upcase (string c)) :keyword))

(defun %task-id-string (x)
  (string-downcase (string x)))

(defun symbol-task-catalog-entry (id)
  "Return sealed package dir pathname if installed under sealed root, else NIL."
  (let* ((id (%task-id-string id))
         (dir (merge-pathnames (format nil "~A/" id) (symbol-sealed-root))))
    (when (and (probe-file (merge-pathnames "header.lisp" dir))
               (probe-file (merge-pathnames "body.mse" dir)))
      dir)))

(defun symbol-task-header-for (id)
  "Read seal header for ID when present in catalog."
  (let ((dir (symbol-task-catalog-entry id)))
    (when dir
      (ignore-errors (symbol-seal-read-header dir)))))

(defun symbol-task-loaded-p (id)
  "T if pack ID is currently enabled, overlayed, or layered."
  (%seal-dep-loaded-p (%task-id-string id)))

(defun symbol-task-trust-allows-p (tier-or-header
                                   &key (allow-tiers *symbol-task-auto-trust-tiers*)
                                     (allow-sideload nil))
  "Default auto-activation trust filter.
   Allows core/vetted/org/community/local. Refuses unvetted and sideload
   unless ALLOW-SIDELOAD (explicit consent)."
  (let* ((header (when (consp tier-or-header) tier-or-header))
         (tier (if header
                   (or (getf header :trust-tier) :community)
                   (or tier-or-header :community)))
         (tier (intern (string-upcase (string tier)) :keyword))
         (sideload (and header
                        (or (getf header :sideload)
                            (eq tier :unvetted)))))
    (cond
      ((and sideload (not allow-sideload)) nil)
      ((eq tier :unvetted) (and allow-sideload t))
      ((member tier allow-tiers :test #'eq) t)
      (t nil))))

(defun %task-score-utterance (text)
  "Return alist (domain-id . score) for TEXT against domain signal table."
  (let ((q (string-downcase (or text "")))
        (scores nil))
    (dolist (row *symbol-task-domain-signals*)
      (let ((id (first row))
            (kws (getf (rest row) :keywords))
            (best 0.0d0)
            (hits 0))
        (dolist (pair kws)
          (let ((kw (car pair))
                (w (float (cdr pair) 0.0d0)))
            (when (search kw q :test #'char-equal)
              (incf hits)
              (setf best (max best w)))))
        ;; light boost for multiple hits; cap at 1.0
        (when (plusp hits)
          (let ((score (min 1.0d0 (+ best (* 0.05d0 (1- hits))))))
            (push (cons id score) scores)))))
    (sort scores #'> :key #'cdr)))

(defun %task-explicit-needs (explicit)
  "Normalize EXPLICIT demand list → need plists with confidence 1.0.
   Accepts keywords/strings (domains or caps like :math, \"calculus\")."
  (let ((out nil)
        (items (if (and explicit (atom explicit)) (list explicit) explicit)))
    (dolist (raw items)
      (let* ((s (%task-id-string raw))
             (cap? (and (or (keywordp raw)
                            (and (symbolp raw) (not (keywordp raw))))
                        (not (symbol-task-catalog-entry s))
                        (not (assoc s *symbol-task-domain-signals*
                                    :test #'string-equal))))
             (domain-from-cap
              (when (or cap? (member s '("math" "nl" "calculus" "algebra"
                                         "geometry" "trigonometry"
                                         "arithmetic" "reasoning"
                                         "chitchat" "language" "concepts")
                                     :test #'string-equal))
                (cond
                  ((member s '("nl" "chitchat" "language" "concepts")
                           :test #'string-equal)
                   "natural-language")
                  ((member s '("math" "arithmetic" "reasoning")
                           :test #'string-equal)
                   ;; prefer sealed math domain when present
                   "math")
                  (t s))))
             (id (or domain-from-cap s))
             (row (assoc id *symbol-task-domain-signals* :test #'string-equal))
             (caps (or (and row (getf (rest row) :capabilities))
                       (list (%task-cap-key raw)))))
        (push (list :id id
                    :kind :domain
                    :capabilities caps
                    :confidence 1.0d0
                    :source :explicit)
              out)))
    (nreverse
     (delete-duplicates out :key (lambda (n) (getf n :id)) :test #'string-equal))))

(defun %task-annotate-status (needs)
  "Add :status :loaded|:missing and split helpers."
  (mapcar
   (lambda (n)
     (let* ((id (getf n :id))
            (status (if (symbol-task-loaded-p id) :loaded :missing)))
       (list* :status status n)))
   needs))

(defun %task-needs-from-scores (scores &key (min-confidence *symbol-task-min-confidence*))
  "Convert score alist to need plists; mark ambiguous when top scores close."
  (declare (ignore min-confidence))
  (let* ((top (first scores))
         (second (second scores))
         (ambiguous
          (and top second
               (>= (cdr second) 0.55d0)
               (< (- (cdr top) (cdr second)) *symbol-task-ambiguous-margin*)))
         (needs nil))
    (dolist (pair scores)
      (let* ((id (car pair))
             (conf (cdr pair))
             (row (assoc id *symbol-task-domain-signals* :test #'string-equal))
             (caps (and row (getf (rest row) :capabilities))))
        (when (>= conf 0.55d0)
          (push (list :id id
                      :kind :domain
                      :capabilities caps
                      :confidence conf
                      :source :utterance)
                needs))))
    (values (nreverse needs) ambiguous)))

(defun symbol-task-classify (input &key (mind nil) (explicit nil))
  "Classify needed domains/capabilities from INPUT utterance and/or EXPLICIT demands.
   Diffs against the currently loaded set. Never loads packs.
   Returns plist:
     :needs — list of (:id :kind :capabilities :confidence :source :status)
     :missing / :loaded — id lists
     :ambiguous-p — T when utterance matches multiple close domains
     :suggestions — candidate ids when ambiguous or low confidence
     :mode :utterance | :explicit | :mixed | :empty"
  (declare (ignore mind))
  (let* ((text (cond
                 ((stringp input) input)
                 ((null input) "")
                 (t (princ-to-string input))))
         (exp-needs (%task-explicit-needs explicit))
         (scores (when (and text (plusp (length (string-trim '(#\Space #\Tab) text))))
                   (%task-score-utterance text))))
    (multiple-value-bind (utt-needs ambiguous)
        (if scores
            (%task-needs-from-scores scores)
            (values nil nil))
      ;; Prefer explicit when present; merge unique utterance needs only if
      ;; not already covered by explicit ids.
      (let* ((merged
              (let ((acc (copy-list exp-needs)))
                (dolist (n utt-needs)
                  (unless (find (getf n :id) acc
                                :key (lambda (x) (getf x :id))
                                :test #'string-equal)
                    (push n acc)))
                (nreverse acc)))
             (annotated (%task-annotate-status merged))
             (missing (mapcar (lambda (n) (getf n :id))
                              (remove :loaded annotated :key (lambda (n) (getf n :status)))))
             (loaded (mapcar (lambda (n) (getf n :id))
                             (remove :missing annotated :key (lambda (n) (getf n :status)))))
             ;; Soft-suggest: ambiguous multi-match OR low-confidence missing
             (suggestions
              (cond
                (ambiguous
                 (mapcar #'car (subseq scores 0 (min 3 (length scores)))))
                (t
                 (mapcar (lambda (n) (getf n :id))
                         (remove-if
                          (lambda (n)
                            (or (eq (getf n :status) :loaded)
                                (>= (getf n :confidence) *symbol-task-min-confidence*)))
                          annotated)))))
             (mode (cond
                     ((and exp-needs scores) :mixed)
                     (exp-needs :explicit)
                     (scores :utterance)
                     (t :empty))))
        (list :needs annotated
              :missing missing
              :loaded loaded
              :ambiguous-p (and ambiguous t)
              :suggestions suggestions
              :scores scores
              :mode mode
              :input text
              :explicit (mapcar (lambda (n) (getf n :id)) exp-needs))))))

(defun symbol-task-suggest (input &key (mind nil) (explicit nil))
  "Classify and return soft-suggestions only — never loads.
   Useful for ambiguous / low-confidence needs."
  (let ((c (symbol-task-classify input :mind mind :explicit explicit)))
    (list :suggestions (getf c :suggestions)
          :ambiguous-p (getf c :ambiguous-p)
          :needs (getf c :needs)
          :missing (getf c :missing)
          :loaded (getf c :loaded)
          :hint (if (getf c :ambiguous-p)
                    "Multiple domains match; load one explicitly or pass :explicit."
                    (when (getf c :suggestions)
                      "Low-confidence candidates — not auto-loaded."))
          :mode (getf c :mode))))

(defun %task-refuse-hint (id reason)
  (case reason
    (:not-installed
     (format nil "Symbol ~A is not installed under knowledge/sealed/. ~
                  Train/build it or place a sealed package there, then retry ~
                  (./bin/metis symbol load knowledge/sealed/~A)."
             id id))
    (:trust-blocked
     (format nil "Symbol ~A is installed but blocked by task auto-trust policy ~
                  (unvetted/sideload or disallowed tier). Load explicitly with ~
                  consent: (symbol-seal-load! …) or pass :allow-sideload / ~
                  :allow-tiers to symbol-task-ensure!."
             id))
    (:ambiguous
     (format nil "Need ~A is ambiguous with other domains; not auto-loaded. ~
                  Pass :explicit '(\"~A\") to force ensure."
             id id))
    (:low-confidence
     (format nil "Need ~A is below auto-load confidence (~A). ~
                  Soft-suggest only; pass :explicit or lower :min-confidence."
             id *symbol-task-min-confidence*))
    (t (format nil "Cannot auto-activate ~A (~A)." id reason))))

(defun %task-plan-activations (classified
                               &key (min-confidence *symbol-task-min-confidence*)
                                 (force-explicit nil))
  "From CLASSIFIED result, decide which ids to load vs refuse/suggest.
   FORCE-EXPLICIT: when T, explicit needs bypass confidence/ambiguous gates."
  (let ((activate nil)
        (refuse nil)
        (suggest (copy-list (getf classified :suggestions)))
        (ambiguous (getf classified :ambiguous-p)))
    (dolist (n (getf classified :needs))
      (let* ((id (getf n :id))
             (status (getf n :status))
             (conf (or (getf n :confidence) 0.0d0))
             (src (getf n :source)))
        (cond
          ((eq status :loaded)
           nil)
          ;; Ambiguous utterance: never multi-load; only explicit may activate
          ((and ambiguous (not (eq src :explicit)))
           (push (list :id id :reason :ambiguous
                       :hint (%task-refuse-hint id :ambiguous)
                       :confidence conf)
                 refuse)
           (pushnew id suggest :test #'string-equal))
          ((and (not (eq src :explicit))
                (< conf min-confidence)
                (not force-explicit))
           (push (list :id id :reason :low-confidence
                       :hint (%task-refuse-hint id :low-confidence)
                       :confidence conf)
                 refuse)
           (pushnew id suggest :test #'string-equal))
          (t
           (push n activate)))))
    (list :activate (nreverse activate)
          :refuse (nreverse refuse)
          :suggestions (delete-duplicates suggest :test #'string-equal))))

(defun symbol-task-ensure!
    (&key (mind nil)
       (input nil)
       (explicit nil)
       (holder *symbol-task-holder-id*)
       (min-confidence *symbol-task-min-confidence*)
       (allow-tiers *symbol-task-auto-trust-tiers*)
       (allow-sideload nil)
       (auto-load t)
       (classified nil))
  "Ensure-on-capability-miss for a task.
   Classifies INPUT/EXPLICIT (or uses CLASSIFIED), then for high-confidence
   missing needs that are installed + trust-allowed, loads via symbol-seal-load!
   as temporary auto-loaded overlays (cascade-eligible), pinning them under HOLDER.
   Ambiguous / low-confidence → soft-suggest without multi-load.
   Missing catalog or trust-blocked → refuse with install/suggest-style hint.
   Returns plist: :ok|:partial|:refused|:suggest-only, :activated, :refused,
   :suggestions, :classified, :holder, :auto-loaded."
  (let* ((m (or mind *mind* (boot)))
         (*mind* m)
         (holder (string holder))
         (classified (or classified
                         (symbol-task-classify input :mind m :explicit explicit)))
         (plan (%task-plan-activations classified
                                       :min-confidence min-confidence))
         (activated nil)
         (load-results nil)
         (refused (copy-list (getf plan :refuse)))
         (suggestions (copy-list (getf plan :suggestions)))
         (pinned nil))
    (when auto-load
      (dolist (n (getf plan :activate))
        (let* ((id (getf n :id))
               (dir (symbol-task-catalog-entry id))
               (header (and dir (symbol-seal-read-header dir))))
          (cond
            ((null dir)
             (push (list :id id :reason :not-installed
                         :hint (%task-refuse-hint id :not-installed))
                   refused)
             (pushnew id suggestions :test #'string-equal))
            ((not (symbol-task-trust-allows-p header
                                              :allow-tiers allow-tiers
                                              :allow-sideload allow-sideload))
             (push (list :id id :reason :trust-blocked
                         :trust-tier (getf header :trust-tier)
                         :sideload (getf header :sideload)
                         :hint (%task-refuse-hint id :trust-blocked))
                   refused))
            ((symbol-task-loaded-p id)
             ;; already present (race / concurrent enable)
             (symbol-dep-pin! holder id)
             (push id pinned)
             (push id activated))
            (t
             (handler-case
                 (let ((ld (symbol-seal-load! dir
                                              :mind m
                                              :verify t
                                              :temporary t
                                              :as-dependency t
                                              :auto-deps t)))
                   (symbol-dep-pin! holder id)
                   (push id pinned)
                   (push id activated)
                   (push (list :id id :load ld) load-results))
               (error (e)
                 (push (list :id id :reason :load-error
                             :hint (format nil "Load failed for ~A: ~A. ~
                                                Check seal verify / deps."
                                           id e)
                             :error (princ-to-string e))
                       refused))))))))
    ;; Record holder → pinned deps for cascade unload via symbol-seal-unload!
    (when pinned
      (let ((prev (symbol-required-deps-of holder)))
        (symbol-record-required-deps!
         holder
         (delete-duplicates (append prev (nreverse (copy-list pinned)))
                            :test #'string-equal))))
    (let* ((activated (delete-duplicates (nreverse activated) :test #'string-equal))
           (refused (nreverse refused))
           (auto-flags
            (mapcar (lambda (id)
                      (list :id id :auto-loaded (and (symbol-auto-loaded-p id) t)))
                    activated))
           (status
            (cond
              ((and activated refused) :partial)
              (activated :ok)
              (refused
               (if (and (null (getf plan :activate))
                        (or (getf classified :ambiguous-p)
                            suggestions))
                   :suggest-only
                   :refused))
              ((or (getf classified :ambiguous-p) suggestions) :suggest-only)
              ((null (getf classified :missing)) :ok) ; already loaded
              (t :refused))))
      (list :status status
            :ok (and (member status '(:ok :partial)) t)
            :activated activated
            :auto-loaded auto-flags
            :refused refused
            :suggestions (delete-duplicates suggestions :test #'string-equal)
            :classified classified
            :holder holder
            :loads (nreverse load-results)
            :missing-after
            (remove-if #'symbol-task-loaded-p
                       (getf classified :missing))))))

(defun symbol-task-release! (&key (mind nil) (holder *symbol-task-holder-id*)
                               (cascade t))
  "Release task holder pins and cascade-unload auto-loaded task packs.
   Reuses symbol-seal-unload! refcount contract."
  (let* ((m (or mind *mind*))
         (holder (string holder))
         (deps (symbol-required-deps-of holder)))
    (if (or deps (symbol-dep-holders holder) t)
        (let ((u (symbol-seal-unload! holder :mind m :cascade-unused-deps cascade)))
          (list :released t :holder holder :deps deps :unload u))
        (list :released nil :holder holder :reason :nothing-held))))

(defun symbol-task-prepare!
    (input &key (mind nil) (explicit nil) (ensure t)
             (min-confidence *symbol-task-min-confidence*)
             (allow-tiers *symbol-task-auto-trust-tiers*)
             (allow-sideload nil))
  "Hybrid/iface entry: classify + optional ensure before capability-gated answers.
   When ENSURE is NIL, returns classify/suggest only.
   Never multi-loads on ambiguity."
  (let* ((m (or mind *mind*))
         (c (symbol-task-classify input :mind m :explicit explicit)))
    (if ensure
        (let ((r (symbol-task-ensure!
                  :mind m
                  :classified c
                  :min-confidence min-confidence
                  :allow-tiers allow-tiers
                  :allow-sideload allow-sideload)))
          (list* :prepared t r))
        (list :prepared t
              :status :classify-only
              :classified c
              :suggestions (getf c :suggestions)
              :ambiguous-p (getf c :ambiguous-p)))))
