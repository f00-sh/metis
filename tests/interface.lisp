;;;; interface.lisp — interactive multi-turn + attachments + self-accommodate
(in-package :metis/tests)

(def-suite :metis-iface
  :description "Full interactive interface: multi-turn, files/photos, accommodation")
(in-suite :metis-iface)

(defparameter *iface-fixtures*
  "/tmp/grok-goal-fbd0b3f9ae3b/implementer/fixtures/")

(test iface-thesis-present
  (is (search "INTERFACE" (metis:iface-thesis) :test #'char-equal))
  (is (search "multi-turn" (metis:iface-thesis) :test #'char-equal)))

(test iface-multi-turn-same-session
  "Two successive turns on one session without restart."
  (metis:boot :bootstrap t :reset t)
  (let* ((s (metis:session-create :id "mt-1"))
         (r1 (metis:iface-turn s "(tell (iface-live alpha))"))
         (r2 (metis:iface-turn s "(ask (iface-live ?x))")))
    (is (= 1 (getf r1 :turn)))
    (is (= 2 (getf r2 :turn)))
    (is (equal (metis::sess-id s) (getf (getf r1 :session) :id)))
    (is (equal (metis::sess-id s) (getf (getf r2 :session) :id)))
    (is (plusp (getf r1 :facts-delta)))
    (is (search "IFACE-LIVE" (prin1-to-string (getf r2 :result))))))

(test iface-attach-file-context-photo
  "Attach text file, context, and photo; all recorded and usable."
  (metis:boot :bootstrap t :reset t)
  (let* ((s (metis:session-create :id "att-1"))
         (notes (merge-pathnames "notes.txt" *iface-fixtures*))
         (photo (merge-pathnames "dot.png" *iface-fixtures*))
         (f (metis:session-attach-file s (namestring notes)))
         (c (metis:session-attach-context s "project priority is safety-first"
                                          :name "priority"))
         (p (metis:session-attach-photo s (namestring photo)
                                        :caption "unit test pixel")))
    (is (eq :file (metis::att-kind f)))
    (is (eq :context (metis::att-kind c)))
    (is (eq :photo (metis::att-kind p)))
    (is (search "ORBIT-77" (metis::att-text f)))
    (is (equal "project priority is safety-first" (metis::att-text c)))
    (is (equal "image/png" (metis::att-media-type p)))
    (is (plusp (metis::att-size p)))
    (is (probe-file (metis::att-path p)))
    (let ((listed (metis:session-list-attachments s)))
      (is (= 3 (length listed))))
    ;; later turn can read attachment text via interface
    (let ((r (metis:iface-turn s (format nil "/read ~A" (metis::att-id f)))))
      (is (search "ORBIT-77" (prin1-to-string (getf r :result)))))
    ;; KB has attachment facts
    (is (metis:ask (metis::sess-mind s)
                   (list 'metis::attachment (metis::att-id f) '?k '?n '?mt '?sz '?p)))))

(test iface-cognition-changes-mind
  "Interactive turn drives real tell/ask cognition."
  (metis:boot :bootstrap t :reset t)
  (let* ((s (metis:session-create :id "cog-1"))
         (m (metis::sess-mind s))
         (before (metis::kb-count-facts (metis::mind-kb m)))
         (r (metis:iface-turn s "(tell (iface-cog-marker 42))")))
    (is (> (metis::kb-count-facts (metis::mind-kb m)) before))
    (is (plusp (getf r :facts-delta)))
    (is (equal (mread "(iface-cog-marker 42)")
               (metis:ask m (mread "(iface-cog-marker 42)"))))))

(test iface-self-accommodate-unknown
  "Gap → /need → accommodation → capability present and tool works."
  (metis:boot :bootstrap t :reset t)
  (let* ((s (metis:session-create :id "acc-1"))
         (m (metis::sess-mind s))
         (cap "hyper-translator"))
    (is (not (metis::%iface-capability-present-p s cap)))
    (let ((r1 (metis:iface-turn s (format nil "/need ~A" cap))))
      (is (eq t (getf (getf r1 :result) :accommodated)))
      (is-true (getf (getf r1 :result) :present-after)))
    (is-true (metis::%iface-capability-present-p s cap))
    (is-true (metis::kb-holds-p
              (metis::mind-kb m)
              (list 'metis::capability-accommodated
                    (intern (string-downcase cap) :metis))))
    ;; tool is live
    (let ((tool (metis::tr-get (metis::mind-tools m)
                               (intern (string-downcase cap) :metis))))
      (is-true tool)
      (is (equal t (getf (metis::invoke-tool m
                                             (intern (string-downcase cap) :metis)
                                             "hello")
                         :ok))))
    ;; second need reports already
    (let ((r2 (metis:iface-turn s (format nil "/need ~A" cap))))
      (is (equal cap (string (getf (getf r2 :result) :already)))))))

(test iface-drive-multi
  (metis:boot :bootstrap t :reset t)
  (let* ((s (metis:session-create))
         (res (metis:iface-drive
               (list "status"
                     "(tell (drive-ok yes))"
                     "(ask (drive-ok ?x))")
               :session s)))
    (is (= 3 (length res)))
    (is (= 3 (metis::sess-turn-count s)))
    (is (metis:ask (metis::sess-mind s) (mread "(drive-ok yes)")))))

(test iface-launcher-exists
  (let ((root (asdf:system-source-directory :metis)))
    (is-true (probe-file (merge-pathnames "bin/iface" root)))
    (is-true (probe-file (merge-pathnames "bin/iface.lisp" root)))
    (is (search "iface-repl"
                (uiop:read-file-string
                 (merge-pathnames "bin/iface.lisp" root))))))
