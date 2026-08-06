;;;; interface.lisp — interactive multi-turn + attachments + self-accommodate
(in-package :metis/tests)

(def-suite :metis-iface
  :description "Full interactive interface: multi-turn, files/photos, accommodation")
(in-suite :metis-iface)

(defun %iface-make-fixtures ()
  "Self-contained fixtures (no hard-coded external goal scratch path)."
  (let* ((dir (uiop:ensure-directory-pathname
               (merge-pathnames
                (format nil "metis-iface-fixtures-~D/" (get-universal-time))
                (uiop:temporary-directory))))
         (notes (merge-pathnames "notes.txt" dir))
         (photo (merge-pathnames "dot.png" dir)))
    (ensure-directories-exist dir)
    (with-open-file (out notes :direction :output :if-exists :supersede)
      (write-string
       "Metis interface fixture: the secret passphrase is ORBIT-77.
This is a plain text file for attachment tests.
"
       out))
    ;; minimal 1x1 PNG
    (with-open-file (out photo :direction :output
                              :element-type '(unsigned-byte 8)
                              :if-exists :supersede)
      (write-sequence
       #(137 80 78 71 13 10 26 10 0 0 0 13 73 72 68 82 0 0 0 1 0 0 0 1
         8 2 0 0 0 144 119 83 222 0 0 0 12 73 68 65 84 120 156 99 248 15
         0 0 1 1 0 5 24 216 78 0 0 0 0 73 69 78 68 174 66 96 130)
       out))
    (list :dir dir :notes (namestring notes) :photo (namestring photo))))

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
  (let* ((fx (%iface-make-fixtures))
         (s (metis:session-create :id "att-1"))
         (turns-before (metis::sess-turn-count s))
         (f (metis:session-attach-file s (getf fx :notes)))
         (c (metis:session-attach-context s "project priority is safety-first"
                                          :name "priority"))
         (turns-after-ctx (metis::sess-turn-count s))
         (p (metis:session-attach-photo s (getf fx :photo)
                                        :caption "unit test pixel")))
    (is (= turns-before turns-after-ctx)
        "context attach must not bump turn counter")
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
    (let ((r (metis:iface-turn s (format nil "/read ~A" (metis::att-id f)))))
      (is (search "ORBIT-77" (prin1-to-string (getf r :result)))))
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
  "Gap → /need → accommodation → subsequent iface-turn (tool NAME …) succeeds."
  (metis:boot :bootstrap t :reset t)
  (let* ((s (metis:session-create :id "acc-1"))
         (m (metis::sess-mind s))
         (cap "hyper-translator")
         (tool-sym (intern (string-upcase cap) :metis)))
    (is (not (metis::%iface-capability-present-p s cap)))
    (let ((r1 (metis:iface-turn s (format nil "/need ~A" cap))))
      (is (eq t (getf (getf r1 :result) :accommodated)))
      (is-true (getf (getf r1 :result) :present-after)))
    (is-true (metis::%iface-capability-present-p s cap))
    ;; Natural mind-language path: reader-normal tool symbol
    (let* ((form (list 'tool tool-sym "hello-from-iface"))
           (r2 (metis:iface-turn s (prin1-to-string form)))
           (res (getf r2 :result)))
      (is (consp res))
      ;; interpret of (tool NAME arg) returns tool result
      (let ((tool-result (or (getf res :result) res)))
        (is (eq t (getf tool-result :ok)))
        (is (eq tool-sym (getf tool-result :capability)))))
    ;; second need reports already
    (let ((r3 (metis:iface-turn s (format nil "/need ~A" cap))))
      (is (equal cap (string (getf (getf r3 :result) :already)))))))

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
