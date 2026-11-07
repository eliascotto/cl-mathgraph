(in-package #:mathbook)

(defclass function-plot ()
  ((function :initarg :function :accessor plot-function)
   (color :initarg :color :initform :blue :accessor plot-color)
   (thickness :initarg :thickness :initform 2 :accessor plot-thickness)
   (visible-p :initarg :visible-p :initform t :accessor plot-visible-p)
   (x-min :initarg :x-min :initform nil :accessor plot-x-min)
   (x-max :initarg :x-max :initform nil :accessor plot-x-max)
   (sample-spacing :initarg :sample-spacing :initform 8 :accessor plot-sample-spacing)
   (tolerance :initarg :tolerance :initform 0.75d0 :accessor plot-tolerance)
   (max-evaluations :initarg :max-evaluations :initform 8193 :accessor plot-max-evaluations)
   (cache-key :initform nil :accessor plot-cache-key)
   (segments :initform nil :accessor plot-cached-segments))
  (:documentation "A styled graph of y=f(x) in world coordinates.
Optional inclusive X-MIN/X-MAX restrict the domain. Sampling distances and
TOLERANCE are in pixels. MAX-EVALUATIONS bounds calls per resampling, not the
execution time of an individual evaluator. Evaluators should be pure and finite."))

(defgeneric draw-on-plane (object plane)
  (:documentation "Draw OBJECT in world coordinates on PLANE in an active frame."))

(defun invalidate-plot (plot)
  "Discard PLOT's sampled geometry after changing state captured by its evaluator.
Replacing the evaluator or changing the plot or view settings invalidates it automatically."
  (setf (plot-cache-key plot) nil)
  plot)

(defun finite-plot-number (value)
  "Return VALUE as a finite double float, or NIL if it cannot be plotted."
  (handler-case
      (when (realp value)
        (let ((number (float value 1d0)))
          (when (<= (- most-positive-double-float) number most-positive-double-float)
            number)))
    (arithmetic-error () nil)
    (type-error () nil)))

(defun clip-plot-segment (x1 y1 x2 y2 width height)
  "Clip a pixel segment to the canvas, returning (x1 y1 x2 y2) or NIL."
  ;; Rational intermediates avoid overflow for finite but very large y values.
  (let* ((x1 (rational x1)) (y1 (rational y1))
         (dx (- (rational x2) x1)) (dy (- (rational y2) y1))
         (start 0) (end 1))
    (loop for p in (list (- dx) dx (- dy) dy)
          for q in (list x1 (- (1- width) x1) y1 (- (1- height) y1))
          do (cond ((zerop p)
                    (when (minusp q) (return-from clip-plot-segment nil)))
                   ((minusp p) (setf start (max start (/ q p))))
                   (t (setf end (min end (/ q p)))))
             (when (> start end) (return-from clip-plot-segment nil)))
    (list (float (+ x1 (* start dx)) 1d0) (float (+ y1 (* start dy)) 1d0)
          (float (+ x1 (* end dx)) 1d0) (float (+ y1 (* end dy)) 1d0))))

(defun sample-function-plot (plot plane)
  "Build clipped pixel segments, refining until midpoint error meets the tolerance.
Unresolved intervals are omitted at the depth or evaluation limit. Discontinuity
detection is heuristic; finite sampling cannot find every pole or oscillation."
  (let* ((width (plane-width plane)) (height (plane-height plane))
         (spacing (plot-sample-spacing plot)) (tolerance (plot-tolerance plot))
         (budget (plot-max-evaluations plot))
         (domain-min (plot-x-min plot)) (domain-max (plot-x-max plot))
         (evaluations 0) (segments nil))
    (check-type spacing (real (0)))
    (check-type tolerance (real (0)))
    (check-type budget (integer 3 *))
    (when domain-min (check-type domain-min real))
    (when domain-max (check-type domain-max real))
    (when (and domain-min domain-max (> domain-min domain-max))
      (error "Plot X-MIN must not exceed X-MAX."))
    (when (or (< width 2) (< height 2)) (return-from sample-function-plot nil))
    (let* ((left (if domain-min (max 0 (world-to-screen plane domain-min 0)) 0))
           (right (if domain-max (min (1- width) (world-to-screen plane domain-max 0))
                      (1- width))))
      (unless (< left right) (return-from sample-function-plot nil))
      (labels ((sample (screen-x)
                 (when (< evaluations budget)
                   (incf evaluations)
                   (handler-case
                       (let* ((x (screen-to-world plane screen-x 0))
                              (y (finite-plot-number (evaluate-at (plot-function plot) x))))
                         (when y
                           (finite-plot-number (nth-value 1 (world-to-screen plane x y)))))
                     (error () nil))))
               (refine (x1 y1 middle ym x2 y2 depth)
                 (let ((error-limit
                         ;; Do not mistake floating-point roundoff in very steep
                         ;; straight lines for curvature that never converges.
                         (when (and y1 ym y2)
                           (max (/ tolerance 2)
                                (* 16 double-float-epsilon
                                   (max (abs y1) (abs ym) (abs y2)))))))
                   (cond
                     ((and y1 ym y2
                           ;; Divide before addition to avoid overflow.
                           (<= (abs (- (/ ym 2) (/ y1 4) (/ y2 4))) error-limit))
                      (let ((segment (clip-plot-segment x1 y1 x2 y2 width height)))
                        (when segment (push segment segments))))
                     ((and (< depth 12) (< evaluations budget)
                           ;; An entirely invalid interval needs no further work.
                           (or y1 ym y2))
                      (let* ((quarter (/ (+ x1 middle) 2))
                             (three-quarters (/ (+ middle x2) 2))
                             (yq (sample quarter)) (y3q (sample three-quarters)))
                        (refine x1 y1 quarter yq middle ym (1+ depth))
                        (refine middle ym three-quarters y3q x2 y2 (1+ depth))))))))
        ;; Reserve a baseline across the whole view before adaptive refinement.
        (let* ((count (min (ceiling (- right left) spacing) (floor (1- budget) 2)))
               (xs (loop for i from 0 to (* 2 count)
                         collect (+ left (* (/ i (* 2 count)) (- right left)))))
               (ys (mapcar #'sample xs)))
          (loop for (x1 middle x2) on xs by #'cddr while x2
                for (y1 ym y2) on ys by #'cddr
                do (refine x1 y1 middle ym x2 y2 0)))))
    (nreverse segments)))

(defun plot-segments (plot plane)
  "Return cached clipped pixel segments for PLOT and PLANE. Treat the list as read-only."
  (let ((key (list (plot-function plot) (function-evaluator (plot-function plot))
                   (plot-x-min plot) (plot-x-max plot) (plot-sample-spacing plot)
                   (plot-tolerance plot) (plot-max-evaluations plot)
                   (plane-width plane) (plane-height plane) (plane-unit-spacing plane)
                   (plane-zoom plane) (plane-center-x plane) (plane-center-y plane))))
    (unless (equal key (plot-cache-key plot))
      (setf (plot-cached-segments plot) (sample-function-plot plot plane)
            (plot-cache-key plot) key))
    (plot-cached-segments plot)))

(defmethod draw-on-plane ((plot function-plot) (plane cartesian-plane))
  (when (plot-visible-p plot)
    (let ((thickness (plot-thickness plot)))
      (check-type thickness (real (0)))
      (dolist (segment (plot-segments plot plane))
        (destructuring-bind (x1 y1 x2 y2) segment
          (raylib:draw-line-ex (3d-vectors:vec2 x1 y1) (3d-vectors:vec2 x2 y2)
                               (coerce thickness 'single-float) (plot-color plot)))))))
