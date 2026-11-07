(require :asdf)
;; Keep generated files inside the project, including under an agent sandbox.
(asdf:initialize-output-translations
 (list :output-translations
       (list t (list (merge-pathnames ".ardd-cache/" (uiop:getcwd)) :implementation))
       :ignore-inherited-configuration))
(asdf:load-asd (truename "mathbook.asd"))
(ql:quickload "mathbook/dev")
(let ((directory (uiop:ensure-directory-pathname (uiop:getenv "SLY_DIR"))))
  (asdf:load-asd (merge-pathnames "slynk/slynk.asd" directory)))
(asdf:load-system "slynk")
(let ((port (parse-integer (or (uiop:getenv "ARDD_PORT") "4005"))))
  (slynk:create-server :port port :interface "127.0.0.1" :style :spawn :dont-close t)
  (format t "~&ARDD ready. In Emacs: M-x sly-connect, host 127.0.0.1, port ~D.~%" port)
  (finish-output))
(mathbook-dev:serve :window (not (equal (uiop:getenv "ARDD_NO_WINDOW") "1")))
(sb-ext:exit)
