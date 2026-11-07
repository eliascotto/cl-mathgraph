(defpackage #:mathbook
  (:use #:cl #:uiop)
  (:export #:run #:scene #:*scene* #:scene-plane #:scene-dots #:scene-close-requested
           #:run-frame #:dot #:dot-x #:dot-y #:dot-radius #:dot-color #:draw
           #:line #:line-end-x #:line-end-y
           #:cartesian-plane #:axis #:grid #:plane-grid-color #:plane-width #:plane-height
           #:plane-color #:plane-unit-spacing #:plane-zoom #:zoom
           #:plane-center-x #:plane-center-y #:pan))
