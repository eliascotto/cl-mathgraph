;;;; Optional development runtime. Slynk is loaded by the launcher, not Mathbook.
#-sb-thread (error "Mathbook ARDD currently requires threaded SBCL.")

(defpackage #:mathbook-dev
  (:use #:cl)
  (:export #:serve #:eval-string #:on-main-thread #:open-window #:close-window
           #:stop #:status #:*last-frame-error*))
(in-package #:mathbook-dev)

(defvar *lock* (sb-thread:make-mutex :name "Mathbook evaluation queue"))
(defvar *queue* nil)
(defvar *main-thread* nil)
(defvar *running* nil)
(defvar *window-open* nil)
(defvar *open-requested* nil)
(defvar *last-frame-error* nil)

(defstruct request thunk (state :queued) values condition
  (done (sb-thread:make-waitqueue :name "Mathbook evaluation result")))

(defun execute-request (request)
  (handler-case
      (setf (request-values request)
            (multiple-value-list (funcall (request-thunk request))))
    (error (condition) (setf (request-condition request) condition)))
  (sb-thread:with-mutex (*lock*)
    (setf (request-state request) :done)
    (sb-thread:condition-broadcast (request-done request))))

(defun process-requests ()
  "Process a bounded number of queued evaluations between frames."
  (dotimes (index 16)
    (let ((request
            (sb-thread:with-mutex (*lock*)
              (loop for candidate = (pop *queue*) while candidate
                    when (eq (request-state candidate) :queued)
                      do (setf (request-state candidate) :running)
                      and return candidate))))
      (unless request (return))
      (execute-request request))))

(defun on-main-thread (thunk &key (timeout 10))
  "Call THUNK on the development main thread and return all values.
TIMEOUT bounds queue waiting only. A queued request that
times out is cancelled; it will not unexpectedly execute later."
  (check-type timeout (real (0)))
  (unless *running* (error "Start Mathbook with ./dev-repl before evaluating."))
  (when (eq sb-thread:*current-thread* *main-thread*)
    (return-from on-main-thread (funcall thunk)))
  (let ((request (make-request :thunk thunk))
        (deadline (+ (get-internal-real-time)
                     (* timeout internal-time-units-per-second))))
    (sb-thread:with-mutex (*lock*)
      (unless *running* (error "The Mathbook development runtime has stopped."))
      (setf *queue* (nconc *queue* (list request))))
    (loop
      (sb-thread:with-mutex (*lock*)
        (case (request-state request)
          (:done (return))
          (:queued
           (let ((remaining (/ (- deadline (get-internal-real-time))
                               internal-time-units-per-second)))
             (when (<= remaining 0)
               (setf (request-state request) :cancelled)
               (error "Main-thread queue timed out; evaluation cancelled."))
             ;; A timed-out CONDITION-WAIT does not reacquire the mutex.
             ;; Leave this scope immediately; the next iteration acquires it.
             (sb-thread:condition-wait (request-done request) *lock*
                                      :timeout remaining)))
          (:running
           (sb-thread:condition-wait (request-done request) *lock*)))))
    (when (request-condition request) (error (request-condition request)))
    (values-list (request-values request))))

(defun eval-string (source &key (timeout 10))
  "Evaluate SOURCE on the main thread in MATHBOOK; return a printable result.
Output and every value of the last form are returned, including on errors."
  (let ((output (make-string-output-stream)))
    (handler-case
        (let ((values
                (on-main-thread
                 (lambda ()
                   (let ((*package* (find-package :mathbook))
                         (*standard-output* output) (*error-output* output)
                         (*trace-output* output) (*print-circle* t)
                         (*print-level* 8) (*print-length* 100))
                     (with-input-from-string (input source)
                       (let ((eof (gensym)) (values nil))
                         (loop for form = (read input nil eof)
                               until (eq form eof)
                               do (setf values (multiple-value-list (eval form))))
                         (mapcar #'prin1-to-string values)))))
                 :timeout timeout)))
          (list :ok (get-output-stream-string output) values))
      (error (condition)
        (list :error (get-output-stream-string output)
              (princ-to-string condition))))))

(defun open-window ()
  "Request a window on the main thread; reuse the retained scene."
  (on-main-thread (lambda ()
                    (unless *window-open* (setf *open-requested* t))
                    :opening)))

(defun close-window ()
  "Close only the canvas; keep Lisp and SLY connected."
  (on-main-thread (lambda ()
                    (setf *open-requested* nil)
                    (when mathbook:*scene*
                      (setf (mathbook:scene-close-requested mathbook:*scene*) t))
                    :closing)))

(defun stop ()
  "Stop the development runtime after the current evaluation."
  (on-main-thread (lambda () (close-window) (setf *running* nil) :stopping)))

(defun status ()
  "Describe the live runtime without needing the main-thread queue."
  (list :running *running* :window-open *window-open*
        :scene-present (not (null mathbook:*scene*))
        :last-frame-error *last-frame-error*))

(defun report-frame-error (condition)
  (let ((message (princ-to-string condition)))
    (unless (equal message *last-frame-error*)
      (format *error-output* "~&ARDD frame error (fix and reload): ~A~%" message))
    (setf *last-frame-error* message))
  ;; Some drawing failures occur before END-DRAWING can pace the frame.
  (sleep 0.02))

(defun serve (&key (window t))
  "Own the process main thread, serving evaluations with or without a canvas."
  (unless (sb-thread:main-thread-p)
    (error "SERVE must be started on SBCL's main thread, using ./dev-repl."))
  (when *running* (error "The Mathbook development runtime is already running."))
  (setf *main-thread* sb-thread:*current-thread* *running* t
        *open-requested* window)
  (unwind-protect
       (loop while *running*
             do (process-requests)
                (when (and *running* *open-requested*)
                  (setf *open-requested* nil *last-frame-error* nil)
                  (unless mathbook:*scene*
                    (setf mathbook:*scene*
                          (make-instance 'mathbook:scene
                                         :plane (make-instance 'mathbook:cartesian-plane))))
                  (unwind-protect
                       (handler-case
                           (progn
                             (setf *window-open* t)
                             (mathbook:run :scene mathbook:*scene*
                                           :before-frame #'process-requests
                                           :on-frame-error #'report-frame-error))
                         (error (condition) (report-frame-error condition)))
                    (setf *window-open* nil)))
                (sleep 0.01))
    (sb-thread:with-mutex (*lock*)
      (setf *running* nil *main-thread* nil)
      (dolist (request *queue*)
        (setf (request-condition request)
              (make-condition 'simple-error :format-control "Development runtime stopped.")
              (request-state request) :done)
        (sb-thread:condition-broadcast (request-done request)))
      (setf *queue* nil))))
