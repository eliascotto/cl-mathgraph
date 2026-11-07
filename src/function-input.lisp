(in-package #:mathbook)

(defconstant +function-footer-height+ 88)

(defclass function-input ()
  ((text :initarg :text :initform "" :accessor input-text)
   (editing-p :initform nil :accessor input-editing-p)
   (buffer :initform nil :accessor input-buffer))
  (:documentation "Footer text entry, retained with the scene across window reopenings.
The native UTF-8 buffer is allocated lazily and released when the window closes.
Text is stored without evaluation; formula parsing is a separate step."))

(defun ensure-input-buffer (input)
  (unless (input-buffer input)
    (setf (input-buffer input) (raygui:make-text-buffer 4096 (input-text input))))
  ;; Also accept changes to INPUT-TEXT made through the shared REPL.
  (unless (string= (input-text input) (raygui:text-buffer-string (input-buffer input)))
    (setf (raygui:text-buffer-string (input-buffer input)) (input-text input)))
  (input-buffer input))

(defun release-input-buffer (input)
  "Release native text storage while retaining the Lisp text for the next window."
  (when (input-buffer input)
    (raygui:free-text-buffer (input-buffer input))
    (setf (input-buffer input) nil))
  (setf (input-editing-p input) nil))

(defun draw-function-footer (input width height chart-height)
  "Draw the footer below CHART-HEIGHT and update INPUT from raygui."
  (raylib:draw-rectangle 0 chart-height width (- height chart-height) :raywhite)
  (raylib:draw-line 0 chart-height (1- width) chart-height :lightgray)
  (raygui:gui-group-box
   (raylib:make-rectangle :x 12 :y (+ chart-height 12)
                          :width (max 1 (- width 24)) :height 64)
   "Function")
  (raygui:gui-label
   (raylib:make-rectangle :x 28 :y (+ chart-height 30) :width 56 :height 32)
   "f(x) =")
  (multiple-value-bind (text result)
      (raygui:gui-text-box
       (raylib:make-rectangle :x 92 :y (+ chart-height 30)
                              :width (max 1 (- width 120)) :height 32)
       (ensure-input-buffer input) (input-editing-p input))
    (setf (input-text input) text)
    (when (raygui:result-pressed-p result)
      (setf (input-editing-p input) (not (input-editing-p input))))))
