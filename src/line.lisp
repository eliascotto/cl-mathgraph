(in-package #:mathbook)

(defclass line (dot)
  ((end-x :initarg :end-x :initform 100 :accessor line-end-x)
   (end-y :initarg :end-y :initform 0 :accessor line-end-y))
  (:documentation "A one-pixel-wide 2D line segment starting at the inherited dot position.
Uses the inherited color; the inherited radius does not affect line rendering."))

(defmethod draw ((object line))
  (raylib:draw-line (round (dot-x object))
                    (round (dot-y object))
                    (round (line-end-x object))
                    (round (line-end-y object))
                    (dot-color object)))
