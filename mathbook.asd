(defsystem "mathbook"
  :version "0.0.1"
  :depends-on ("uiop" "cl-raylib" "3d-vectors")
  :components ((:module "src"
                :serial t
                :components
                ((:file "package")
                 (:file "dot")
                 (:file "line")
                 (:file "cartesian-plane")
                 (:file "real-function")
                 (:file "function-plot")
                 (:file "main"))))
  :description "An interactive mathematics notebook combining geometry, graphing, and live computation."
  :in-order-to ((test-op (test-op "mathbook/tests"))))

(defsystem "mathbook/tests"
  :depends-on ("mathbook"
               "rove")
  :components ((:module "tests"
                :serial t
                :components
                ((:file "main")
                 (:file "function-plot"))))
  :description "Test system for mathbook"
  ;; Rove's file discovery assumes ASDF's default cache; select registered tests.
  :perform (test-op (op c)
             (let* ((package (find-package :mathbook/tests/main))
                    (tests (loop for symbol being the symbols of package
                                 when (and (eq (symbol-package symbol) package)
                                           (symbol-call :rove :get-test symbol))
                                   collect symbol)))
               (unless (and tests (symbol-call :rove :run-tests tests))
                 (error "Mathbook tests failed or no tests were registered.")))))

(defsystem "mathbook/dev"
  :depends-on ("mathbook")
  :components ((:file "dev/runtime"))
  :description "Optional SBCL main-thread evaluation queue for shared SLY development."
  :in-order-to ((test-op (test-op "mathbook/dev/tests"))))

(defsystem "mathbook/dev/tests"
  :depends-on ("mathbook/dev" "rove")
  :components ((:file "tests/ardd"))
  :perform (test-op (op c)
             (let* ((package (find-package :mathbook/tests/ardd))
                    (tests (loop for symbol being the symbols of package
                                 when (and (eq (symbol-package symbol) package)
                                           (symbol-call :rove :get-test symbol))
                                   collect symbol)))
               (unless (and tests (symbol-call :rove :run-tests tests))
                 (error "Mathbook ARDD tests failed or no tests were registered.")))))
