;;;; install.lisp — real install.sh + packaging structural tests
(in-package :metis/tests)

(def-suite :metis-install
  :description "Shell installer and packaging recipes (real paths)")
(in-suite :metis-install)

(defun %metis-root ()
  (asdf:system-source-directory :metis))

(defun %install-sh ()
  (merge-pathnames "scripts/install.sh" (%metis-root)))

(defun %tree-version ()
  (string-trim '(#\Space #\Tab #\Newline #\Return)
               (uiop:read-file-string
                (merge-pathnames "VERSION" (%metis-root)))))

(defun %run-shell (command &key (directory nil))
  "Run COMMAND via bash -lc; inherit PATH. Returns (values out err code)."
  (uiop:run-program
   (list "bash" "-lc" command)
   :directory directory
   :output :string
   :error-output :string
   :ignore-error-status t))

(test install-sh-exists-and-executable
  "Shipped installer is present and executable bit set."
  (let ((p (%install-sh)))
    (is-true (probe-file p))
    (multiple-value-bind (out err code)
        (%run-shell (format nil "stat -c '%a' ~S" (namestring p)))
      (declare (ignore err))
      (is (zerop code))
      (let ((mode-num (parse-integer (string-trim '(#\Space #\Newline) out)
                                     :junk-allowed t)))
        (is (and mode-num (plusp (logand mode-num #o111)))
            (format nil "install.sh mode ~S should be executable" out))))))

(test install-sh-local-prefix-and-version
  "Drive real scripts/install.sh into a temp prefix; launcher reports VERSION."
  (let* ((root (namestring (%metis-root)))
         (prefix (namestring
                  (ensure-directories-exist
                   (merge-pathnames
                    (format nil "metis-install-test-~A/"
                            (get-universal-time))
                    (uiop:temporary-directory)))))
         (script (namestring (%install-sh)))
         (launcher (merge-pathnames "bin/metis" prefix))
         (share (merge-pathnames "share/metis/" prefix))
         (man (merge-pathnames "share/man/man1/metis.1" prefix))
         (expected (%tree-version))
         (cmd (format nil
                      "PREFIX=~S METIS_LOCAL=1 METIS_SKIP_QL_LINK=1 bash ~S"
                      prefix script)))
    (unwind-protect
         (multiple-value-bind (out err code)
             (%run-shell cmd :directory root)
           (is (zerop code)
               (format nil "install.sh exit ~A~%stdout:~%~A~%stderr:~%~A"
                       code out err))
           (is-true (probe-file launcher) "bin/metis launcher missing after install")
           (is-true (probe-file (merge-pathnames "metis.asd" share)))
           (is-true (probe-file (merge-pathnames "VERSION" share)))
           (is-true (probe-file man) "man page should install")
           (multiple-value-bind (vout verr vcode)
               (%run-shell (format nil "~S version" (namestring launcher)))
             (is (zerop vcode)
                 (format nil "metis version failed (~A): ~A~%~A" vcode vout verr))
             (is (search expected vout)
                 (format nil "version output ~S should contain ~S" vout expected))))
      (ignore-errors
        (uiop:delete-directory-tree
         (uiop:ensure-directory-pathname prefix)
         :validate t :if-does-not-exist :ignore)))))

(test packaging-homebrew-formula-present
  "Homebrew formula ships in-tree and pins tree VERSION."
  (let* ((p (merge-pathnames "packaging/homebrew/metis.rb" (%metis-root)))
         (txt (uiop:read-file-string p))
         (ver (%tree-version)))
    (is-true (probe-file p))
    (is (search "class Metis" txt))
    (is (search "metis.f00.sh" txt))
    (is (search ver txt)
        "formula should pin the same VERSION as the tree")
    (is (search "depends_on \"sbcl\"" txt))))

(test packaging-aur-pkgbuild-present
  "AUR PKGBUILD ships and packages /usr/bin/metis launcher."
  (let* ((p (merge-pathnames "packaging/aur/PKGBUILD" (%metis-root)))
         (txt (uiop:read-file-string p))
         (ver (%tree-version)))
    (is-true (probe-file p))
    (is (search "pkgname=metis" txt))
    (is (search (format nil "pkgver=~A" ver) txt))
    (is (search "/usr/bin/metis" txt))
    (is (search "depends=('sbcl')" txt))))

(test site-install-sh-mirrors-scripts
  "site/install.sh is the curl edge entry and matches scripts/install.sh."
  (let ((a (merge-pathnames "scripts/install.sh" (%metis-root)))
        (b (merge-pathnames "site/install.sh" (%metis-root))))
    (is-true (probe-file b))
    (is (equal (uiop:read-file-string a)
               (uiop:read-file-string b))
        "site/install.sh must stay identical to scripts/install.sh")))
