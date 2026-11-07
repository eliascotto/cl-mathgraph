(defpackage mathbook/tests/main
  (:use :cl
        :rove))
(in-package :mathbook/tests/main)

;; NOTE: To run this test file, execute `(asdf:test-system :mathbook)' in your Lisp.

(deftest adaptive-tick-labels
  (testing "zoom selects readable steps with exact decimal labels"
    (dolist (example '((1d0 ("1" "2" "3"))
                       (2d0 ("0.5" "1" "1.5"))
                       (5d0 ("0.2" "0.4" "0.6"))
                       (0.5d0 ("2" "4" "6"))
                       (0.1d0 ("10" "20" "30"))))
      (destructuring-bind (magnification expected) example
        (let* ((plane (make-instance 'mathbook:cartesian-plane :zoom magnification))
               (step (nth-value 3 (mathbook::plane-layout plane))))
          (ok (equal expected (loop for index from 1 to 3
                                    collect (mathbook::axis-label index step))))
          (ok (equal (mapcar (lambda (text) (concatenate 'string "-" text)) expected)
                     (loop for index from -1 downto -3
                           collect (mathbook::axis-label index step)))))))))

(deftest wheel-zoom
  (testing "wheel direction, fractional movement, reversibility, and limits"
    (let ((plane (make-instance 'mathbook:cartesian-plane)))
      (mathbook:zoom plane 0.5d0)
      (ok (> (mathbook:plane-zoom plane) 1d0))
      (mathbook:zoom plane -0.5d0)
      (ok (< (abs (- (mathbook:plane-zoom plane) 1d0)) 1d-12))
      (mathbook:zoom plane -1d0)
      (ok (< (mathbook:plane-zoom plane) 1d0))
      (mathbook:zoom plane 1000000)
      (ok (< (abs (- (mathbook:plane-zoom plane) 1d6)) 1d-6))
      (mathbook:zoom plane -1000000)
      (ok (< (abs (- (mathbook:plane-zoom plane) 1d-6)) 1d-15)))))

(defun capture-plane-drawing (plane)
  "Capture drawing commands without opening a window or using a graphics context."
  (let* ((names '(raylib:draw-line raylib:draw-text
                  raylib:draw-rectangle raylib:measure-text))
         (originals (mapcar #'symbol-function names))
         (lines nil)
         (labels nil))
    (unwind-protect
         (progn
           (setf (symbol-function 'raylib:draw-line)
                 (lambda (&rest args) (push args lines))
                 (symbol-function 'raylib:draw-text)
                 (lambda (&rest args) (push args labels))
                 (symbol-function 'raylib:draw-rectangle)
                 (lambda (&rest args) (declare (ignore args)))
                 (symbol-function 'raylib:measure-text)
                 (lambda (text size) (declare (ignore size)) (* 6 (length text))))
           (mathbook:grid plane)
           (mathbook:axis plane)
           (values lines labels))
      (mapc (lambda (name original) (setf (symbol-function name) original))
            names originals))))

(defun four-way-subdivisions-p (lines boundaries vertical-p)
  "Every complete major interval must contain three evenly spaced minor lines."
  (let ((positions (remove-duplicates
                    (loop for (x1 y1 x2 y2 color) in lines
                          when (and (not (eq color :black))
                                    (if vertical-p (= x1 x2) (= y1 y2)))
                            collect (if vertical-p x1 y1))))
        (boundaries (sort (copy-list boundaries) #'<)))
    (loop for (start end) on boundaries
          while end
          always (let ((interior (sort (remove-if-not (lambda (position) (< start position end))
                                                     positions)
                                      #'<)))
                   (and (= 3 (length interior))
                        (loop for position in interior
                              for quarter from 1 to 3
                              always (<= (abs (- position (+ start (* quarter (/ (- end start) 4)))))
                                         1)))))))

(deftest centered-and-aligned-zoom
  (testing "zero stays centered, major lines align with ticks, and each cell has 16 squares"
    (dolist (magnification '(1d-6 0.01d0 0.1d0 0.5d0 1d0 1.8d0 2d0 3.2d0 5d0 10d0 100d0 1d6))
      (let ((plane (make-instance 'mathbook:cartesian-plane
                                  :width 800 :height 600 :zoom magnification)))
        (multiple-value-bind (lines labels) (capture-plane-drawing plane)
          (ok (member '(0 300 799 300 :black) lines :test #'equal))
          (ok (member '(400 0 400 599 :black) lines :test #'equal))
          (ok (= 1 (count "0" labels :key #'first :test #'string=)))
          (ok (member '("0" 386 308 12 :black) labels :test #'equal))
          (let ((x-ticks (loop for (x1 y1 x2 y2 color) in lines
                               when (and (eq color :black) (= x1 x2)
                                         (= y1 297) (= y2 303))
                                 collect x1))
                (y-ticks (loop for (x1 y1 x2 y2 color) in lines
                               when (and (eq color :black) (= y1 y2)
                                         (= x1 397) (= x2 403))
                                 collect y1)))
            (ok (every (lambda (line)
                         (destructuring-bind (x1 y1 x2 y2 color) line
                           (or (eq color :black)
                               (and (<= 0 x1 x2 799) (<= 0 y1 y2 599)
                                    (if (= x1 x2)
                                        (and (/= x1 400) (= y1 0) (= y2 599))
                                        (and (= y1 y2) (/= y1 300) (= x1 0) (= x2 799)))))))
                       lines))
            (ok (four-way-subdivisions-p lines (cons 400 x-ticks) t))
            (ok (four-way-subdivisions-p lines (cons 300 y-ticks) nil)))
          (ok (every (lambda (label)
                       (destructuring-bind (text x y size color) label
                         (declare (ignore size color))
                         (let ((value (read-from-string text)))
                           (or (zerop value)
                               (if (= y 308)
                                   (<= (abs (- (+ x (* 3 (length text)))
                                               (+ 400 (* value 60 magnification)))) 1)
                                   (<= (abs (- (+ y 6)
                                               (- 300 (* value 60 magnification)))) 1))))))
                     labels)))))))

(defun plane-origin (plane)
  (multiple-value-bind (x y) (mathbook::plane-layout plane)
    (list x y)))

(deftest panning-and-zoom
  (testing "the plane follows the drag in pixels at every zoom level"
    (dolist (magnification '(0.1d0 1d0 1.8d0 5d0 100d0))
      (let ((plane (make-instance 'mathbook:cartesian-plane
                                  :width 800 :height 600 :zoom magnification)))
        (mathbook:pan plane 120 -45)
        (ok (equal '(520 255) (plane-origin plane)))
        (multiple-value-bind (lines labels) (capture-plane-drawing plane)
          (ok (member '(0 255 799 255 :black) lines :test #'equal))
          (ok (member '(520 0 520 599 :black) lines :test #'equal))
          (ok (member '("0" 506 263 12 :black) labels :test #'equal)))
        (let ((center-x (mathbook:plane-center-x plane))
              (center-y (mathbook:plane-center-y plane)))
          (mathbook:zoom plane 2)
          (ok (= center-x (mathbook:plane-center-x plane)))
          (ok (= center-y (mathbook:plane-center-y plane)))
          (ok (equal (list (round (+ 400 (* 120 (expt 1.15d0 2))))
                           (round (- 300 (* 45 (expt 1.15d0 2)))))
                     (plane-origin plane))))
        (mathbook:zoom plane -2)
        (mathbook:pan plane -120 45)
        (ok (equal '(400 300) (plane-origin plane)))))))

(deftest offscreen-panning
  (testing "the grid still fills the canvas when both axes leave the view"
    (let ((plane (make-instance 'mathbook:cartesian-plane :width 800 :height 600)))
      (mathbook:pan plane 1000 900)
      (multiple-value-bind (lines labels) (capture-plane-drawing plane)
        (ok lines)
        (ok (null labels))
        (ok (every (lambda (line)
                     (destructuring-bind (x1 y1 x2 y2 color) line
                       (and (not (eq color :black))
                            (<= 0 x1 x2 799) (<= 0 y1 y2 599))))
                   lines)))))
  (testing "zero is not drawn when its intersection is just outside the canvas"
    (let ((plane (make-instance 'mathbook:cartesian-plane :width 800 :height 600)))
      (mathbook:pan plane 0 -305)
      (multiple-value-bind (lines labels) (capture-plane-drawing plane)
        (declare (ignore lines))
        (ok (zerop (count "0" labels :key #'first :test #'string=)))))))

(deftest mouse-drag-lifecycle
  (testing "only held-button movement pans; release, fresh presses, and focus loss reset dragging"
    (let* ((names '(raylib:get-mouse-wheel-move raylib:is-window-focused
                    raylib:is-mouse-button-down raylib:is-mouse-button-pressed
                    raylib:get-mouse-x raylib:get-mouse-y))
           (originals (mapcar #'symbol-function names))
           (plane (make-instance 'mathbook:cartesian-plane :width 800 :height 600))
           (down nil) (pressed nil) (focused t) (wheel 0) (x 100) (y 100)
           (drag-position nil))
      (unwind-protect
           (progn
             (setf (symbol-function 'raylib:get-mouse-wheel-move) (lambda () wheel)
                   (symbol-function 'raylib:is-window-focused) (lambda () focused)
                   (symbol-function 'raylib:is-mouse-button-down)
                   (lambda (button) (assert (eq button :mouse-button-left)) down)
                   (symbol-function 'raylib:is-mouse-button-pressed)
                   (lambda (button) (assert (eq button :mouse-button-left)) pressed)
                   (symbol-function 'raylib:get-mouse-x) (lambda () x)
                   (symbol-function 'raylib:get-mouse-y) (lambda () y))
             (flet ((frame ()
                      (setf drag-position (mathbook::update-plane-input plane drag-position))))
               (frame)
               (ok (null drag-position))
               (setf down t pressed t)
               (frame)
               (ok (equal '(400 300) (plane-origin plane)))
               (setf pressed nil x 125 y 80)
               (frame)
               (ok (equal '(425 280) (plane-origin plane)))
               (setf down nil)
               (frame)
               (setf x 500 y 400)
               (frame)
               (ok (equal '(425 280) (plane-origin plane)))
               (setf down t pressed t)
               (frame)
               (ok (equal '(425 280) (plane-origin plane)))
               (setf pressed nil x 510 y 410)
               (frame)
               (ok (equal '(435 290) (plane-origin plane)))
               (setf focused nil x 700 y 700)
               (frame)
               (ok (null drag-position))
               (setf focused t x 710 y 710)
               (frame)
               (ok (equal '(435 290) (plane-origin plane)))
               (setf wheel 1 down nil)
               (frame)
               (ok (> (mathbook:plane-zoom plane) 1d0))))
        (mapc (lambda (name original) (setf (symbol-function name) original))
              names originals)))))
