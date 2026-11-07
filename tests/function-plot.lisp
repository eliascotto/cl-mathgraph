(in-package :mathbook/tests/main)

(defun test-plot (evaluator &rest options)
  (apply #'make-instance 'mathbook:function-plot
         :function (make-instance 'mathbook:real-function :evaluator evaluator) options))

(defun clipped-segments-p (segments width height)
  (every (lambda (segment)
           (destructuring-bind (x1 y1 x2 y2) segment
             (and (<= 0 x1 x2 (1- width)) (<= 0 y1 (1- height))
                  (<= 0 y2 (1- height)))))
         segments))

(deftest real-function-evaluation
  (let ((function (make-instance 'mathbook:real-function :name "square"
                                 :evaluator (lambda (x) (* x x)))))
    (ok (= 9 (mathbook:evaluate-at function 3)))
    (ok (string= "square" (mathbook:function-name function)))
    (setf (mathbook:function-evaluator function) (lambda (x) (/ 1 x)))
    (ok (signals (mathbook:evaluate-at function 0) 'division-by-zero))))

(deftest world-screen-conversion
  (dolist (magnification '(1d-6 0.1d0 1d0 3.2d0 1d6))
    (let ((plane (make-instance 'mathbook:cartesian-plane :width 801 :height 601
                                :zoom magnification :center-x 2.5d0 :center-y -3d0)))
      (ok (equalp '(400.5d0 300.5d0)
                  (multiple-value-list (mathbook:world-to-screen plane 2.5d0 -3d0))))
      (multiple-value-bind (sx sy) (mathbook:world-to-screen plane 1.25d0 4.5d0)
        (multiple-value-bind (x y) (mathbook:screen-to-world plane sx sy)
          (ok (< (abs (- x 1.25d0)) 1d-8))
          (ok (< (abs (- y 4.5d0)) 1d-8)))))))

(deftest plot-geometry-and-domain
  (let* ((plane (make-instance 'mathbook:cartesian-plane :width 800 :height 600))
         (plot (test-plot (lambda (x) (* x x)) :x-min -1 :x-max 2))
         (segments (mathbook:plot-segments plot plane)))
    (ok segments)
    (ok (clipped-segments-p segments 800 600))
    (ok (< (abs (- (first (first segments)) 340)) 1d-8))
    (ok (< (abs (- (third (car (last segments))) 520)) 1d-8))
    (ok (every (lambda (segment)
                 (destructuring-bind (x1 y1 x2 y2) segment
                   (let* ((x (mathbook:screen-to-world plane (/ (+ x1 x2) 2) 0))
                          (expected (nth-value 1 (mathbook:world-to-screen plane x (* x x)))))
                     (<= (abs (- expected (/ (+ y1 y2) 2))) 0.750001d0))))
               segments))
    (setf (mathbook:plot-x-min plot) 100)
    (setf (mathbook:plot-x-max plot) 101)
    (ok (null (mathbook:plot-segments plot plane)))
    (setf (mathbook:plot-x-max plot) 99)
    (ok (signals (mathbook:plot-segments plot plane) 'error))))

(deftest plot-clipping-and-steep-lines
  (let ((plane (make-instance 'mathbook:cartesian-plane :width 800 :height 600)))
    (dolist (slope '(1d0 1d6 1d100))
      (let ((segments (mathbook:plot-segments (test-plot (lambda (x) (* slope x))) plane)))
        (ok segments)
        (ok (clipped-segments-p segments 800 600))))
    (ok (null (mathbook:plot-segments (test-plot (lambda (x) (declare (ignore x)) 1d200))
                                     plane)))))

(deftest plot-gaps-and-asymptotes
  (let ((plane (make-instance 'mathbook:cartesian-plane :width 800 :height 600)))
    (testing "poles between sample points never acquire a cross-canvas bridge"
      (dolist (pole '(0d0 0.013d0 -1.237d0))
        (let* ((segments (mathbook:plot-segments
                          (test-plot (lambda (x) (/ 1d0 (- x pole)))) plane))
               (pole-x (mathbook:world-to-screen plane pole 0)))
          (ok segments)
          (ok (clipped-segments-p segments 800 600))
          (ok (every (lambda (segment)
                       (not (< (first segment) pole-x (third segment)))) segments)))))
    (testing "sqrt excludes its complex-valued half of the domain"
      (let ((segments (mathbook:plot-segments (test-plot #'sqrt) plane)))
        (ok segments)
        (ok (every (lambda (segment) (>= (first segment) 400)) segments))))
    (testing "sign jumps are gaps, and a bad evaluator does not stop other plots"
      (let ((segments (mathbook:plot-segments
                        (test-plot (lambda (x) (if (< x 0.013d0) -1d0 1d0))) plane)))
        (ok segments)
        (ok (every (lambda (segment) (< (abs (- (second segment) (fourth segment))) 1))
                   segments)))
      (dolist (evaluator (list (lambda (x) (declare (ignore x)) (error "Undefined"))
                              (lambda (x) (declare (ignore x)) :invalid)
                              (lambda (x) (declare (ignore x)) #c(1 2))
                              #+sbcl (lambda (x) (declare (ignore x))
                                       sb-ext:double-float-positive-infinity)
                              #+sbcl (lambda (x) (declare (ignore x))
                                       (sb-kernel:make-double-float #x7ff80000 0))))
        (ok (null (mathbook:plot-segments (test-plot evaluator) plane)))))))

(deftest plot-budget-and-cache
  (let* ((calls 0) (offset 0d0)
         (plane (make-instance 'mathbook:cartesian-plane))
         (plot (test-plot (lambda (x) (incf calls) (+ offset (sin (* 1000 x))))
                          :max-evaluations 301))
         (segments (mathbook:plot-segments plot plane)))
    (ok (<= 1 calls 301))
    (let ((before calls))
      (ok (eq segments (mathbook:plot-segments plot plane)))
      (ok (= before calls))
      (setf (mathbook:plot-color plot) :red)
      (mathbook:plot-segments plot plane)
      (ok (= before calls))
      (mathbook:pan plane 10 20)
      (mathbook:plot-segments plot plane)
      (ok (< before calls)))
    (dolist (change (list (lambda () (mathbook:zoom plane 1))
                         (lambda () (setf (mathbook:plot-x-min plot) 0))
                         (lambda () (setf (mathbook:plot-tolerance plot) 0.5d0))
                         (lambda () (setf (mathbook:plot-sample-spacing plot) 4))
                         (lambda () (setf (mathbook:plane-width plane) 800))
                         (lambda () (incf offset) (mathbook:invalidate-plot plot))))
      (let ((before calls))
        (funcall change)
        (mathbook:plot-segments plot plane)
        (ok (< before calls))
        (ok (<= (- calls before) 301))))
    (setf (mathbook:function-evaluator (mathbook:plot-function plot))
          (lambda (x) (declare (ignore x)) (incf calls) 0))
    (let ((before calls))
      (ok (mathbook:plot-segments plot plane))
      (ok (< before calls)))))

(deftest plot-rendering-and-scene
  ;; These substitutions run only in the fresh test process, never in ARDD.
  (let* ((names '(raylib:begin-drawing raylib:end-drawing raylib:clear-background
                  raylib:get-mouse-wheel-move raylib:is-window-focused
                  raylib:get-screen-width raylib:get-screen-height
                  raylib:get-mouse-x raylib:get-mouse-y
                  raylib:begin-scissor-mode raylib:end-scissor-mode
                  mathbook:grid mathbook:axis raylib:draw-line-ex))
         (originals (mapcar #'symbol-function names))
         (plane (make-instance 'mathbook:cartesian-plane))
         (plot (test-plot #'sin :color :purple :thickness 3))
         (scene (make-instance 'mathbook:scene :plane plane :plots (list plot) :input nil))
         (drawn nil))
    (unwind-protect
         (progn
           (dolist (name names)
             (setf (symbol-function name) (lambda (&rest args) (declare (ignore args)) nil)))
           (setf (symbol-function 'raylib:get-mouse-wheel-move) (lambda () 0)
                 (symbol-function 'raylib:get-screen-width) (lambda () 1024)
                 (symbol-function 'raylib:get-screen-height) (lambda () 768)
                 (symbol-function 'raylib:get-mouse-x) (lambda () 100)
                 (symbol-function 'raylib:get-mouse-y) (lambda () 100)
                 (symbol-function 'raylib:draw-line-ex)
                 (lambda (start end thickness color)
                   (push (list start end thickness color) drawn)))
           (mathbook:run-frame scene)
           (ok drawn)
           (ok (= (length drawn) (length (mathbook:plot-segments plot plane))))
           (ok (every (lambda (call) (and (= 3 (third call)) (eq :purple (fourth call)))) drawn))
           (setf drawn nil (mathbook:plot-visible-p plot) nil)
           (mathbook:run-frame scene)
           (ok (null drawn))
           (setf (mathbook:plot-visible-p plot) t (mathbook:scene-plane scene) nil)
           (mathbook:run-frame scene)
           (ok (null drawn)))
      (mapc (lambda (name original) (setf (symbol-function name) original)) names originals))))
