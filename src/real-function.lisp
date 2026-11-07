(in-package #:mathbook)

(defclass real-function ()
  ((name :initarg :name :initform nil :accessor function-name)
   (evaluator :initarg :evaluator
              :initform (error "A REAL-FUNCTION requires an :EVALUATOR.")
              :accessor function-evaluator))
  (:documentation "A mathematical function of one real variable, independent of rendering.
EVALUATOR is a Lisp function accepting x. NAME is an optional display label."))

(defgeneric evaluate-at (function x)
  (:documentation "Evaluate FUNCTION at real X. Errors propagate to the caller.
Plot sampling treats errors and non-real or nonfinite results as gaps."))

(defmethod evaluate-at ((function real-function) x)
  (check-type x real)
  (funcall (function-evaluator function) x))
