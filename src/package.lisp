(defpackage #:mathbook
  (:use #:cl #:uiop)
  (:export #:run #:scene #:*scene* #:scene-plane #:scene-dots #:scene-plots #:scene-close-requested
           #:run-frame #:dot #:dot-x #:dot-y #:dot-radius #:dot-color #:draw
           #:line #:line-end-x #:line-end-y
           #:cartesian-plane #:axis #:grid #:plane-grid-color #:plane-width #:plane-height
           #:plane-color #:plane-unit-spacing #:plane-zoom #:zoom
           #:plane-center-x #:plane-center-y #:pan #:world-to-screen #:screen-to-world
           #:real-function #:function-name #:function-evaluator #:evaluate-at
           #:function-plot #:plot-function #:plot-color #:plot-thickness #:plot-visible-p
           #:plot-x-min #:plot-x-max #:plot-sample-spacing #:plot-tolerance
           #:plot-max-evaluations #:plot-segments #:invalidate-plot #:draw-on-plane))
