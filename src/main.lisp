(in-package #:mathbook)

(defun update-plane-input (plane previous-drag-position &key (enabled-p t))
  "Apply wheel zoom and left-button drag input; return the current drag position."
  (unless enabled-p (return-from update-plane-input nil))
  (let ((wheel (raylib:get-mouse-wheel-move)))
    (unless (zerop wheel)
      (zoom plane wheel)))
  (when (and (raylib:is-window-focused)
             (raylib:is-mouse-button-down :mouse-button-left))
    (let ((x (raylib:get-mouse-x))
          (y (raylib:get-mouse-y)))
      (when (and previous-drag-position
                 (not (raylib:is-mouse-button-pressed :mouse-button-left)))
        (pan plane (- x (car previous-drag-position))
                   (- y (cdr previous-drag-position))))
      (cons x y))))

(defclass scene ()
  ((plane :initarg :plane :initform (make-instance 'cartesian-plane) :accessor scene-plane)
   (dots :initarg :dots :initform nil :accessor scene-dots)
   (plots :initarg :plots :initform nil :accessor scene-plots)
   (input :initarg :input :initform (make-instance 'function-input) :accessor scene-input)
   (close-requested :initform nil :accessor scene-close-requested)
   (drag-position :initform nil :accessor scene-drag-position))
  (:documentation "Live canvas state, retained independently of the window."))

(defvar *scene* nil "The most recently opened scene; preserved across source reloads.")

(defun update-scene-layout (scene width height)
  "Size the chart above the footer; return the chart height in pixels."
  (let ((chart-height (max 1 (- height (if (scene-input scene) +function-footer-height+ 0)))))
    (when (scene-plane scene)
      (setf (plane-width (scene-plane scene)) width
            (plane-height (scene-plane scene)) chart-height))
    chart-height))

(defun draw-scene-chart (scene width chart-height)
  "Clip chart content so pixel-coordinate objects cannot overlap the footer."
  (raylib:begin-scissor-mode 0 0 width chart-height)
  (unwind-protect
       (progn
         (when (scene-plane scene)
           (grid (scene-plane scene))
           (axis (scene-plane scene))
           (dolist (plot (scene-plots scene))
             (draw-on-plane plot (scene-plane scene))))
         (dolist (dot (scene-dots scene))
           (draw dot)))
    (raylib:end-scissor-mode)))

(defun run-frame (scene)
  "Update and draw SCENE. Redefinitions take effect on the next frame."
  (let* ((width (raylib:get-screen-width)) (height (raylib:get-screen-height))
         (chart-height (update-scene-layout scene width height))
         (plane (scene-plane scene)))
    (when plane
      (setf (scene-drag-position scene)
            (update-plane-input plane (scene-drag-position scene)
                                :enabled-p (and (<= 0 (raylib:get-mouse-x) (1- width))
                                                (<= 0 (raylib:get-mouse-y) (1- chart-height))))))
    (raylib:with-drawing
      (raylib:clear-background :white)
      (draw-scene-chart scene width chart-height)
      (when (scene-input scene)
        (draw-function-footer (scene-input scene) width height chart-height)))))

(defun run (&key (width 1024) (height 768) (title "Mathbook")
                 (plane (make-instance 'cartesian-plane :width width :height height))
                 (dots nil) (plots nil) (input (make-instance 'function-input))
                 scene before-frame on-frame-error)
  "Open a canvas and function footer until closed or Escape is pressed.
Supply INPUT NIL to hide the footer.
Call this on the main thread of your Lisp process."
  #+(and sbcl darwin)
  (unless (sb-thread:main-thread-p)
    (error "Mathbook's window must run on the main thread on macOS. Launch it from a standalone SBCL process; SLY and SLIME evaluate on worker threads."))
  (setf scene (or scene (make-instance 'scene :plane plane :dots dots :plots plots :input input))
        *scene* scene
        (scene-close-requested scene) nil
        (scene-drag-position scene) nil)
  ;; The multisampled framebuffer must be requested before window creation.
  (raylib:set-config-flags :flag-msaa-4x-hint)
  (raylib:with-window (width height title)
    (unless (raylib:is-window-ready)
      (error "Could not initialize the Mathbook window."))
    (unwind-protect
         (progn
           (initialize-interface)
           (raylib:set-target-fps 60)
           (loop until (or (scene-close-requested scene) (raylib:window-should-close))
                 do (when before-frame (funcall before-frame))
                    (when (scene-close-requested scene) (return))
                    (if on-frame-error
                        (handler-case (run-frame scene)
                          (error (condition) (funcall on-frame-error condition)))
                        (run-frame scene))))
      (when (scene-input scene)
        (release-input-buffer (scene-input scene)))
      (release-interface-font)))
  scene)
