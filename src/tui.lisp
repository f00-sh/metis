;;;; tui.lisp — pure Common Lisp product TUI (ANSI/Unicode)
;;;;
;;;; Dynamic layout: every frame re-reads terminal rows×cols and redraws.
;;;; Screen buffer (rows strings of length cols) → one dump (no mid-line wrap mess).
;;;;
;;;;   ┌──── chat ─────────┬── status ──┐
;;;;   │                   ├── symbols ─┤  (collapsible tree; REPL is Ctrl+R popup)
;;;;   └──── input ─────────────────────┘
;;;;
;;;; Keys: Tab=insert · Ctrl+T=chat↔symbols · Ctrl+R=REPL popup · Ctrl+S=settings
;;;;       Enter=send · Ctrl+N=newline · /quit
(in-package :metis)

(defparameter *tui-use-color* t)
(defparameter *tui-use-unicode* t)
(defparameter *tui-splash-frames* 16)
(defparameter *tui-splash-delay* 0.032d0)
(defparameter *tui-quit-process* t
  "When T (product CLI), leaving the TUI kills the Lisp process → shell prompt.
   Set NIL only when embedding tui-run inside a longer Lisp session.")
;; Soft floors so panes don't collapse; NO artificial max — fill the real display.
(defparameter *tui-min-rows* 8)
(defparameter *tui-min-cols* 40)
(defvar *tui-resized-p* nil
  "Set by SIGWINCH / size poll when the terminal changed.")
(defvar *tui-cached-rows* nil)
(defvar *tui-cached-cols* nil)

;;; ------------------------------------------------------------------
;;; ANSI
;;; ------------------------------------------------------------------

(defun %tui-tty-p ()
  (ignore-errors
    (and (interactive-stream-p *standard-input*)
         (interactive-stream-p *standard-output*))))

(defun %tui-esc (code)
  (format nil "~C[~A" #\Esc code))

(defun %tui-ansi-attr (attr)
  "ANSI SGR for logical ATTR keywords used in the screen buffer."
  (if (not *tui-use-color*)
      ""
      (case attr
        ((:default nil) (%tui-esc "0m"))
        (:dim (%tui-esc "2;37m"))
        (:bold (%tui-esc "1;37m"))
        ;; pane chrome
        (:border (%tui-esc "34m"))              ; blue idle border
        (:border-focus (%tui-esc "1;96m"))      ; bright cyan focus border
        (:title (%tui-esc "1;34m"))
        (:title-focus (%tui-esc "1;30;46m"))    ; black on cyan — focused pane
        ;; chat roles (no you>/metis> needed)
        (:user (%tui-esc "1;93m"))             ; bright yellow — you
        (:metis (%tui-esc "1;92m"))            ; bright green — metis
        (:sys (%tui-esc "2;37m"))              ; dim system
        ;; math worked solution — three focus bands
        (:math-work (%tui-esc "2;36m"))        ; dim cyan — the work / operation
        (:math-mid (%tui-esc "1;93m"))         ; bright yellow — step result
        (:math-final (%tui-esc "1;92m"))       ; bright green — final answer
        (:math-arrow (%tui-esc "2;37m"))       ; dim "→" separator
        ;; status pane
        (:status-key (%tui-esc "1;95m"))       ; bright magenta labels
        (:status-val (%tui-esc "97m"))         ; bright white values
        (:status-live (%tui-esc "1;92m"))      ; LIVE
        (:status-off (%tui-esc "1;91m"))       ; off
        (:status-hi (%tui-esc "1;96m"))        ; highlight numbers
        ;; repl
        (:repl-in (%tui-esc "1;96m"))          ; input
        (:repl-out (%tui-esc "1;93m"))         ; => result
        (:repl-err (%tui-esc "1;91m"))
        (:repl-meta (%tui-esc "2;36m"))
        ;; input bar — high contrast so typing is always visible
        (:input (%tui-esc "1;30;47m"))         ; black on white (typed text)
        (:input-bg (%tui-esc "47m"))           ; white bar background
        (:input-label-chat (%tui-esc "1;30;46m")) ; black on cyan label
        (:input-label-repl (%tui-esc "1;30;43m")) ; black on yellow label
        (:help (%tui-esc "2;90m"))
        (:cursor (%tui-esc "1;37;40m"))        ; white on black block cursor
        ;; symbols tree
        (:sym-cat (%tui-esc "1;95m"))          ; magenta categories
        (:sym-on (%tui-esc "1;92m"))           ; green loaded
        (:sym-off (%tui-esc "2;37m"))          ; dim unloaded
        (:sym-sel (%tui-esc "1;30;46m"))       ; selection reverse cyan
        (:sym-desc (%tui-esc "2;36m"))         ; dim cyan description
        (:popup-border (%tui-esc "1;93m"))     ; yellow popup chrome
        (:popup-title (%tui-esc "1;30;43m"))
        (:popup-bg (%tui-esc "40m"))
        (:settings-on (%tui-esc "1;92m"))
        (:settings-off (%tui-esc "1;91m"))
        (t (%tui-esc "0m")))))

(defun %tui-clear ()
  (let ((o (%tui-io-out)))
    (write-string (%tui-esc "2J") o)
    (write-string (%tui-esc "H") o)
    (force-output o)))

(defun %tui-hide-cursor ()
  (let ((o (%tui-io-out)))
    (write-string (%tui-esc "?25l") o)
    (force-output o)))

(defun %tui-show-cursor ()
  (let ((o (%tui-io-out)))
    (write-string (%tui-esc "?25h") o)
    (force-output o)))

(defun %tui-goto (row col)
  (write-string (%tui-esc (format nil "~D;~DH" (max 1 row) (max 1 col)))
                (%tui-io-out)))

(defun %tui-parse-dim (x &optional (default nil))
  "Parse a terminal dimension. 0 / negative / garbage → DEFAULT (may be NIL)."
  (let ((n (cond
             ((integerp x) x)
             ((stringp x)
              (ignore-errors
                (parse-integer (string-trim '(#\Space #\Tab #\Newline #\Return) x)
                               :junk-allowed t)))
             (t nil))))
    (if (and (integerp n) (plusp n)) n default)))

#+sbcl
(defun %tui-ioctl-winsize (fd)
  "TIOCGWINSZ (0x5413) on FD → (values rows cols) or NIL."
  (ignore-errors
    (when (and fd (integerp fd) (>= fd 0))
      (sb-alien:with-alien ((buf (array (sb-alien:unsigned 8) 8)))
        (dotimes (i 8) (setf (sb-alien:deref buf i) 0))
        (multiple-value-bind (ok errno)
            (sb-unix:unix-ioctl fd #x5413 (sb-alien:alien-sap buf))
          (declare (ignore errno))
          (when ok
            (let ((rows (logior (sb-alien:deref buf 0)
                                (ash (sb-alien:deref buf 1) 8)))
                  (cols (logior (sb-alien:deref buf 2)
                                (ash (sb-alien:deref buf 3) 8))))
              (when (and (plusp rows) (plusp cols) (< rows 10000) (< cols 10000))
                (values rows cols)))))))))

#-sbcl
(defun %tui-ioctl-winsize (fd)
  (declare (ignore fd))
  nil)

(defun %tui-ioctl-size ()
  "Best ioctl size from stdin/out/err or /dev/tty."
  #+sbcl
  (or
   (dolist (stream (list *standard-input* *standard-output* *error-output*) nil)
     (let ((fd (ignore-errors
                 (and (typep stream 'sb-sys:fd-stream)
                      (sb-sys:fd-stream-fd stream)))))
       (multiple-value-bind (r c) (%tui-ioctl-winsize fd)
         (when (and r c) (return (cons r c))))))
   (ignore-errors
     (with-open-file (tty "/dev/tty" :direction :io :if-exists :overwrite)
       (multiple-value-bind (r c)
           (%tui-ioctl-winsize (sb-sys:fd-stream-fd tty))
         (and r c (cons r c))))))
  #-sbcl
  nil)

(defun %tui-stty-size ()
  "Parse `stty size` from controlling tty."
  (ignore-errors
    (let* ((out (uiop:run-program
                 '("sh" "-c"
                   "stty size </dev/tty 2>/dev/null || stty size 2>/dev/null")
                 :output :string :ignore-error-status t :error-output nil))
           (parts (cl-ppcre:split "\\s+"
                                  (string-trim '(#\Space #\Newline #\Tab #\Return)
                                               (or out "")))))
      (when (>= (length parts) 2)
        (let ((r (%tui-parse-dim (first parts)))
              (c (%tui-parse-dim (second parts))))
          (when (and r c) (cons r c)))))))

(defun %tui-env-size ()
  (let ((r (%tui-parse-dim (uiop:getenv "LINES")))
        (c (%tui-parse-dim (uiop:getenv "COLUMNS"))))
    (when (and r c) (cons r c))))

(defun %tui-ansi-query-size ()
  "Ask the terminal for size via CPR (cursor position report).
   Move to 9999;9999, read actual position = rows;cols."
  (ignore-errors
    (when (%tui-tty-p)
      ;; drain pending input
      (loop while (listen *standard-input*) do (read-char-no-hang *standard-input*))
      (write-string (format nil "~C[s~C[9999;9999H~C[6n~C[u" #\Esc #\Esc #\Esc #\Esc))
      (force-output)
      (let ((deadline (+ (get-internal-real-time)
                         (* internal-time-units-per-second 0.15)))
            (buf (make-array 32 :element-type 'character :fill-pointer 0 :adjustable t)))
        (loop while (< (get-internal-real-time) deadline) do
          (let ((ch (read-char-no-hang *standard-input* nil nil)))
            (if ch
                (vector-push-extend ch buf)
                (sleep 0.005)))
          (when (and (plusp (length buf)) (char= (char buf (1- (length buf))) #\R))
            (return)))
        (let* ((s (coerce buf 'string))
               (m (nth-value 0 (cl-ppcre:scan-to-strings
                                "\\x1b\\[(\\d+);(\\d+)R" s))))
          (when m
            (cl-ppcre:register-groups-bind (rs cs)
                ("\\x1b\\[(\\d+);(\\d+)R" s)
              (let ((r (%tui-parse-dim rs))
                    (c (%tui-parse-dim cs)))
                (when (and r c) (cons r c))))))))))

(defun %tui-term-size-raw ()
  "Unclamped live size: ioctl → stty → env → ANSI query → 24×80."
  (let ((pair (or (%tui-ioctl-size)
                  (%tui-stty-size)
                  (%tui-env-size)
                  ;; ANSI only if we have no better idea and are interactive
                  (and (null *tui-cached-rows*) (%tui-ansi-query-size))
                  (and *tui-cached-rows* *tui-cached-cols*
                       (cons *tui-cached-rows* *tui-cached-cols*))
                  (cons 24 80))))
    (values (car pair) (cdr pair))))

(defun %tui-term-size ()
  "Live terminal size (values rows cols). True display size, re-queried every call.
   Soft min only so UI doesn't go negative; never caps the max — dynamic."
  (multiple-value-bind (rows cols) (%tui-term-size-raw)
    (let ((rows (max *tui-min-rows* (or rows 24)))
          (cols (max *tui-min-cols* (or cols 80))))
      (unless (and (eql rows *tui-cached-rows*) (eql cols *tui-cached-cols*))
        (setf *tui-resized-p* t
              *tui-cached-rows* rows
              *tui-cached-cols* cols))
      (values rows cols))))

(defun %tui-install-sigwinch! ()
  "Repaint flag on terminal resize (SBCL)."
  #+sbcl
  (ignore-errors
    (sb-sys:enable-interrupt
     sb-unix:sigwinch
     (lambda (signal info context)
       (declare (ignore signal info context))
       (setf *tui-resized-p* t)
       ;; bust cache so next paint re-ioctls
       (setf *tui-cached-rows* nil *tui-cached-cols* nil))))
  #-sbcl nil)

(defvar *tui-in* nil
  "Character input stream for the TUI (/dev/tty UTF-8).")
(defvar *tui-out* nil
  "Character output stream for the TUI (/dev/tty UTF-8).")
(defvar *tui-in-fd* nil
  "OS fd for *tui-in* (SBCL).")
(defvar *tui-key-rev* 9
  "Bump when key path changes — proves fresh load.")

(defun %tui-io-in ()
  (or *tui-in* *standard-input*))

(defun %tui-io-out ()
  (or *tui-out* *standard-output*))

(defun %tui-termios-raw! (fd)
  "Force termios: no ICANON, no ECHO, VMIN=0 VTIME=0. SBCL sb-posix."
  #+sbcl
  (ignore-errors
    (require 'sb-posix)
    (when (and fd (integerp fd) (>= fd 0))
      (let ((tty (sb-posix:tcgetattr fd)))
        (setf (sb-posix:termios-lflag tty)
              (logand (sb-posix:termios-lflag tty)
                      (lognot (logior sb-posix:icanon
                                      sb-posix:echo
                                      sb-posix:echoe
                                      sb-posix:echok
                                      sb-posix:echonl
                                      sb-posix:isig))))
        (setf (sb-posix:termios-iflag tty)
              (logand (sb-posix:termios-iflag tty)
                      (lognot (logior sb-posix:ixon sb-posix:ixoff))))
        (setf (sb-posix:termios-cc tty sb-posix:vmin) 0
              (sb-posix:termios-cc tty sb-posix:vtime) 0)
        (sb-posix:tcsetattr fd sb-posix:tcsadrain tty)
        t)))
  #-sbcl nil)

(defun %tui-open-tty! ()
  "UTF-8 character I/O on /dev/tty (separate in/out)."
  (ignore-errors
    (when (probe-file "/dev/tty")
      (%tui-close-tty!)
      (let (in out)
        (unwind-protect
             (progn
               (setf in (open "/dev/tty" :direction :input
                              :element-type 'character
                              :external-format :utf-8
                              :if-does-not-exist :error)
                     out (open "/dev/tty" :direction :output
                               :if-exists :overwrite
                               :element-type 'character
                               :external-format :utf-8))
               (setf *tui-in* in
                     *tui-out* out
                     *tui-in-fd* #+sbcl (ignore-errors (sb-sys:fd-stream-fd in))
                                 #-sbcl nil)
               (setf in nil out nil)
               t)
          (when in (ignore-errors (close in :abort t)))
          (when out (ignore-errors (close out :abort t))))))))

(defun %tui-close-tty! ()
  (let ((in *tui-in*) (out *tui-out*))
    (setf *tui-in* nil *tui-out* nil *tui-in-fd* nil)
    (when (and in (open-stream-p in))
      (ignore-errors (close in :abort t)))
    (when (and out (not (eq out in)) (open-stream-p out))
      (ignore-errors (close out :abort t))))
  nil)

(defun %tui-raw-on ()
  (%tui-open-tty!)
  ;; 1) stty (portable)
  (ignore-errors
    (uiop:run-program
     '("sh" "-c"
       "stty raw -echo -echoe -echok -echoctl -icanon -isig -ixon min 0 time 0 </dev/tty 2>/dev/null; stty -echo -icanon min 0 time 0 </dev/tty 2>/dev/null; true")
     :ignore-error-status t :output nil :error-output nil))
  ;; 2) termios on our actual fd (belt)
  (ignore-errors (%tui-termios-raw! *tui-in-fd*))
  #+sbcl
  (ignore-errors
    (when *tui-in-fd*
      (%tui-termios-raw! *tui-in-fd*)))
  ;; NO hardware cursor ever while TUI runs — Tab moves the hardware cursor
  ;; and leaves a visual gap that is NOT in our buffer (backspace can't kill it).
  (%tui-hide-cursor)
  (ignore-errors
    (write-string (%tui-esc "?2004l") (%tui-io-out)) ; bracketed paste off
    (write-string (%tui-esc ">4;0m") (%tui-io-out))  ; modifyOtherKeys off
    (write-string (%tui-esc "?1000l") (%tui-io-out)) ; mouse off
    (write-string (%tui-esc "?7l") (%tui-io-out))    ; no autowrap surprises
    (write-string (%tui-esc "?25l") (%tui-io-out))    ; cursor hide
    (force-output (%tui-io-out)))
  (%tui-install-sigwinch!))

(defun %tui-raw-off ()
  (ignore-errors
    (write-string (%tui-esc "?2004l") (%tui-io-out))
    (write-string (%tui-esc ">4;0m") (%tui-io-out))
    (write-string (%tui-esc "?7h") (%tui-io-out))
    (write-string (%tui-esc "?25h") (%tui-io-out))
    (write-string (%tui-esc "0m") (%tui-io-out))
    (force-output (%tui-io-out)))
  (ignore-errors
    (uiop:run-program
     '("sh" "-c" "stty sane </dev/tty 2>/dev/null || stty sane")
     :ignore-error-status t :output nil :error-output nil))
  (%tui-close-tty!))

(defun %tui-byte-ready-p ()
  "T if at least one input char/byte is waiting."
  (ignore-errors (listen (%tui-io-in))))

(defun %tui-read-byte-nohang ()
  "One input byte (0–255) or NIL — never blocks."
  (ignore-errors
    (let ((ch (read-char-no-hang (%tui-io-in) nil nil)))
      (and ch (logand (char-code ch) #xff)))))

(defun %tui-decode-utf8-from-b0 (b0)
  "Consume continuation bytes after leading byte B0 → character or NIL."
  (labels ((need (n)
             (let ((bytes nil) (ok t))
               (dotimes (i n)
                 (let ((b (%tui-read-byte-nohang)))
                   (if (and b (<= #x80 b #xbf))
                       (push b bytes)
                       (return (setf ok nil)))))
               (when ok (nreverse bytes)))))
    (cond
      ((< b0 #x80) (code-char b0))
      ((<= #xc2 b0 #xdf)
       (let ((rest (need 1)))
         (when rest
           (code-char (logior (ash (logand b0 #x1f) 6)
                              (logand (first rest) #x3f))))))
      ((<= #xe0 b0 #xef)
       (let ((rest (need 2)))
         (when rest
           (code-char (logior (ash (logand b0 #x0f) 12)
                              (ash (logand (first rest) #x3f) 6)
                              (logand (second rest) #x3f))))))
      ((<= #xf0 b0 #xf4)
       (let ((rest (need 3)))
         (when rest
           (code-char (logior (ash (logand b0 #x07) 18)
                              (ash (logand (first rest) #x3f) 12)
                              (ash (logand (second rest) #x3f) 6)
                              (logand (third rest) #x3f))))))
      (t nil))))

(defun %tui-csi-event (s)
  "Map full CSI body (after ESC [) to a key event. Consumes modifyOtherKeys etc.
   Never returns NIL for known garbage sequences — :ignore so nothing is inserted."
  (or
   ;; modifyOtherKeys / xterm: ESC [ 27 ; <mod> ; <key> ~
   (cl-ppcre:register-groups-bind (mod key)
       ("^27;([0-9]+);([0-9]+)~$" s)
     (let ((k (ignore-errors (parse-integer key)))
           (m (or mod "1")))
       (cond
         ((= k 13)                      ; Enter family
          (if (member m '("2" "4" "6" "8") :test #'string=) :newline :enter))
         ((= k 9) (list :insert (string #\Tab))) ; Tab with mods → still tab data
         ((= k 127) :backspace)
         ((= k 8) :backspace)
         ((and (= k 116) (string= m "5")) :focus-toggle) ; Ctrl+T via CSI
         (t :ignore))))
   ;; CSI u / kitty: ESC [ <key> ; <mod> u
   (cl-ppcre:register-groups-bind (key mod)
       ("^([0-9]+);([0-9]+)u$" s)
     (let ((k (ignore-errors (parse-integer key)))
           (m (or mod "1")))
       (cond
         ((= k 13)
          (if (member m '("2" "4" "6" "8") :test #'string=) :newline :enter))
         ((= k 9) (list :insert (string #\Tab)))
         ((= k 127) :backspace)
         (t :ignore))))
   (cl-ppcre:register-groups-bind (key)
       ("^([0-9]+)u$" s)
     (let ((k (ignore-errors (parse-integer key))))
       (cond ((= k 13) :enter)
             ((= k 9) (list :insert (string #\Tab)))
             (t :ignore))))
   (cond
     ((string= s "A") :up)
     ((string= s "B") :down)
     ((string= s "C") :right)
     ((string= s "D") :left)
     ((string= s "5~") :page-up)
     ((string= s "6~") :page-down)
     ((string= s "Z") (list :insert (string #\Tab))) ; Shift+Tab → tab char (data)
     ((string= s "12~") :focus-toggle) ; F2 still focus
     ;; bare CSI fragment that looks like leaked modifyOtherKeys without ESC
     ((cl-ppcre:scan "^27;[0-9]+;[0-9]+~$" s) :ignore)
     ((cl-ppcre:scan "^[0-9;]*[~uABCDEFHPQS]$" s) :ignore)
     (t :ignore))))

(defun %tui-read-csi-body ()
  "Read CSI parameter/intermediate/final bytes after ESC [. Waits up to ~80ms."
  (let ((buf (make-array 48 :element-type 'character :fill-pointer 0 :adjustable t))
        (deadline (+ (get-internal-real-time)
                     (floor (* 0.08 internal-time-units-per-second)))))
    (loop
      (let ((b (%tui-read-byte-nohang)))
        (cond
          (b
           (let ((ch (code-char b)))
             (vector-push-extend ch buf)
             (when (or (char<= #\@ ch #\~))
               (return (coerce buf 'string)))))
          ((>= (get-internal-real-time) deadline)
           (return (coerce buf 'string)))
          (t (sleep 0.002)))))))

(defun %tui-decode-escape-bytes ()
  "After ESC (0x1b). Fully consume CSI — never leak [27;2;13~ into text."
  (let ((deadline (+ (get-internal-real-time)
                     (floor (* 0.05 internal-time-units-per-second))))
        (b2 nil))
    (loop while (and (null b2) (< (get-internal-real-time) deadline))
          do (setf b2 (%tui-read-byte-nohang))
             (unless b2 (sleep 0.002)))
    (cond
      ((null b2) :escape)
      ((= b2 #x5b)                      ; [
       (%tui-csi-event (%tui-read-csi-body)))
      ((= b2 #x4f)                      ; SS3 (application keys)
       (let ((b3 nil)
             (d2 (+ (get-internal-real-time)
                    (floor (* 0.03 internal-time-units-per-second)))))
         (loop while (and (null b3) (< (get-internal-real-time) d2))
               do (setf b3 (%tui-read-byte-nohang))
                  (unless b3 (sleep 0.001)))
         :ignore))
      ((or (= b2 13) (= b2 10)) :enter)
      ;; ESC alone + letter — not a chord for focus; ignore meta
      (t :ignore))))

(defun %tui-ctrl-event (b)
  "Ctrl+key (ASCII 1–26). Immediate TUI commands — never typed as text."
  (case b
    (3  :quit)            ; Ctrl+C
    (4  :quit)            ; Ctrl+D
    (8  :backspace)       ; Ctrl+H
    (9  nil)              ; Tab = data
    (10 :enter)           ; Ctrl+J
    (11 :clear-input)     ; Ctrl+K
    (12 :focus-toggle)    ; Ctrl+L
    (13 :enter)           ; Ctrl+M
    (14 :newline)         ; Ctrl+N
    (15 :focus-toggle)    ; Ctrl+O
    (18 :popup-repl)      ; Ctrl+R → REPL popup
    (19 :popup-settings)  ; Ctrl+S → settings
    (20 :focus-toggle)    ; Ctrl+T chat↔symbols
    (21 :clear-input)     ; Ctrl+U
    (23 :clear-input)     ; Ctrl+W
    (t  :ignore)))

(defun %tui-byte-event (b)
  "Map one raw byte to a key event.
   Tab(9) = insert tab character. Ctrl+T(20) = focus-toggle immediately."
  (cond
    ((null b) nil)
    ((= b 9)  (list :insert (string #\Tab))) ; TAB IS DATA
    ((= b 27) (%tui-decode-escape-bytes))
    ((= b 127) :backspace)
    ((= b 8)   :backspace)
    ((or (= b 13) (= b 10)) :enter)
    ((<= 1 b 26)
     (or (%tui-ctrl-event b) :ignore))
    ((< b 32) :ignore)
    ((< b 128) (list :insert (string (code-char b))))
    (t
     (let ((ch (%tui-decode-utf8-from-b0 b)))
       (if ch (list :insert (string ch)) :ignore)))))

(defvar *tui-enter-slop-until* 0)

(defun %tui-drain-pending! (&optional (ms 0.06d0))
  "Drop any pending tty bytes (post-Enter CSI junk, stray CR/LF, etc.)."
  (let ((deadline (+ (get-internal-real-time)
                     (floor (* ms internal-time-units-per-second)))))
    (loop while (< (get-internal-real-time) deadline) do
      (if (%tui-read-byte-nohang)
          nil
          (sleep 0.002)))))

(defun %tui-finish-enter ()
  "One physical Enter → one :enter. Swallow CR/LF + leftover CSI completely."
  (sleep 0.008d0)
  (%tui-drain-pending! 0.08d0)
  (setf *tui-enter-slop-until*
        (+ (get-internal-real-time)
           (floor (* 0.20 internal-time-units-per-second))))
  :enter)

(defun %tui-drain-paste (first-byte)
  "Drain paste. Keeps Tab. Drops C0 controls. If ESC seen, stop (CSI handled next)."
  (let ((had-enter nil)
        (out (make-array 64 :element-type 'character :fill-pointer 0 :adjustable t)))
    (labels ((take-byte (b)
               (cond
                 ((null b) nil)
                 ((= b 27) nil)         ; leave ESC for next key read
                 ((or (= b 10) (= b 13))
                  (setf had-enter t) nil)
                 ((= b 9)
                  (vector-push-extend #\Tab out) t)
                 ((< b 32) t)           ; drop other controls
                 ((< b 128)
                  (vector-push-extend (code-char b) out) t)
                 (t
                  (let ((ch (%tui-decode-utf8-from-b0 b)))
                    (when ch (vector-push-extend ch out))
                    t)))))
      (take-byte first-byte)
      (loop while (%tui-byte-ready-p)
            for b = (%tui-read-byte-nohang)
            while b
            do (unless (take-byte b) (return))))
    (values (coerce out 'string) had-enter)))

(defun %tui-read-key-timeout (seconds)
  "Poll raw tty. Tab=insert. Ctrl+T=focus now. CSI fully consumed.
   Bare '[' that starts a CSI fragment is never inserted as text."
  (let ((deadline (+ (get-internal-real-time)
                     (floor (* seconds internal-time-units-per-second)))))
    (loop
      (when *tui-resized-p* (return :resize))
      (let ((b (%tui-read-byte-nohang)))
        (when b
          (when (and (or (= b 10) (= b 13))
                     (< (get-internal-real-time) *tui-enter-slop-until*))
            (setf b nil))
          (when b
            (return
              (cond
                ((= b 9) (list :insert (string #\Tab)))
                ((or (= b 13) (= b 10)) (%tui-finish-enter))
                ((or (= b 127) (= b 8)) :backspace)
                ((= b 27) (%tui-decode-escape-bytes))
                ;; bare CSI start without ESC (common after partial drain)
                ((= b #x5b)
                 (let ((ev (%tui-csi-event (%tui-read-csi-body))))
                   (if (eq ev :ignore) :ignore ev)))
                ((<= 1 b 26)
                 (or (%tui-ctrl-event b) :ignore))
                ((< b 32) :ignore)
                ;; paste burst only for letters/space (not [ or digits → CSI debris)
                ((and (%tui-byte-ready-p) (>= b 32)
                      (or (alpha-char-p (code-char b))
                          (char= (code-char b) #\Space)))
                 (multiple-value-bind (text had-enter)
                     (%tui-drain-paste b)
                   (let ((text (%tui-sanitize-input text)))
                     (cond
                       (had-enter (list :paste-send text))
                       ((zerop (length text)) :ignore)
                       (t (list :paste text))))))
                (t (%tui-byte-event b)))))))
      (when (>= (get-internal-real-time) deadline)
        (return :timeout))
      (sleep 0.008))))

(defun %tui-read-key ()
  "Blocking-ish key read (used by tests)."
  (or (%tui-read-key-timeout 3600) :timeout))

(defun %tui-strip-csi-garbage (text)
  "Remove leaked CSI / modifyOtherKeys fragments from buffer text.
   Covers full ESC sequences and bare [27;2;13~ style leaks."
  (let* ((esc (string #\Esc))
         (s (or text "")))
    ;; full ESC CSI / SS3 (use real Esc char — \x1b is unreliable in cl-ppcre)
    (setf s (cl-ppcre:regex-replace-all
             (concatenate 'string esc "\\[[0-9;?]*[ -/]*[@-~]") s ""))
    (setf s (cl-ppcre:regex-replace-all
             (concatenate 'string esc "O[A-Za-z]") s ""))
    ;; bare modifyOtherKeys / kitty (ESC already lost): [27;2;13~ or 27;2;13~
    (setf s (cl-ppcre:regex-replace-all "\\[27;[0-9]+;[0-9]+~" s ""))
    (setf s (cl-ppcre:regex-replace-all "(?<![0-9A-Za-z])27;[0-9]+;[0-9]+~" s ""))
    (setf s (cl-ppcre:regex-replace-all "\\[[0-9]+;[0-9]+u" s ""))
    ;; lone ESC leftover
    (setf s (remove #\Esc s))
    s))

(defun %tui-sanitize-input (text)
  "Keep printable + Tab + newline. Strip CR, DEL, C0 (except Tab/NL), CSI garbage."
  (let ((s (%tui-strip-csi-garbage (or text ""))))
    (with-output-to-string (o)
      (loop for c across s
            for code = (char-code c)
            do (cond
                 ((= code 9) (write-char #\Tab o))       ; KEEP TAB
                 ((= code 10) (write-char #\Newline o))
                 ((= code 13) nil)
                 ((= code 127) nil)
                 ((< code 32) nil)
                 (t (write-char c o)))))))

(defun %tui-set-input! (app text)
  "Set input buffer (Tab allowed; CSI garbage stripped)."
  (setf (tui-input app) (%tui-sanitize-input (or text ""))))

(defun %tui-input-append (app text)
  "Append TEXT. Tab is kept. Always updates buffer."
  (let ((clean (%tui-sanitize-input text)))
    (%tui-set-input! app
                     (concatenate 'string
                                  (%tui-sanitize-input (or (tui-input app) ""))
                                  clean))))

;;; ------------------------------------------------------------------
;;; Glyphs + string helpers (display width = string length for BMP/box)
;;; ------------------------------------------------------------------

(defun %tui-g ()
  (if *tui-use-unicode*
      '(:tl "┌" :tr "┐" :bl "└" :br "┘" :h "─" :v "│"
        :tee-l "├" :tee-r "┤" :tee-t "┬" :tee-b "┴")
      '(:tl "+" :tr "+" :bl "+" :br "+" :h "-" :v "|"
        :tee-l "+" :tee-r "+" :tee-t "+" :tee-b "+")))

(defun %tui-rep (s n)
  (with-output-to-string (o)
    (dotimes (_ (max 0 n)) (write-string s o))))

(defun %tui-trunc (s width)
  "Truncate S to WIDTH (no padding)."
  (let* ((s (or s ""))
         (w (max 0 width))
         (len (length s)))
    (cond
      ((zerop w) "")
      ((<= len w) s)
      ((= w 1) (subseq s 0 1))
      (t (concatenate 'string (subseq s 0 (1- w)) "…")))))

(defun %tui-clip (s width)
  "Pad/truncate S to exactly WIDTH."
  (let* ((s (%tui-trunc s width))
         (len (length s))
         (w (max 0 width)))
    (if (>= len w)
        s
        (concatenate 'string s (make-string (- w len) :initial-element #\Space)))))

(defun %tui-wrap (text width)
  (let ((width (max 4 width))
        (out nil))
    (dolist (para (cl-ppcre:split "\\n" (or text "")))
      (if (zerop (length para))
          (push "" out)
          (let ((rest para))
            (loop while (plusp (length rest)) do
              (if (<= (length rest) width)
                  (progn (push rest out) (setf rest ""))
                  (let ((cut width)
                        (sp (position #\Space rest :from-end t :end (min width (length rest)))))
                    (when (and sp (> sp (floor width 3))) (setf cut (1+ sp)))
                    (push (string-right-trim '(#\Space) (subseq rest 0 cut)) out)
                    (setf rest (string-left-trim '(#\Space) (subseq rest cut)))))))))
    (nreverse out)))

;;; ------------------------------------------------------------------
;;; Color screen buffer — chars + per-cell attr, flush with ANSI
;;; ------------------------------------------------------------------

(defstruct (tui-scr (:conc-name ts-))
  rows cols
  chars   ; vector of simple-strings
  attrs)  ; vector of (simple-vector attr) length cols

(defun %tui-make-screen (rows cols)
  (let ((chars (make-array rows))
        (attrs (make-array rows)))
    (dotimes (i rows)
      (setf (aref chars i) (make-string cols :initial-element #\Space)
            (aref attrs i) (make-array cols :initial-element :default)))
    (make-tui-scr :rows rows :cols cols :chars chars :attrs attrs)))

(defun %tui-scr-put (scr row col text &key (fg :default))
  "Write TEXT at 0-based row/col with FG attr."
  (let ((rows (ts-rows scr))
        (cols (ts-cols scr))
        (text (or text "")))
    (when (and (>= row 0) (< row rows) (>= col 0) (< col cols))
      (let* ((line (aref (ts-chars scr) row))
             (att (aref (ts-attrs scr) row))
             (n (min (length text) (- cols col))))
        (when (plusp n)
          (replace line text :start1 col :end1 (+ col n) :start2 0 :end2 n)
          (dotimes (i n)
            (setf (aref att (+ col i)) fg)))))))

(defun %tui-scr-hline (scr row col n ch &key (fg :default))
  (when (and (>= row 0) (< row (ts-rows scr)))
    (let* ((cols (ts-cols scr))
           (line (aref (ts-chars scr) row))
           (att (aref (ts-attrs scr) row))
           (ch (if (characterp ch) ch (char (string ch) 0))))
      (loop for i from 0 below n
            for c = (+ col i)
            while (< c cols)
            when (>= c 0)
              do (setf (char line c) ch
                       (aref att c) fg)))))

(defun %tui-scr-fill (scr row col width height &key (ch #\Space) (fg :default))
  (dotimes (i height)
    (%tui-scr-hline scr (+ row i) col width ch :fg fg)))

(defun %tui-scr-box (scr row col height width title &key (focus nil))
  "Draw box. FOCUS T → bright border + reverse title."
  (let* ((g (%tui-g))
         (hch (char (getf g :h) 0))
         (bfg (if focus :border-focus :border))
         (tfg (if focus :title-focus :title))
         (rows (ts-rows scr))
         (cols (ts-cols scr))
         (height (max 2 (min height (- rows row))))
         (width (max 3 (min width (- cols col))))
         (inner (- width 2))
         (ttl (format nil "~A~A~A"
                      (if focus "▶" " ")
                      (or title "")
                      (if focus "◀" " ")))
         (ttl (if (> (length ttl) inner) (subseq ttl 0 inner) ttl))
         (pad (- inner (length ttl)))
         (lp (floor pad 2))
         (rp (- pad lp)))
    (%tui-scr-put scr row col (getf g :tl) :fg bfg)
    (%tui-scr-hline scr row (1+ col) lp hch :fg bfg)
    (%tui-scr-put scr row (+ col 1 lp) ttl :fg tfg)
    (%tui-scr-hline scr row (+ col 1 lp (length ttl)) rp hch :fg bfg)
    (%tui-scr-put scr row (+ col width -1) (getf g :tr) :fg bfg)
    (loop for r from 1 below (1- height) do
      (%tui-scr-put scr (+ row r) col (getf g :v) :fg bfg)
      (%tui-scr-put scr (+ row r) (+ col width -1) (getf g :v) :fg bfg))
    (%tui-scr-put scr (+ row height -1) col (getf g :bl) :fg bfg)
    (%tui-scr-hline scr (+ row height -1) (1+ col) inner hch :fg bfg)
    (%tui-scr-put scr (+ row height -1) (+ col width -1) (getf g :br) :fg bfg)
    (values height width)))

(defun %tui-scr-flush (scr)
  "Write screen with ANSI color runs to the TUI tty."
  (let ((o (%tui-io-out)))
    (%tui-goto 1 1)
    (write-string (%tui-esc "0J") o)
    (%tui-goto 1 1)
    (let ((rows (ts-rows scr))
          (cols (ts-cols scr))
          (cur nil))
      (dotimes (r rows)
        (let ((line (aref (ts-chars scr) r))
              (att (aref (ts-attrs scr) r)))
          (dotimes (c cols)
            (let ((a (aref att c))
                  (ch (char line c)))
              (unless (eq a cur)
                (write-string (%tui-ansi-attr a) o)
                (setf cur a))
              ;; NEVER write Tab/controls to the tty — they wreck columns
              (write-char (if (or (char= ch #\Tab)
                                  (< (char-code ch) 32)
                                  (= (char-code ch) 127))
                              #\Space
                              ch)
                          o)))
          (write-string (%tui-ansi-attr :default) o)
          (setf cur :default)
          (when (< r (1- rows))
            (write-char #\Newline o)))))
    (force-output o)))

;;; ------------------------------------------------------------------
;;; Splash — minimal CLI (Claude/Codex/Grok-adjacent), not a rave flyer
;;; monochrome wordmark · one accent · thin rule · version line
;;; ------------------------------------------------------------------

(defun %tui-center (cols text)
  (max 0 (floor (- cols (length text)) 2)))

(defun %tui-splash-put-centered (scr row cols text &key (fg :default))
  (%tui-scr-put scr row (%tui-center cols text) text :fg fg))

(defun %tui-splash-frame (frame total)
  "Quiet boot splash. Frame 0..TOTAL-1, single accent, no rainbow."
  (multiple-value-bind (rows cols) (%tui-term-size)
    (let* ((scr (%tui-make-screen rows cols))
           (ver (ignore-errors (metis-version-string)))
           (ver (or ver "Metis"))
           ;; phases (of total frames)
           (p (if (plusp total) (/ (float frame) (float (max 1 (1- total)))) 1.0))
           (name "metis")
           (tag "cognitive architecture")
           (rule-w (min 28 (max 10 (- cols 16))))
           (rule-fill (max 0 (min rule-w (floor (* rule-w p)))))
           (rule (concatenate 'string
                              (make-string rule-fill :initial-element
                                           (if *tui-use-unicode* #\─ #\-))
                              (make-string (max 0 (- rule-w rule-fill))
                                           :initial-element #\Space)))
           ;; vertical block centered as a unit (~5 lines)
           (block-h 5)
           (r0 (max 1 (floor (- rows block-h 2) 2)))
           ;; name: dim early, then crisp white
           (name-fg (if (< p 0.25) :dim :bold))
           (tag-fg (if (< p 0.45) :dim :dim))
           (rule-fg (if (< p 0.55) :border :border-focus))
           (ver-fg (if (< p 0.7) :dim :status-val)))
      ;; wordmark — letterspaced, lowercase, no FIGlet circus
      (%tui-splash-put-centered scr r0 cols name :fg name-fg)
      ;; growing hairline (the only “animation”)
      (when (>= p 0.15)
        (%tui-splash-put-centered scr (+ r0 1) cols
                                  (string-right-trim '(#\Space) rule)
                                  :fg rule-fg))
      ;; tagline
      (when (>= p 0.35)
        (%tui-splash-put-centered scr (+ r0 3) cols tag :fg tag-fg))
      ;; version — quiet
      (when (>= p 0.55)
        (%tui-splash-put-centered scr (+ r0 4) cols ver :fg ver-fg))
      ;; trailing pulse: one dim mid-dot, not a spinner party
      (when (and (>= p 0.85) (evenp frame))
        (%tui-splash-put-centered scr (min (1- rows) (+ r0 6)) cols "·" :fg :dim))
      (%tui-clear)
      (%tui-scr-flush scr))))

(defun tui-splash (&key (frames *tui-splash-frames*) (delay *tui-splash-delay*))
  "Minimal monochrome splash — short, centered, one accent rule."
  (unless (%tui-tty-p) (return-from tui-splash nil))
  (%tui-hide-cursor)
  (unwind-protect
       (let ((n (max 1 frames)))
         (dotimes (i n)
           (%tui-splash-frame i n)
           (sleep delay))
         ;; hold final frame a beat
         (%tui-splash-frame (1- n) n)
         (sleep 0.08d0))
    (%tui-show-cursor))
  t)

;;; ------------------------------------------------------------------
;;; App state
;;; ------------------------------------------------------------------

(defstruct (tui-app (:conc-name tui-))
  session
  mind
  (chat-log nil)
  (repl-log nil)
  (chat-scroll 0)
  (focus :chat) ; :chat | :symbols
  (input "")
  (status-lines nil)
  (running t)
  (status-tick 0)
  (last-rows 0)
  (last-cols 0)
  ;; symbols pane tree
  (sym-expanded nil)   ; alist category → T
  (sym-cursor 0)
  (sym-scroll 0)
  (sym-rows nil)       ; cached flattened rows
  ;; popups: nil | :repl | :settings
  (popup nil)
  (settings-cursor 0)
  (popup-input ""))

(defun %tui-push-chat (app role text &key (segments nil))
  (setf (tui-chat-log app)
        (append (tui-chat-log app)
                (list (list :role role
                            :text (or text "")
                            :segments segments)))))

(defun %tui-push-repl (app text)
  (setf (tui-repl-log app)
        (append (tui-repl-log app) (list (or text "")))))

(defun %tui-push-math-worked (app steps final)
  "Push color-banded math work: cyan work → yellow mid … bright green final."
  (dolist (st steps)
    (let* ((w (or (getf st :work) ""))
           (m (or (getf st :mid) ""))
           (line (format nil "~A  →  ~A" w m))
           (segs (list (cons :math-work w)
                       (cons :math-arrow "  →  ")
                       (cons :math-mid m))))
      (%tui-push-chat app :math line :segments segs)))
  (let* ((fin (or final ""))
         (line (format nil "∴ ~A" fin)))
    (%tui-push-chat app :math-final line
                    :segments (list (cons :math-final line)))))

;;; ---- symbols tree + settings model --------------------------------

(defun %tui-sym-expanded-p (app cat)
  (cdr (assoc cat (tui-sym-expanded app) :test #'equal)))

(defun %tui-sym-toggle-expand! (app cat)
  (let ((cur (tui-sym-expanded app)))
    (if (assoc cat cur :test #'equal)
        (setf (tui-sym-expanded app)
              (mapcar (lambda (p)
                        (if (equal (car p) cat)
                            (cons cat (not (cdr p)))
                            p))
                      cur))
        (push (cons cat t) (tui-sym-expanded app))))
  (tui-sym-expanded app))

(defun %tui-sym-flatten (app)
  "Flatten tree → rows (:kind :cat|:item :label :id :enabled :desc :data)."
  (let ((rows nil)
        (tree (ignore-errors (symbol-tree-model))))
    (dolist (cat (or tree nil))
      (let* ((ck (getf cat :category))
             (label (or (getf cat :label) ck))
             (open-p (if (assoc ck (tui-sym-expanded app) :test #'equal)
                         (%tui-sym-expanded-p app ck)
                         t)) ; default expanded
             (items (getf cat :items)))
        (push (list :kind :cat :label label :id ck :open open-p
                    :count (length items))
              rows)
        (when open-p
          (dolist (it items)
            (push (list :kind :item
                        :id (getf it :id)
                        :label (or (getf it :name) (getf it :id))
                        :enabled (getf it :enabled)
                        :temporary (getf it :temporary)
                        :desc (or (getf it :description) "")
                        :data it)
                  rows)))))
    (setf (tui-sym-rows app) (nreverse rows))
    (tui-sym-rows app)))

(defun %tui-settings-items ()
  "All product settings for the settings popup (color-coded ON/off)."
  (list
   (list :key :local-learning :label "Local learning (user-taught / local-user)"
         :type :bool
         :get (lambda () (and (get-config :local-learning t) t))
         :set (lambda (v) (set-config :local-learning (and v t))))
   (list :key :online-learn :label "Online neural learn"
         :type :bool
         :get (lambda () (and (boundp '*online-learn-enabled*)
                              *online-learn-enabled*))
         :set (lambda (v)
                (when (boundp '*online-learn-enabled*)
                  (setf *online-learn-enabled* (and v t)))))
   (list :key :brain-auto :label "Background brain auto-start"
         :type :bool
         :get (lambda () (and (boundp '*brain-auto-start*) *brain-auto-start*))
         :set (lambda (v)
                (when (boundp '*brain-auto-start*)
                  (setf *brain-auto-start* (and v t)))))
   (list :key :sketch :label "Allow pure-CL LM sketch freeform"
         :type :bool
         :get (lambda () (and (boundp '*iface-sketch-generate*)
                              *iface-sketch-generate*))
         :set (lambda (v)
                (when (boundp '*iface-sketch-generate*)
                  (setf *iface-sketch-generate* (and v t)))))
   (list :key :trace :label "Trace reasoning"
         :type :bool
         :get (lambda () (get-config :trace-reasoning))
         :set (lambda (v) (set-config :trace-reasoning (and v t))))
   (list :key :safe-eval :label "Safe eval (sandbox)"
         :type :bool
         :get (lambda () (get-config :safe-eval t))
         :set (lambda (v) (set-config :safe-eval (and v t))))
   (list :key :llm :label "External LLM"
         :type :bool
         :get (lambda () (get-config :llm-enabled))
         :set (lambda (v) (set-config :llm-enabled (and v t))))
   (list :key :tool-shell :label "Tool shell (dangerous)"
         :type :bool
         :get (lambda () (get-config :tool-shell-enabled))
         :set (lambda (v) (set-config :tool-shell-enabled (and v t))))
   (list :key :verbose :label "Verbose logging"
         :type :bool
         :get (lambda () (get-config :verbose))
         :set (lambda (v) (set-config :verbose (and v t))))
   (list :key :auto-forward :label "Auto-forward (agenda)"
         :type :bool
         :get (lambda () (get-config :auto-forward))
         :set (lambda (v) (set-config :auto-forward (if v :agenda nil))))
   (list :key :log-stream :label "Log to stream"
         :type :bool
         :get (lambda () (get-config :log-to-stream t))
         :set (lambda (v) (set-config :log-to-stream (and v t))))
   (list :key :api-token-req :label "API require token"
         :type :bool
         :get (lambda () (get-config :api-require-token))
         :set (lambda (v) (set-config :api-require-token (and v t))))
   (list :key :color :label "TUI color"
         :type :bool
         :get (lambda () *tui-use-color*)
         :set (lambda (v) (setf *tui-use-color* (and v t))))
   (list :key :unicode :label "TUI unicode boxes"
         :type :bool
         :get (lambda () *tui-use-unicode*)
         :set (lambda (v) (setf *tui-use-unicode* (and v t))))
   (list :key :quit-process :label "Quit kills process (product CLI)"
         :type :bool
         :get (lambda () *tui-quit-process*)
         :set (lambda (v) (setf *tui-quit-process* (and v t))))))

(defun %tui-settings-toggle! (app)
  (let* ((items (%tui-settings-items))
         (i (mod (or (tui-settings-cursor app) 0) (max 1 (length items))))
         (it (nth i items))
         (cur (ignore-errors (funcall (getf it :get)))))
    (ignore-errors (funcall (getf it :set) (not cur)))
    (getf it :key)))

(defun %tui-paint-symbols (scr app row col width height)
  "Collapsible category>symbol tree with load state colors."
  (let* ((rows (%tui-sym-flatten app))
         (n (length rows))
         (cur (max 0 (min (1- (max 1 n)) (or (tui-sym-cursor app) 0))))
         (scroll (or (tui-sym-scroll app) 0))
         (scroll (max 0 (min scroll (max 0 (- n height)))))
         (vis (if (<= n height) rows
                  (subseq rows scroll (min n (+ scroll height))))))
    (setf (tui-sym-cursor app) cur
          (tui-sym-scroll app) scroll)
    (loop for i from 0
          for r in vis
          while (< i height)
          do (let* ((sel (= (+ scroll i) cur))
                    (kind (getf r :kind))
                    (fg (cond
                          (sel :sym-sel)
                          ((eq kind :cat) :sym-cat)
                          ((getf r :enabled) :sym-on)
                          (t :sym-off)))
                    (mark (if (eq kind :cat)
                              (if (getf r :open) "v " "> ")
                              (if (getf r :enabled) "* " ". ")))
                    (lab (if (eq kind :cat)
                             (format nil "~A~A (~A)"
                                     mark (getf r :label) (getf r :count))
                             (format nil "~A~A~A"
                                     mark
                                     (getf r :label)
                                     (if (getf r :temporary) " [tmp]" ""))))
                    (line (%tui-trunc lab width)))
               (%tui-scr-put scr (+ row i) col line :fg fg)
               ;; description on selected item if room on next visual... keep one line
               (when (and sel (eq kind :item) (plusp (length (or (getf r :desc) ""))))
                 ;; overlay dim desc truncated after name when wide enough
                 (when (> width (+ 4 (length lab)))
                   (let* ((d (%tui-trunc (getf r :desc)
                                         (max 4 (- width (length lab) 1))))
                          (x (+ col (min (1- width) (length line)))))
                     (declare (ignore x))
                     (%tui-scr-put scr (+ row i)
                                   (min (+ col (length line) 1) (+ col width -4))
                                   d :fg (if sel :sym-sel :sym-desc)))))))))

(defun %tui-paint-popup (scr app)
  "Centered REPL or Settings modal."
  (let* ((rows (ts-rows scr))
         (cols (ts-cols scr))
         (kind (tui-popup app)))
    (when kind
      (let* ((ph (max 8 (floor (* rows 60) 100)))
             (pw (max 30 (floor (* cols 70) 100)))
             (pr (max 1 (floor (- rows ph) 2)))
             (pc (max 1 (floor (- cols pw) 2)))
             (title (if (eq kind :repl) " REPL  (Esc close · Enter run) "
                        " SETTINGS  (Esc close · Enter toggle) ")))
        ;; dim fill
        (dotimes (i ph)
          (%tui-scr-hline scr (+ pr i) pc pw #\Space :fg :popup-bg))
        (%tui-scr-box scr pr pc ph pw
                      (string-trim '(#\Space) title)
                      :focus t)
        (cond
          ((eq kind :repl)
           (let* ((log (tui-repl-log app))
                  (inner (- ph 3))
                  (vis (if (<= (length log) inner) log
                           (subseq log (- (length log) inner))))
                  (y 0))
             (dolist (ln vis)
               (when (< y inner)
                 (%tui-scr-put scr (+ pr 1 y) (1+ pc)
                               (%tui-trunc (or ln "") (- pw 2))
                               :fg :repl-out)
                 (incf y)))
             (%tui-scr-put scr (+ pr ph -2) (1+ pc)
                           (%tui-trunc
                            (format nil " repl> ~A#"
                                    (or (tui-popup-input app) ""))
                            (- pw 2))
                           :fg :input)))
          ((eq kind :settings)
           (let ((items (%tui-settings-items))
                 (ci (mod (or (tui-settings-cursor app) 0)
                          (max 1 (length (%tui-settings-items))))))
             (loop for i from 0
                   for it in items
                   while (< i (- ph 2))
                   do (let* ((on (ignore-errors (funcall (getf it :get))))
                             (sel (= i ci))
                             (fg (cond (sel :sym-sel)
                                       (on :settings-on)
                                       (t :settings-off)))
                             (line (format nil " ~A ~A"
                                           (if on "[ON] " "[off]")
                                           (getf it :label))))
                        (%tui-scr-put scr (+ pr 1 i) (1+ pc)
                                      (%tui-trunc line (- pw 2))
                                      :fg fg))))))))))

(defun %tui-dashboard-segments (app)
  "Status pane as list of rows; each row is list of (fg . text) segments."
  (let* ((s (tui-session app))
         (m (or (tui-mind app) (and s (sess-mind s)) *mind*))
         (br (ignore-errors (brain-status)))
         (st (and s (session-status s)))
         (atts (and s (session-list-attachments s)))
         (ms (ignore-errors
               (let ((x (mind-status m)))
                 (truncate-string (if (stringp x) x (prin1-to-string x)) 40))))
         (live (and br (getf br :running)))
         (corpus (ignore-errors (length (session-corpus s))))
         (focus (tui-focus app))
         (rows nil))
    (flet ((row (&rest segs) (push segs rows)))
      (row (cons :status-key "ver   ") (cons :dim (metis-version-string)))
      (row (cons :status-key "brain ")
           (cons (if live :status-live :status-off) (if live "LIVE" "off"))
           (cons :dim (format nil "  q=~A" (or (getf br :queue) 0))))
      (row (cons :status-key "turns ")
           (cons :status-hi (format nil "~A" (or (getf st :turns) 0)))
           (cons :status-key "  chars ")
           (cons :status-hi (format nil "~A" (or corpus 0))))
      (row (cons :status-key "focus ")
           (cons :title-focus (string-downcase (symbol-name focus)))
           (cons :dim (format nil "  ~Dx~D" (tui-last-rows app) (tui-last-cols app))))
      ;; LLM truth: on with model, or off with how to fix (not a silent lie)
      (let* ((st (ignore-errors (llm-status)))
             (on (getf st :enabled))
             (sum (or (getf st :summary) "off")))
        (row (cons :status-key "llm   ")
             (cons (if on :status-live :status-off) sum)))
      (row (cons :status-key "files ")
           (if (null atts)
               (cons :dim "—")
               (cons :status-val
                     (format nil "~{~A~^, ~}"
                             (mapcar (lambda (a)
                                       (or (getf a :name) (getf a :id) "?"))
                                     (subseq atts 0 (min 4 (length atts))))))))
      ;; loaded capability symbols (the product surface)
      (let* ((ids (or (ignore-errors (symbol-loaded-summary)) nil))
             (learn (and (ignore-errors (symbol-local-learning-p)) t))
             (caps (list (if (ignore-errors (symbol-capability-enabled-p :math)) "math" nil)
                         (if (ignore-errors (symbol-capability-enabled-p :nl)) "nl" nil)
                         (if (ignore-errors (symbol-capability-enabled-p :local-user)) "local" nil)))
             (caps (remove nil caps)))
        (row (cons :status-key "syms  ")
             (cons :sym-on
                   (if ids
                       (%tui-trunc (format nil "~{~A~^ ~}"
                                           (subseq ids 0 (min 4 (length ids))))
                                   28)
                       "—")))
        (row (cons :status-key "caps  ")
             (cons :status-hi (if caps (format nil "~{~A~^ · ~}" caps) "none"))
             (cons :dim (if learn "  learn:on" "  learn:off"))))
      (nreverse rows))))

(defun %tui-chat-items (app width)
  "List of chat rows. Math rows keep :segments for multi-color paint."
  (let ((out nil)
        (width (max 4 width)))
    (dolist (msg (tui-chat-log app))
      (let* ((role (or (getf msg :role) :sys))
             (body (or (getf msg :text) ""))
             (segs (getf msg :segments)))
        (if (and segs (member role '(:math :math-final :math-work :math-mid)))
            ;; keep one visual row per step (truncate segments to width)
            (push (list :role role :text body :segments segs) out)
            (dolist (w (%tui-wrap body width))
              (push (list :role role :text w) out)))))
    (nreverse out)))

;;; ------------------------------------------------------------------
;;; Dynamic layout + paint
;;; ------------------------------------------------------------------

(defparameter *tui-input-max-lines* 5
  "Max visible lines in the multi-line input composer (tail if longer).")

(defun %tui-input-line-count (text)
  (let ((t0 (or text "")))
    (if (zerop (length t0))
        1
        (1+ (count #\Newline t0)))))

(defun %tui-display-tabs (s)
  "Show Tab as a visible mark so typing is obvious; buffer still holds real Tab."
  (substitute #\→ #\Tab (or s "") :test #'char=))

(defun %tui-input-visible-lines (text max-lines width)
  "Last MAX-LINES of TEXT as display rows (logical newlines only — no rewrap chaos).
   Each logical line is truncated to WIDTH. Trailing newline ⇒ empty last line.
   Tabs shown as → for visibility (buffer keeps real Tab)."
  (let* ((width (max 8 width))
         (raw (or text ""))
         (parts (cl-ppcre:split "\\n" raw))
         (lines (mapcar (lambda (p)
                          (%tui-trunc (%tui-display-tabs p) width))
                        parts)))
    (when (and (plusp (length raw))
               (char= (char raw (1- (length raw))) #\Newline))
      (setf lines (append lines (list ""))))
    (when (null lines) (setf lines (list "")))
    (let ((n (length lines)))
      (if (<= n max-lines)
          lines
          (subseq lines (- n max-lines))))))

(defun %tui-layout (rows cols &key (input-lines 1))
  "chat | status+symbols (repl is a popup, not a permanent pane)."
  (let* ((rows (max *tui-min-rows* (%tui-parse-dim rows 24)))
         (cols (max *tui-min-cols* (%tui-parse-dim cols 80)))
         (vis (max 1 (min *tui-input-max-lines* (max 1 input-lines))))
         (input-h (+ 2 vis))
         (body-h (max 6 (- rows input-h)))
         (left-w (min (- cols 16) (max 18 (floor (* cols 55) 100))))
         (right-w (max 16 (- cols left-w)))
         (status-h (max 4 (floor (* body-h 28) 100)))
         (sym-h (max 8 (- body-h status-h))))
    (when (/= (+ status-h sym-h) body-h)
      (setf sym-h (max 8 (- body-h status-h))))
    (list :rows rows :cols cols
          :left-w left-w :right-w right-w
          :body-h body-h :input-h input-h
          :input-vis vis
          :status-h status-h :sym-h sym-h
          :input-y body-h)))

(defun %tui-paint-status (scr app row col width height)
  "Colorized status segments into SCR."
  (let* ((segs-rows (%tui-dashboard-segments app))
         (maxr (min height (length segs-rows))))
    (dotimes (i maxr)
      (let ((x col)
            (limit (+ col width)))
        (dolist (seg (nth i segs-rows))
          (let* ((fg (car seg))
                 (tx (cdr seg))
                 (room (max 0 (- limit x)))
                 (piece (%tui-trunc tx room)))
            (when (plusp (length piece))
              (%tui-scr-put scr (+ row i) x piece :fg fg)
              (incf x (length piece)))))))))

(defun %tui-paint-chat-segments (scr row col width segments)
  "Paint one row of (fg . text) segments, left-aligned, clipped to WIDTH."
  (let ((x col)
        (limit (+ col width)))
    (dolist (seg segments)
      (when (>= x limit) (return))
      (let* ((fg (car seg))
             (tx (cdr seg))
             (room (max 0 (- limit x)))
             (piece (%tui-trunc tx room)))
        (when (plusp (length piece))
          (%tui-scr-put scr row x piece :fg fg)
          (incf x (length piece)))))))

(defun %tui-paint-chat (scr app row col width height)
  "User = yellow RIGHT; Metis = green LEFT; math steps = cyan/yellow/green."
  (let* ((items (%tui-chat-items app width))
         (scroll (max 0 (tui-chat-scroll app)))
         (n (length items))
         (vis (if (<= n height)
                  items
                  (let* ((end (max height (- n scroll)))
                         (start (max 0 (- end height))))
                    (subseq items start (min n end))))))
    (loop for i from 0
          for item in vis
          while (< i height)
          do (let* ((role (getf item :role))
                    (segs (getf item :segments))
                    (text (%tui-trunc (getf item :text) width))
                    (y (+ row i)))
               (cond
                 ((and segs (plusp (length segs)))
                  (%tui-paint-chat-segments scr y col width segs))
                 (t
                  (let ((fg (case role
                              (:user :user)
                              (:metis :metis)
                              (:math-final :math-final)
                              (:math-work :math-work)
                              (:math-mid :math-mid)
                              (:math :math-work)
                              (t :sys)))
                        (x (if (eq role :user)
                               (+ col (max 0 (- width (length text))))
                               col)))
                    (%tui-scr-put scr y x text :fg fg))))))))

(defun %tui-paint-repl (scr app row col width height)
  (let* ((raw (tui-repl-log app))
         (lines nil))
    (dolist (ln raw)
      (let ((fg (cond
                  ((and (stringp ln) (>= (length ln) 3)
                        (string= (subseq ln 0 3) "=> "))
                   :repl-out)
                  ((and (stringp ln) (>= (length ln) 2)
                        (string= (subseq ln 0 2) "> "))
                   :repl-in)
                  ((and (stringp ln) (>= (length ln) 3)
                        (string= (subseq ln 0 3) ";; "))
                   :repl-meta)
                  ((and (stringp ln) (search "error" ln :test #'char-equal))
                   :repl-err)
                  ;; worked math in REPL
                  ((and (stringp ln) (plusp (length ln)) (char= (char ln 0) #\∴))
                   :math-final)
                  ((and (stringp ln) (search "→" ln))
                   :math-work)
                  (t :default))))
        (dolist (w (%tui-wrap ln width))
          (push (cons fg w) lines))))
    (setf lines (nreverse lines))
    (let* ((n (length lines))
           (vis (if (<= n height) lines (subseq lines (- n height)))))
      (loop for i from 0
            for pair in vis
            while (< i height)
            do (%tui-scr-put scr (+ row i) col
                             (%tui-trunc (cdr pair) width)
                             :fg (car pair))))))

(defun %tui-paint (app)
  "Full color redraw. Enter=send; Shift+Enter/Ctrl+N=newline; input grows ≤5 lines.
   Hardware cursor only — parked at end of last input line (stable)."
  (multiple-value-bind (rows cols) (%tui-term-size)
    (setf (tui-last-rows app) rows
          (tui-last-cols app) cols
          *tui-resized-p* nil)
    ;; choke-point: buffer can never hold Tab/controls
    (%tui-set-input! app (tui-input app))
    (let* ((raw (or (tui-input app) ""))
           (nlines (%tui-input-line-count raw))
           (L (%tui-layout rows cols :input-lines nlines))
           (rows (getf L :rows))
           (cols (getf L :cols))
           (left-w (getf L :left-w))
           (right-w (getf L :right-w))
           (body-h (getf L :body-h))
           (status-h (getf L :status-h))
           (sym-h (or (getf L :sym-h) (getf L :repl-h) 8))
           (input-y (getf L :input-y))
           (input-vis (getf L :input-vis))
           (scr (%tui-make-screen rows cols))
           (focus (tui-focus app))
           (chat-active (eq focus :chat))
           (sym-active (eq focus :symbols))
           (cursor-col 1)
           (cursor-row 1)
           (mode-tag (cond ((tui-popup app)
                            (string-downcase (symbol-name (tui-popup app))))
                           (sym-active "sym")
                           (t "chat")))
           (mode-fg (cond (sym-active :sym-cat)
                          (chat-active :input-label-chat)
                          (t :input-label-repl)))
           (help "C-t symbols  C-r REPL  C-s settings  Enter  d=dl  /quit")
           (g (%tui-g))
           (hch (char (getf g :h) 0))
           (bfg :border-focus)
           (prefix (format nil " ~A> " mode-tag))
           (gutter (length prefix))
           (text-w (max 4 (- cols gutter 1))))
      ;; panes: chat | status + symbols tree (repl is popup)
      (%tui-scr-box scr 0 0 body-h left-w "chat" :focus chat-active)
      (%tui-scr-box scr 0 left-w status-h right-w "status" :focus nil)
      (%tui-scr-box scr status-h left-w sym-h right-w "symbols" :focus sym-active)
      (%tui-paint-chat scr app 1 1 (max 4 (- left-w 2)) (max 1 (- body-h 2)))
      (%tui-paint-status scr app 1 (1+ left-w)
                         (max 4 (- right-w 2)) (max 1 (- status-h 2)))
      (%tui-paint-symbols scr app (1+ status-h) (1+ left-w)
                          (max 4 (- right-w 2)) (max 1 (- sym-h 2)))
      (%tui-paint-popup scr app)
      ;; input composer — solid high-contrast bar so every keystroke shows
      (let* ((vis-lines (%tui-input-visible-lines raw input-vis text-w))
             (truncated (> (%tui-input-line-count raw) input-vis))
             (bot (+ input-y 1 input-vis)))
        (%tui-scr-hline scr input-y 0 cols hch :fg bfg)
        (loop for i from 0
              for line in vis-lines
              for y = (+ input-y 1 i)
              while (and (< i input-vis) (< y rows))
              do (let* ((is-first (zerop i))
                        (is-last (= i (1- (length vis-lines))))
                        (gstr (if is-first
                                  prefix
                                  (format nil " ~A| "
                                          (make-string (length mode-tag)
                                                       :initial-element #\Space))))
                        (gstr (if (<= (length gstr) cols) gstr
                                  (subseq gstr 0 cols)))
                        (x0 (length gstr))
                        (avail (max 1 (- cols x0)))
                        (show (%tui-trunc line avail)))
                   ;; full-width white bar so typed text cannot vanish into bg
                   (%tui-scr-hline scr y 0 cols #\Space :fg :input-bg)
                   (%tui-scr-put scr y 0 gstr :fg mode-fg)
                   (when (and is-first truncated)
                     (%tui-scr-put scr y x0 "..." :fg :input)
                     (setf show (%tui-trunc line (max 1 (- avail 3))))
                     (%tui-scr-put scr y (+ x0 3) show :fg :input)
                     (when is-last
                       (let ((cx (min (1- cols) (+ x0 3 (length show)))))
                         (setf cursor-row y cursor-col cx)
                         (%tui-scr-put scr y cx "#" :fg :cursor))))
                   (unless (and is-first truncated)
                     (%tui-scr-put scr y x0 show :fg :input)
                     (when is-last
                       (let ((cx (min (1- cols) (+ x0 (length show)))))
                         (setf cursor-row y cursor-col cx)
                         ;; ASCII cursor marker on high-contrast bar
                         (%tui-scr-put scr y cx "#" :fg :cursor))))))
        (when (< bot rows)
          (%tui-scr-hline scr bot 0 cols hch :fg bfg))
        (when (> cols (+ 4 (length help)))
          (%tui-scr-put scr input-y (max 0 (- cols (length help) 1))
                        help :fg :help)))
      (%tui-clear)
      (%tui-scr-flush scr)
      ;; re-assert raw mode flags each frame (some terminals re-enable CSI keys)
      (ignore-errors
        (write-string (%tui-esc ">4;0m") (%tui-io-out))  ; modifyOtherKeys off
        (write-string (%tui-esc "?2004l") (%tui-io-out)))
      ;; Soft # marker is drawn on the bar; also park hardware cursor there so
      ;; the terminal's own caret is on the input (helps visibility).
      (%tui-goto (1+ cursor-row) (1+ cursor-col))
      (%tui-show-cursor)
      (force-output (%tui-io-out))
      (values rows cols))))

;;; ------------------------------------------------------------------
;;; Actions
;;; ------------------------------------------------------------------

(defun %tui-refresh-status (app)
  (declare (ignore app))
  ;; status is rebuilt live in paint from mind/brain state
  nil)

(defun %tui-normalize-cmd (text)
  "Trim whitespace/CR and collapse odd slashes for command match."
  (let* ((t0 (string-trim '(#\Space #\Tab #\Newline #\Return #\Page #\Nul)
                          (or text "")))
         ;; strip a single leading fullwidth solidus etc.
         (t0 (cl-ppcre:regex-replace "^[／/]+" t0 "/")))
    t0))

(defun %tui-quit-command-p (text)
  "T for quit/exit in any common spelling."
  (let ((t0 (%tui-normalize-cmd text)))
    (or (member t0 '("quit" "exit" "/quit" "/exit" "/q" ":q" ":quit" ":exit"
                     "(quit)" "(exit)" "q")
                :test #'string-equal)
        (and (plusp (length t0))
             (cl-ppcre:scan "(?i)^/*\\s*(quit|exit)\\s*$" t0)))))

(defun %tui-result-quit-p (resp)
  (let ((r (and (consp resp) (getf resp :result))))
    (or (and (consp r) (getf r :quit))
        (and (consp resp) (getf resp :quit)))))

(defparameter *tui-mind-ops*
  '("QUIT" "EXIT" "STATUS" "HELP" "TELL" "ASSERT" "RETRACT" "RULE" "<-"
    "ASK" "ASK-ALL" "PROVE" "FORWARD" "GOAL" "PURSUE" "PLAN" "HTN" "WHY"
    "VERSION" "PRODUCTION-BOOT" "SOCIETY" "API" "DAEMON" "DO" "EXECUTE"
    "TOOL" "REFLECT" "EXPLAIN" "SELF" "SELF-MODEL" "REMEMBER" "RECALL"
    "SKILLS" "SYNTHESIZE-SKILL" "REWRITE-RULE" "CYCLE" "RUN-ONCE" "LLM"
    "EVAL" "SAVE" "LOAD" "FRAME" "DEFRAME" "FRAME-GET" "FRAME-SET"
    "WORKING" "TRACE")
  "Mind-language operators; everything else in the REPL is sandboxed CL.")

(defun %tui-mind-form-p (form)
  (and (consp form)
       (symbolp (car form))
       (member (symbol-name (car form)) *tui-mind-ops* :test #'string=)))

(defun %tui-format-result (result)
  (cond
    ((stringp result) result)
    ((eq result :quit) "quit")
    (t (let ((*print-pretty* t)
             (*print-circle* t)
             (*print-length* 40)
             (*print-level* 6))
         (prin1-to-string result)))))

(defun %tui-repl-eval (mind text)
  "REPL scratch: bare math 2+4(56/3) · mind forms · sandboxed CL."
  (let* ((text (string-trim '(#\Space #\Tab #\Newline) text))
         (*package* (find-package :metis))
         (*read-eval* nil))
    ;; 1) infix math / algebra with worked steps
    (multiple-value-bind (val final expr steps) (eval-math-expression text)
      (declare (ignore val expr))
      (when final
        (return-from %tui-repl-eval
          (if (and steps (plusp (length steps)))
              (%math-format-worked-text steps final)
              final))))
    (let ((form
           (cond
             ((member text '("status" "help" "self" "version" "cycle")
                      :test #'string-equal)
              (list (intern (string-upcase text) :metis)))
             (t (read-from-string text)))))
      (cond
        ((%tui-mind-form-p form)
         (interpret mind form))
        ((and (consp form) (symbolp (car form))
              (string= (symbol-name (car form)) "EVAL"))
         (interpret mind form))
        (t
         (let ((*mind* mind))
           (sandboxed-eval form)))))))

(defun %tui-focus-toggle! (app)
  "Chat ↔ symbols pane (REPL is a popup, not a focus)."
  (when (tui-popup app)
    (setf (tui-popup app) nil))
  (setf (tui-focus app)
        (if (eq (tui-focus app) :chat) :symbols :chat))
  (tui-focus app))

(defun %tui-popup-open! (app kind)
  (setf (tui-popup app) kind
        (tui-popup-input app) ""
        (tui-settings-cursor app) 0)
  kind)

(defun %tui-popup-close! (app)
  (setf (tui-popup app) nil
        (tui-popup-input app) "")
  nil)

(defun %tui-symbols-activate! (app &key (download nil))
  "Enter/space on symbols cursor: expand category or toggle load.
   DOWNLOAD T → catalog install/enable (seed → registry)."
  (let* ((rows (or (tui-sym-rows app) (%tui-sym-flatten app)))
         (i (max 0 (min (1- (max 1 (length rows))) (or (tui-sym-cursor app) 0))))
         (r (nth i rows)))
    (when r
      (cond
        ((eq (getf r :kind) :cat)
         (%tui-sym-toggle-expand! app (getf r :id))
         (%tui-sym-flatten app)
         :expand)
        ((eq (getf r :kind) :item)
         (let ((id (getf r :id)))
           (handler-case
               (let ((res
                      (if download
                          (symbol-catalog-download! id :mind (tui-mind app) :enable t)
                          (symbol-toggle! id :mind (tui-mind app)))))
                 (%tui-push-chat app :sys
                                 (format nil "symbol ~A → ~A"
                                         id (or (getf res :action)
                                                (if download :downloaded
                                                    (getf res :enabled)))))
                 (%tui-sym-flatten app)
                 res)
             (error (e)
               (%tui-push-chat app :sys (format nil "symbol error: ~A" e))
               nil))))))))

(defun %tui-backspace! (app)
  "Delete one character (including a real Tab). Sanitizes CSI junk first."
  (let ((in (%tui-sanitize-input (or (tui-input app) ""))))
    (cond
      ((zerop (length in))
       (%tui-set-input! app "")
       nil)
      (t
       (%tui-set-input! app (subseq in 0 (1- (length in))))
       t))))

(defun %tui-do-quit! (app &optional (msg "Goodbye."))
  "Stop the TUI loop and kill the process (product CLI). Always."
  (ignore-errors (%tui-push-chat app :sys msg))
  (setf (tui-running app) nil)
  ;; paint once so user can see goodbye if exit is slow; then hard exit
  (ignore-errors (%tui-paint app))
  (%tui-restore-terminal!)
  (%tui-exit-process! 0)
  :quit)

(defun %tui-submit (app)
  (let* ((raw (or (tui-input app) ""))
         ;; sanitize BEFORE normalize so CSI debris never reaches freeform
         (text (%tui-sanitize-input raw))
         (text (%tui-normalize-cmd text))
         (focus (tui-focus app)))
    (setf (tui-input app) "")
    (%tui-drain-pending! 0.05d0) ; kill leftover CSI after send
    (when (zerop (length text)) (return-from %tui-submit nil))
    (when (zerop (length text)) (return-from %tui-submit nil))
    ;; quit first, always — never send to freeform/math
    (when (%tui-quit-command-p text)
      (return-from %tui-submit (%tui-do-quit! app)))
    ;; slash UI commands (REPL/settings are popups; symbols is a pane)
    (when (member text '("/repl" "/chat" "/focus" "/pane" "/symbols" "/settings"
                         "/sym")
                  :test #'string-equal)
      (cond
        ((string-equal text "/repl")
         (%tui-popup-open! app :repl)
         (%tui-push-chat app :sys "→ REPL popup (Esc closes · Ctrl+R)"))
        ((string-equal text "/settings")
         (%tui-popup-open! app :settings)
         (%tui-push-chat app :sys "→ settings (Esc closes · Ctrl+S)"))
        ((or (string-equal text "/symbols") (string-equal text "/sym"))
         (setf (tui-focus app) :symbols)
         (%tui-push-chat app :sys "→ symbols pane (Enter=toggle · d=download · Ctrl+T)"))
        ((string-equal text "/chat")
         (setf (tui-focus app) :chat)
         (%tui-push-chat app :sys "→ chat"))
        (t
         (%tui-focus-toggle! app)
         (%tui-push-chat app :sys
                         (format nil "→ ~A  (Ctrl+T · /symbols · /chat)"
                                 (if (eq (tui-focus app) :symbols)
                                     "symbols" "chat")))))
      (return-from %tui-submit :focus))
    (cond
      ((eq focus :symbols)
       (%tui-symbols-activate! app)
       (%tui-refresh-status app))
      (t
       (%tui-push-chat app :user text)
       (handler-case
           (let* ((resp (iface-turn (tui-session app) text))
                  (reply (or (getf resp :reply) ""))
                  (result (getf resp :result))
                  (steps (or (getf resp :steps)
                             (and (consp result) (getf result :steps))))
                  (final (or (and (consp result) (getf result :final))
                             nil)))
             (if (and steps (plusp (length steps)))
                 (%tui-push-math-worked app steps (or final reply))
                 (%tui-push-chat app :metis reply))
             (when (%tui-result-quit-p resp)
               (return-from %tui-submit (%tui-do-quit! app reply)))
             (%tui-refresh-status app))
         (error (e)
           (%tui-push-chat app :sys (format nil "error: ~A" e))))))
    (setf (tui-chat-scroll app) 0)
    t))

;;; ------------------------------------------------------------------
;;; Main
;;; ------------------------------------------------------------------

(defun %tui-restore-terminal! ()
  "Leave the tty sane — always, even on error paths."
  (ignore-errors (%tui-show-cursor))
  (ignore-errors
    (write-string (%tui-esc "0m") (%tui-io-out))
    (%tui-clear)
    (force-output (%tui-io-out)))
  (ignore-errors (%tui-raw-off))
  (ignore-errors (brain-stop!))
  t)

(defun %tui-exit-process! (&optional (code 0))
  "Product exit: restore tty and kill the process → shell prompt. No debugger."
  (%tui-restore-terminal!)
  (ignore-errors (finish-output))
  (ignore-errors (finish-output *error-output*))
  (if *tui-quit-process*
      (uiop:quit code)
      code))

(defun tui-run (&key (session nil) (splash t) (mind nil) (quit-process nil))
  "Product TUI. /quit · Esc · C-c → clean process exit (shell prompt), not SBCL.
   QUIT-PROCESS overrides *tui-quit-process* when non-NIL (T or :no)."
  (let ((*tui-quit-process*
         (cond ((eq quit-process :no) nil)
               ((eq quit-process t) t)
               (t *tui-quit-process*))))
    (handler-bind
        ((serious-condition
          (lambda (c)
            ;; never dump the user into LDB from product TUI
            (%tui-restore-terminal!)
            (format *error-output* "~&metis: ~A~%" c)
            (force-output *error-output*)
            (when *tui-quit-process*
              (uiop:quit 1)))))
      (let* ((m (or mind *mind* (boot)))
             (s (or session
                    (and *session* (eq (sess-mind *session*) m) *session*)
                    (session-create :mind m :boot nil)))
             (app (make-tui-app :session s :mind m))
             (*session* s)
             (old-log *log-stream*)
             (exit-code 0))
        (setf *log-stream* (make-broadcast-stream))
        (ignore-errors (nn-enable-path m))
        (when *brain-auto-start* (brain-start!))
        (%tui-push-chat app :sys
                        (format nil "Metis · ~A · Ctrl+T=symbols · Ctrl+R=REPL · Ctrl+S=settings · Enter=send · /quit  [r~A]"
                                (sess-id s) *tui-key-rev*))
        (%tui-push-chat app :sys
                        "Symbols are on-demand knowledge (math, NL, local-user, domains) — not a kitchen-sink model.")
        (%tui-push-repl app ";; REPL popup — Esc closes · Enter runs · try 2+4(56/3) or (status)")
        (setf (tui-sym-expanded app)
              (list (cons "language" t) (cons "reasoning" t)
                    (cons "local" t) (cons "reference" t)))
        (ignore-errors (%tui-sym-flatten app))
        ;; Open /dev/tty (UTF-8) + raw mode BEFORE first full paint.
        ;; Splash may run on stdio; UI always prefers the tty streams.
        (%tui-raw-on)
        (when splash (ignore-errors (tui-splash)))
        (%tui-hide-cursor)
        (setf *tui-cached-rows* nil *tui-cached-cols* nil *tui-resized-p* t)
        (unwind-protect
             (progn
               ;; First paint: if this dies, user saw splash → prompt. Guard it.
               (handler-case (%tui-paint app)
                 (error (e)
                   (format *error-output* "~&metis tui paint failed: ~A~%" e)
                   (force-output *error-output*)
                   (error e)))
               (loop while (tui-running app) do
                 (let ((k (%tui-read-key-timeout 0.12d0))
                       (need-paint nil))
                   (incf (tui-status-tick app))
                   ;; ALWAYS scrub controls from input every tick
                   (%tui-set-input! app (tui-input app))
                   (cond
                     ((or (null k) (eq k :eof))
                      (when (eq k :eof)
                        (setf (tui-running app) nil)))
                     ((member k '(:timeout :resize))
                      (%tui-term-size)
                      (when (or *tui-resized-p*
                                (not (eql (tui-last-rows app) *tui-cached-rows*))
                                (not (eql (tui-last-cols app) *tui-cached-cols*)))
                        (setf need-paint t)))
                     ((eq k :quit)
                      (%tui-do-quit! app))
                     ((eq k :escape)
                      (if (tui-popup app)
                          (progn (%tui-popup-close! app) (setf need-paint t))
                          (setf need-paint t)))
                     ((eq k :ignore)
                      (setf need-paint t))
                     ((eq k :popup-repl)
                      (%tui-popup-open! app :repl)
                      (setf need-paint t))
                     ((eq k :popup-settings)
                      (%tui-popup-open! app :settings)
                      (setf need-paint t))
                     ((eq k :focus-toggle)
                      (let ((f (%tui-focus-toggle! app)))
                        (%tui-push-chat app :sys
                                        (format nil "→ ~A  (Ctrl+T · Ctrl+R REPL · Ctrl+S settings)"
                                                (if (eq f :symbols) "symbols" "chat")))
                        (setf need-paint t)))
                     ((eq k :enter)
                      (cond
                        ((eq (tui-popup app) :settings)
                         (%tui-settings-toggle! app)
                         (setf need-paint t))
                        ((eq (tui-popup app) :repl)
                         (let* ((tx (or (tui-popup-input app) ""))
                                (m (tui-mind app)))
                           (when (plusp (length tx))
                             (%tui-push-repl app (format nil "> ~A" tx))
                             (handler-case
                                 (let ((r (%tui-repl-eval m tx)))
                                   (%tui-push-repl app
                                                   (format nil "=> ~A"
                                                           (%tui-format-result r))))
                               (error (e)
                                 (%tui-push-repl app (format nil ";; error: ~A" e))))
                             (setf (tui-popup-input app) ""))
                           (setf need-paint t)))
                        ((eq (tui-focus app) :symbols)
                         (%tui-symbols-activate! app)
                         (setf need-paint t))
                        (t
                         (%tui-set-input! app (tui-input app))
                         (let ((r (%tui-submit app)))
                           (unless (eq r :quit)
                             (setf need-paint t))))))
                     ((eq k :newline)
                      (if (eq (tui-popup app) :repl)
                          (setf (tui-popup-input app)
                                (concatenate 'string
                                             (or (tui-popup-input app) "")
                                             (string #\Newline)))
                          (%tui-input-append app (string #\Newline)))
                      (setf need-paint t))
                     ((eq k :backspace)
                      (cond
                        ((eq (tui-popup app) :repl)
                         (let ((in (or (tui-popup-input app) "")))
                           (when (plusp (length in))
                             (setf (tui-popup-input app)
                                   (subseq in 0 (1- (length in))))))
                         (setf need-paint t))
                        (t
                         (%tui-backspace! app)
                         (setf need-paint t))))
                     ((eq k :clear-input)
                      (if (eq (tui-popup app) :repl)
                          (setf (tui-popup-input app) "")
                          (%tui-set-input! app ""))
                      (setf need-paint t))
                     ((eq k :page-up)
                      (if (eq (tui-focus app) :symbols)
                          (setf (tui-sym-cursor app)
                                (max 0 (- (or (tui-sym-cursor app) 0) 5)))
                          (incf (tui-chat-scroll app) 5))
                      (setf need-paint t))
                     ((eq k :page-down)
                      (if (eq (tui-focus app) :symbols)
                          (incf (tui-sym-cursor app) 5)
                          (setf (tui-chat-scroll app)
                                (max 0 (- (tui-chat-scroll app) 5))))
                      (setf need-paint t))
                     ((eq k :up)
                      (cond
                        ((eq (tui-popup app) :settings)
                         (decf (tui-settings-cursor app))
                         (setf need-paint t))
                        ((eq (tui-focus app) :symbols)
                         (setf (tui-sym-cursor app)
                               (max 0 (1- (or (tui-sym-cursor app) 0))))
                         (setf need-paint t))
                        (t
                         (incf (tui-chat-scroll app))
                         (setf need-paint t))))
                     ((eq k :down)
                      (cond
                        ((eq (tui-popup app) :settings)
                         (incf (tui-settings-cursor app))
                         (setf need-paint t))
                        ((eq (tui-focus app) :symbols)
                         (incf (tui-sym-cursor app))
                         (setf need-paint t))
                        (t
                         (setf (tui-chat-scroll app)
                               (max 0 (1- (tui-chat-scroll app))))
                         (setf need-paint t))))
                     ((and (consp k) (eq (first k) :paste))
                      (if (eq (tui-popup app) :repl)
                          (setf (tui-popup-input app)
                                (concatenate 'string
                                             (or (tui-popup-input app) "")
                                             (or (second k) "")))
                          (%tui-input-append app (or (second k) "")))
                      (setf need-paint t))
                     ((and (consp k) (eq (first k) :paste-send))
                      (%tui-input-append app (or (second k) ""))
                      (let ((r (%tui-submit app)))
                        (unless (eq r :quit) (setf need-paint t))))
                     ((and (consp k) (eq (first k) :insert))
                      (if (eq (tui-popup app) :repl)
                          (setf (tui-popup-input app)
                                (concatenate 'string
                                             (or (tui-popup-input app) "")
                                             (or (second k) "")))
                          (%tui-input-append app (or (second k) "")))
                      (setf need-paint t))
                     ;; symbols pane: d = catalog download/install, space = toggle
                     ((and (characterp k)
                           (not (tui-popup app))
                           (eq (tui-focus app) :symbols)
                           (or (char= k #\d) (char= k #\D)))
                      (%tui-symbols-activate! app :download t)
                      (setf need-paint t))
                     ((and (characterp k)
                           (not (tui-popup app))
                           (eq (tui-focus app) :symbols)
                           (char= k #\Space))
                      (%tui-symbols-activate! app)
                      (setf need-paint t))
                     ((characterp k)
                      (if (eq (tui-popup app) :repl)
                          (setf (tui-popup-input app)
                                (concatenate 'string
                                             (or (tui-popup-input app) "")
                                             (string k)))
                          (%tui-input-append app (string k)))
                      (setf need-paint t))
                     (t (setf need-paint t)))
                   (when need-paint
                     (%tui-paint app)))))
          (setf *log-stream* old-log)
          (%tui-restore-terminal!))
        ;; if loop ends without hard quit, still exit process
        (%tui-exit-process! exit-code)
        :tui-done))))

(defun run-tui (&rest args)
  (apply #'tui-run args))
