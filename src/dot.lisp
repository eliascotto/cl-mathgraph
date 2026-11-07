(in-package #:mathbook)

(defclass dot ()
  ((x :initarg :x :initform 0 :accessor dot-x)
   (y :initarg :y :initform 0 :accessor dot-y)
   (radius :initarg :radius :initform 2.0 :accessor dot-radius)
   (color :initarg :color :initform :black :accessor dot-color))
  (:documentation "A filled 2D dot in canvas pixel coordinates."))

(defgeneric draw (object)
  (:documentation "Draw OBJECT during an active Raylib drawing frame."))

(defmethod draw ((object dot))
  (raylib:draw-circle (round (dot-x object))
                      (round (dot-y object))
                      (coerce (dot-radius object) 'single-float)
                      (dot-color object)))
