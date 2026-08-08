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

(test iface-freeform-retrieval-english
  "Keyword retrieval: question is not a substring of corpus but hits distinctive tokens."
  (metis:boot :bootstrap t :reset t)
  (let* ((s (metis:session-create :id "ff-ret" :boot nil))
         (corpus "Dolphins are mammals that live in the ocean and use sonar.")
         ;; question shares keywords but is NOT an exact substring of corpus
         (q "Are dolphins mammals of the ocean?"))
    (is (null (search (string-downcase q) (string-downcase corpus)
                      :test #'char-equal)))
    (metis:session-attach-context s corpus :name "dolphin-notes")
    (let* ((hits (metis:iface-retrieve-attachments s q))
           (out (metis:iface-turn s q))
           (res (getf out :result))
           (reply (getf out :reply)))
      (is (plusp (length hits)))
      (is (search "dolphin" (string-downcase (getf (first hits) :snippet))
                  :test #'char-equal))
      (is (eq (getf res :freeform) :from-attachments))
      (is (stringp reply))
      (is (search "dolphin" (string-downcase reply) :test #'char-equal))
      (is (or (search "mammal" (string-downcase reply) :test #'char-equal)
              (search "ocean" (string-downcase reply) :test #'char-equal)
              (search "sonar" (string-downcase reply) :test #'char-equal)))
      (is (getf out :explain))
      (is (getf out :metrics)))))

(test iface-freeform-generate-path-in
  "No attachment hit → TMS-IN generate path; reply is a string."
  (metis:boot :bootstrap t :reset t)
  (metis:nn-enable-path metis:*mind*)
  (metis:nn-train-language-model
   "metis hybrid architecture trains pure common lisp models "
   :name "online-lm" :epochs 1 :hidden 24 :seq-len 24 :depth 2
   :max-batches 6 :lr 3d-2)
  (let* ((s (metis:session-create :id "ff-gen" :boot nil))
         (out (metis:iface-turn s "What is quantum chromodynamics zigzag?"))
         (res (getf out :result))
         (reply (getf out :reply)))
    (is (eq (getf res :freeform) :generate))
    (is (stringp reply))
    (is (plusp (length reply)))
    (is (stringp (getf res :prompt)))
    (is (search "Question" (getf res :prompt) :test #'char-equal))
    (is (getf out :explain))
    (is (getf out :metrics))))

(test iface-freeform-generate-path-out
  "Path OUT refuses generate; readable string reply; no silent sample."
  (metis:boot :bootstrap t :reset t)
  (metis:nn-train-language-model
   "some corpus text for model registration only "
   :name "online-lm" :epochs 1 :hidden 24 :seq-len 24 :depth 2
   :max-batches 4 :lr 3d-2)
  (metis:nn-disable-path metis:*mind*)
  (let* ((s (metis:session-create :id "ff-out" :boot nil))
         (out (metis:iface-turn s "Explain obscure topic without notes"))
         (res (getf out :result))
         (reply (getf out :reply)))
    (is (eq (getf res :freeform) :refuse))
    (is (getf res :refused))
    (is (stringp reply))
    (is (or (search "disabled" (string-downcase reply))
            (search "out" (string-downcase reply))
            (search "can't" (string-downcase reply))
            (search "cannot" (string-downcase reply))))
    (is (getf out :explain))))

(test iface-freeform-kb-priority
  "KB about hit preferred over generate when no attachment needed."
  (metis:boot :bootstrap t :reset t)
  (metis:nn-enable-path metis:*mind*)
  (let* ((s (metis:session-create :id "ff-kb" :boot nil))
         (m (metis::sess-mind s)))
    (metis:assert-fact m (list 'about "purple widget" "a purple widget is a demo fact")
                       :support :test :forward nil)
    (let* ((out (metis:iface-turn s "purple widget"))
           (res (getf out :result)))
      (is (eq (getf res :freeform) :kb))
      (is (stringp (getf out :reply)))
      (is (search "purple" (string-downcase (getf out :reply))
                  :test #'char-equal)))))

(test iface-freeform-retrieval-beats-generate
  "Attachment keyword hit used even when a model exists."
  (metis:boot :bootstrap t :reset t)
  (metis:nn-enable-path metis:*mind*)
  (metis:nn-train-language-model "filler train text filler train text "
                                 :name "online-lm" :epochs 1 :hidden 24
                                 :seq-len 24 :depth 2 :max-batches 4)
  (let* ((s (metis:session-create :id "ff-pri" :boot nil)))
    (metis:session-attach-context s
     "UniqueToken-ZZYZX is a rare artifact stored only in notes."
     :name "rare")
    (let* ((out (metis:iface-turn s "Where is UniqueToken-ZZYZX mentioned?"))
           (res (getf out :result)))
      (is (eq (getf res :freeform) :from-attachments))
      (is (search "UniqueToken-ZZYZX" (getf out :reply) :test #'char-equal)))))

(test iface-ingest-folder-realtime
  "Ingest mixed folder; extract text; freeform English from corpus."
  (metis:boot :bootstrap t :reset t)
  (metis:nn-enable-path metis:*mind*)
  (let* ((dir (uiop:ensure-directory-pathname
               (merge-pathnames "metis-ingest-fx/" (uiop:temporary-directory))))
         (s (metis:session-create :id "ing-fx" :boot nil)))
    (ensure-directories-exist dir)
    (with-open-file (out (merge-pathnames "a.txt" dir) :direction :output :if-exists :supersede)
      (write-string "Penguins are flightless birds that swim in cold seas." out))
    (with-open-file (out (merge-pathnames "b.csv" dir) :direction :output :if-exists :supersede)
      (write-string "name,role\nmetis,architecture\n" out))
    (let ((r (metis:session-ingest-path s dir :train t :train-name "session-lm"
                                        :async t :intensity :ingest)))
      (is (plusp (getf r :with-text)))
      (is (plusp (getf r :trained))))
    (let* ((out (metis:iface-turn s "tell me about penguins"))
           (reply (getf out :reply)))
      (is (stringp reply))
      (is (search "penguin" (string-downcase reply) :test #'char-equal)))
    (let ((ex (metis:extract-text-from-path
               (namestring (merge-pathnames "b.csv" dir)))))
      (is (getf ex :text))
      (is (search "metis" (string-downcase (getf ex :text)) :test #'char-equal)))
    (metis:brain-stop!)))

(test iface-at-file-hard-trains
  "Chat @path attaches and queues real hard train (not context-only)."
  (metis:boot :bootstrap t :reset t)
  (metis:nn-enable-path metis:*mind*)
  (let* ((dir (uiop:ensure-directory-pathname
               (merge-pathnames "metis-at-fx/" (uiop:temporary-directory))))
         (path (namestring (merge-pathnames "narwhals.txt" dir)))
         (s (metis:session-create :id "at-fx" :boot nil)))
    (ensure-directories-exist dir)
    (with-open-file (out path :direction :output :if-exists :supersede)
      (write-string "Narwhals are Arctic whales with a long spiral tusk." out))
    (let* ((out (metis:iface-turn s (format nil "@~A" path)))
           (res (getf out :result))
           (reply (getf out :reply)))
      (is (eq (getf res :attached) :file))
      (is (getf res :trained))
      (is (search "HARD train" reply :test #'char-equal)))
    (let* ((out (metis:iface-turn s "tell me about narwhals"))
           (reply (getf out :reply)))
      (is (search "narwhal" (string-downcase reply) :test #'char-equal)))
    (let ((st (metis:brain-status)))
      (is (getf st :running)))
    (metis:brain-stop!)))

(test repl-english-not-nil
  "Default metis-repl surface: slash + English return real replies (not NIL)."
  (metis:boot :bootstrap t :reset t)
  (let* ((s (metis:session-create :id "repl-fx" :boot nil))
         (b (metis:iface-turn s "/brain status"))
         (q (metis:iface-turn s "what is a day")))
    (is (stringp (getf b :reply)))
    (is (search "Brain" (getf b :reply) :test #'char-equal))
    (is (stringp (getf q :reply)))
    (is (plusp (length (string-trim '(#\Space) (getf q :reply)))))
    (is (not (string-equal (getf q :reply) "NIL")))
    (metis:brain-stop!)))

(test iface-chat-not-garbage
  "Greetings and concept questions get real English — not NIL, not char-LM soup."
  (metis:boot :bootstrap t :reset t)
  (let ((s (metis:session-create :id "chat-fx" :boot nil)))
    (let* ((hi (metis:iface-turn s "hello"))
           (r (getf hi :reply)))
      (is (search "Metis" r :test #'char-equal))
      (is (not (search "I don't have notes matching" r :test #'char-equal))))
    (let* ((num (metis:iface-turn s "what is a number?"))
           (r (getf num :reply)))
      (is (search "mathematical" (string-downcase r)))
      (is (not (search "[Local model sketch" r :test #'char-equal)))
      (is (< (count #\* r) 3)))
    (let* ((who (metis:iface-turn s "who are you"))
           (r (getf who :reply)))
      (is (search "Metis" r :test #'char-equal)))
    (metis:brain-stop!)))

(test iface-watch-brain-auto
  "Watch folder + poll attaches+trains new drops (shipped session-watch-poll!)."
  (metis:boot :bootstrap t :reset t)
  (metis:nn-enable-path metis:*mind*)
  (metis:brain-stop!)
  (let* ((dir (uiop:ensure-directory-pathname
               (merge-pathnames
                (format nil "metis-watch-fx-~A/" (get-universal-time))
                (uiop:temporary-directory))))
         (s (metis:session-create
             :id (format nil "watch-fx-~A" (get-universal-time))
             :boot nil)))
    (ensure-directories-exist dir)
    (with-open-file (out (merge-pathnames "seed.txt" dir)
                         :direction :output :if-exists :supersede)
      (write-string "Seed: otters hold hands while sleeping." out))
    (metis:session-watch-folder s dir :train t :async nil :intensity :hard
                                :auto-brain nil)
    (metis:brain-stop!)
    (with-open-file (out (merge-pathnames "live-otter.txt" dir)
                         :direction :output :if-exists :supersede)
      (write-string "Live drop: sea otters use tools and float in rafts." out))
    (finish-output)
    (let ((ev (metis:session-watch-poll! s)))
      (is (plusp (length ev)))
      (is (getf (first ev) :trained)))
    (let* ((out (metis:iface-turn s "tell me about otters"))
           (reply (getf out :reply)))
      (is (search "otter" (string-downcase reply) :test #'char-equal)))
    (metis:brain-stop!)))
