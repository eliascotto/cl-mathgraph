(defpackage #:mathbook/tests/ardd
  (:use #:cl #:rove))
(in-package #:mathbook/tests/ardd)

(deftest shared-main-thread-evaluation
  (let* ((results nil)
         (worker
           (sb-thread:make-thread
            (lambda ()
              (loop until mathbook-dev::*running* do (sleep 0.001))
              (unwind-protect
                   (setf results
                         (list (mathbook-dev:eval-string "(sb-thread:main-thread-p)")
                               (mathbook-dev:eval-string
                                "(format t \"hello\") (values 2 3)")
                               (mathbook-dev:eval-string
                                "(format t \"before error\") (error \"expected failure\")")
                               (mathbook-dev:eval-string "(+ 20 22)")
                               (multiple-value-list
                                (mathbook-dev:on-main-thread (lambda () (values :a :b))))))
                (mathbook-dev:stop)))
            :name "ARDD test client")))
    (mathbook-dev:serve :window nil)
    (sb-thread:join-thread worker)
    (ok (equal (first results) '(:ok "" ("T"))))
    (ok (equal (second results) '(:ok "hello" ("2" "3"))))
    (ok (equal (third results) '(:error "before error" "expected failure")))
    (ok (equal (fourth results) '(:ok "" ("42"))))
    (ok (equal (fifth results) '(:a :b)))
    (ok (not (getf (mathbook-dev:status) :running)))))

(deftest cancelled-evaluation-does-not-run-later
  (let ((mathbook-dev::*running* t)
        (mathbook-dev::*main-thread* sb-thread:*current-thread*)
        (executed nil)
        (message nil))
    ;; SBCL thread-local special bindings are not inherited by a new thread.
    (let ((main sb-thread:*current-thread*))
      (sb-thread:join-thread
       (sb-thread:make-thread
        (lambda ()
          (let ((mathbook-dev::*running* t) (mathbook-dev::*main-thread* main))
            (handler-case
                (mathbook-dev:on-main-thread (lambda () (setf executed t)) :timeout 0.02)
              (error (condition) (setf message (princ-to-string condition)))))))))
    (mathbook-dev::process-requests)
    (ok (and message (search "cancelled" message)))
    (ok (not executed))))

(deftest scene-reloads-and-frame-recovery
  (let* ((names '(raylib:init-window raylib:close-window raylib:is-window-ready
                  raylib:set-target-fps raylib:window-should-close mathbook:run-frame))
         (originals (mapcar #'symbol-function names))
         (scene (make-instance 'mathbook:scene :plane nil))
         (frames 0) (errors 0) (closed nil))
    (unwind-protect
         (progn
           (setf (symbol-function 'raylib:init-window) (lambda (&rest args) (declare (ignore args)))
                 (symbol-function 'raylib:close-window) (lambda () (setf closed t))
                 (symbol-function 'raylib:is-window-ready) (lambda () t)
                 (symbol-function 'raylib:set-target-fps) (lambda (fps) (declare (ignore fps)))
                 (symbol-function 'raylib:window-should-close) (lambda () nil)
                 (symbol-function 'mathbook:run-frame)
                 (lambda (state)
                   (declare (ignore state))
                   (incf frames)
                   (error "broken frame")))
           (mathbook:run
            :scene scene
            :before-frame
            (lambda ()
              (when (= frames 1)
                ;; Model loading a corrected frame definition while the loop runs.
                (setf (symbol-function 'mathbook:run-frame)
                      (lambda (state)
                        (incf frames)
                        (setf (mathbook:scene-dots state) '(retained)
                              (mathbook:scene-close-requested state) t)))))
            :on-frame-error (lambda (condition) (declare (ignore condition)) (incf errors)))
           (ok (= errors 1))
           (ok (= frames 2))
           (ok closed)
           (ok (eq scene mathbook:*scene*))
           (ok (equal '(retained) (mathbook:scene-dots scene))))
      (mapc (lambda (name original) (setf (symbol-function name) original)) names originals))))
