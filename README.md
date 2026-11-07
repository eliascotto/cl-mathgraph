# Mathbook

Mathbook is a Common Lisp project for an interactive mathematics workspace,
bringing together the dynamic geometry of GeoGebra, the graphing experience of
Desmos, and the executable notebook workflow of Jupyter.

The intended experience combines geometric constructions, function plots, prose,
and live computations in a single notebook.

## Status

This repository starts from a Common Lisp project skeleton generated with
[cl-project](https://github.com/fukamachi/cl-project) and opens a Raylib window
with a white canvas, black Cartesian axes, a subdivided gray grid, mouse-wheel
zoom, click-and-drag panning, plots of Lisp functions of one real variable, and
a footer text input. Geometric constructions, formula parsing, notebook cells,
notebook evaluation, persistence, and further interface controls are not implemented yet.

## Requirements

- A Common Lisp implementation, such as SBCL, with ASDF.
- Quicklisp for loading dependencies, including Rove for tests.
- `cl-raylib`, available through Quicklisp's `local-projects` directory, with its
  native raylib library available to the bindings.
- [cl-raygui](https://github.com/eliascotto/cl-raygui), with its native raygui
  library built against the same shared raylib installation (raylib 6.0 or newer).

The application system depends on `cl-raylib`, `cl-raygui`, `3d-vectors` (also used by the
Raylib bindings), and UIOP (bundled with ASDF).
`cl-project` is used to generate the skeleton and is not required to load Mathbook.

For a checkout at `~/dev/Lisp/cl-raygui`, register it with Quicklisp using a symlink
(skip the link command if it already exists). On macOS, build its native library
if needed using the repository's build helper:

```sh
ln -s ~/dev/Lisp/cl-raygui ~/quicklisp/local-projects/cl-raygui
bash ~/dev/Lisp/cl-raygui/tools/build-macos.sh
```

All application source files share the `mathbook` package, defined once in
`src/package.lisp`. It uses Common Lisp and UIOP, so UIOP utilities such as
`getcwd` and `define-package` are available without a `uiop:` prefix inside it.

## Load the project

With Quicklisp loaded, start a Lisp REPL in the repository root and evaluate:

```lisp
(require :asdf)
(asdf:load-asd (merge-pathnames #p"mathbook.asd" (uiop:getcwd)))
(ql:quickload "mathbook")
(in-package #:mathbook)
```

## Open the window

From the repository root, run:

```sh
./run
```

The launcher uses SBCL and the Quicklisp setup in your SBCL startup file. It
loads the latest saved source each time and works when called from another
directory using its full path.

In Emacs, save your changes, then use `M-x compile` and enter `./run` from a
buffer in the project root (or enter `/Users/elia/dev/Lisp/Mathbook/run` from
any buffer). Emacs stays responsive while the window runs, and output appears
in `*compilation*`. Close the window, save your next changes, and use
`M-x recompile` to launch again.

On macOS, use a standalone Lisp process to open the window. SLY and SLIME
evaluate on worker threads, where Raylib window initialization can hang.
Mathbook rejects these calls on SBCL before initializing Raylib. You can still
load and compile the project in SLY or SLIME.

For a persistent canvas shared with an agent through Emacs SLY, see
[ARDD.md](ARDD.md). Its development launcher runs window operations on the main
thread and evaluates scene changes between frames.

After loading, call the exported entry point on the Lisp process's main thread
(required on macOS):

```lisp
(mathbook:run)
```

This opens a 1024 × 768 window titled "Mathbook", with centered black x/y
axes, one pixel thick, with numbered ticks. No sample dots or line segments are
shown. The window requests 4× MSAA for smoother curve and line edges on supported
graphics hardware. It redraws the canvas
at 60 FPS, and blocks until you close the window or press Escape. The window is
also cleaned up if the drawing loop exits through an error.

Hold the left mouse button and drag to pan the plane. The grid, axes, and labels
follow the pointer; release the button to stop. The origin starts at the center
and moves when you pan. Losing window focus also ends the current drag.

Scroll the mouse wheel up to zoom in and down to zoom out. Trackpad scrolling
also works. Zoom keeps the world point at the center of the current view fixed,
rather than zooming around the mouse pointer. Grid lines and ticks move together as the scale changes.
Labels adapt through steps such as `0.2`, `0.5`, `1`, `2`, `5`, and `10`.

You can customize the initial size and title:

```lisp
(mathbook:run :width 1280 :height 800 :title "My Mathbook")
```

If an older version is already stuck in SLY, use `M-x sly-interrupt` and select the debugger restart
"Return to SLY's top level", then reload the updated project.

## Dots

`dot` is a CLOS class with `:x`, `:y`, `:radius`, and `:color` initialization
arguments. Coordinates and radius are in pixels, with the origin at the top left,
x increasing rightward, and y increasing downward. Positions are rounded to the
nearest pixel when drawn. Defaults are `(0, 0)`, radius `2`, and `:black`.

Pass a list of dots to `run` to customize the canvas:

```lisp
(mathbook:run
 :dots (list (make-instance 'mathbook:dot
                           :x 200 :y 150 :radius 8 :color :blue)))
```

Use `(mathbook:run :plane nil :dots nil :input nil)` for a blank canvas. The `dot-x`, `dot-y`,
`dot-radius`, and `dot-color` accessors support `setf`. The `draw` generic function
draws a dot inside an active Raylib drawing frame; `run` calls it each frame.

## Lines

`line` subclasses `dot`. Its inherited `:x` and `:y` specify the starting point;
`:end-x` and `:end-y` specify the endpoint (defaulting to `(100, 0)`). It uses the
inherited color and draws a one-pixel-wide segment. The inherited radius is not
used by the line's specialized `draw` method.

```lisp
(mathbook:run
 :dots (list (make-instance 'mathbook:line
                           :x 100 :y 100 :end-x 400 :end-y 250 :color :blue)))
```

Both dots and lines can be passed in the same `:dots` list. The `line-end-x` and
`line-end-y` accessors support `setf`, as do the inherited dot accessors.

## Cartesian plane

`cartesian-plane` is a class; `axis` is a generic function with a method for that
class that draws its horizontal x-axis and vertical y-axis. The axes span the
plane's width and height, default to black, and are one pixel thick. Numbered
ticks are spaced 60 pixels apart at the default zoom: positive x goes right, positive y
goes up, and negative values go left and down. A single `0` marks the origin.
The `grid` method draws solid light gray lines through each nonzero tick:
vertical lines at x values and horizontal lines at y values. Three solid, lighter gray
lines between each pair of major lines divide every cell into a 4 × 4 grid of
16 smaller squares. The subdivisions scale
with the major grid while zooming. The black axes remain solid. Labels have white backgrounds
for readability; labels that would extend beyond the canvas are omitted.
The grid and axes are drawn behind any dots and lines supplied to `run`.

`run` creates a plane matching the window size by default. You can supply one:

```lisp
(mathbook:run
 :plane (make-instance 'mathbook:cartesian-plane
                       :width 1024 :height 768
                       :color :gray :zoom 1d0
                       :unit-spacing 60 :grid-color :lightgray))
```

The origin starts at the canvas center. The `plane-width`, `plane-height`,
and `plane-color` accessors support `setf`. `:unit-spacing` is the positive number
of pixels per world unit at zoom 1 and can be changed with `plane-unit-spacing`.
`:zoom` is a positive magnification factor, available through `plane-zoom`.
Wheel input changes magnification by a factor of 1.15 per notch, with limits of
`0.000001` to `1000000`. The tick interval is chosen from multiples of 1, 2, and 5
across powers of ten, and fractional labels omit unnecessary trailing zeroes.

`(mathbook:zoom plane amount)` applies a wheel movement programmatically; positive
values zoom in and negative values zoom out. Both axes use the same scale.
`(mathbook:pan plane delta-x delta-y)` moves the plane by canvas pixels in the
drag direction, independently of zoom. `plane-center-x` and `plane-center-y`
store the world coordinates at the center of the view, initially `(0, 0)`, and
support `setf`. Positive world y points upward. Axes and their labels disappear
when panned offscreen while the grid continues to fill the canvas.

`(mathbook:axis plane)` must be called inside an active drawing frame; `run`
handles this automatically.

`:grid-color` sets the grid color and can be changed with `plane-grid-color`.
When drawing manually, call `(mathbook:grid plane)` before `(mathbook:axis plane)`
inside the drawing frame.

Use `:plane nil` to hide the axes and grid. Dots and lines still use canvas pixel
coordinates and do not scale with the plane yet.

## Function plots

`real-function` represents a mathematical function independently of drawing.
Its required `:evaluator` accepts one real x value; `:name` is an optional label.
`evaluate-at` calls the evaluator and propagates its results and errors.
`function-name` and `function-evaluator` support `setf`.

`function-plot` references a `real-function` through `:function` and draws
`y=f(x)` in world coordinates. Pass plots to `run`:

```lisp
(mathbook:run
 :plots (list
         (make-instance 'mathbook:function-plot
                        :function (make-instance 'mathbook:real-function
                                                 :name "x²"
                                                 :evaluator (lambda (x) (* x x)))
                        :color :blue :thickness 2)))
```

Plots follow the plane when panning and zooming. They appear after the grid and
axes and before pixel-coordinate dots and lines. With `:plane nil`, plots are
not drawn. The initial scene has no plots unless you supply them.

Plot initialization arguments and corresponding `setf` accessors are:

| Argument | Accessor | Default |
| --- | --- | --- |
| `:function` | `plot-function` | Required |
| `:color` | `plot-color` | `:blue` |
| `:thickness` | `plot-thickness` | `2` pixels |
| `:visible-p` | `plot-visible-p` | `t` |
| `:x-min`, `:x-max` | `plot-x-min`, `plot-x-max` | `nil` (visible x range) |
| `:sample-spacing` | `plot-sample-spacing` | `8` pixels |
| `:tolerance` | `plot-tolerance` | `0.75d0` pixels |
| `:max-evaluations` | `plot-max-evaluations` | `8193` per resampling |

Domain bounds are inclusive world coordinates; `x-min` must not exceed `x-max`.
Thickness, sample spacing, and tolerance must be positive; the evaluation budget
must be an integer of at least 3. The sampler starts across the visible domain
and refines intervals using their midpoint error, up to 12 refinement levels.
Errors, complex values, NaNs, and infinities create gaps. Intervals that remain
unresolved at the refinement or evaluation limit are omitted. Segments are clipped
to the canvas before being sent to Raylib.

Discontinuity detection is approximate: finite sampling can miss narrow features,
oscillations, and some discontinuities. The evaluation budget limits the number
of calls, not the time spent inside an evaluator; use functions that return
promptly and avoid side effects.

`plot-segments` returns cached pixel segments `(x1 y1 x2 y2)` without drawing;
treat the returned list as read-only. Geometry updates when the evaluator,
domain, sampling settings, or plane view changes. After changing state captured
by an evaluator, or reloading code used by it, call `(invalidate-plot plot)`.
Changing the color, thickness, or visibility does not require resampling.

`world-to-screen` and `screen-to-world` return two values without rounding and
share the plane's pan and zoom transform. Positive world y points upward.
`(draw-on-plane plot plane)` renders a plot inside an active drawing frame.
These functions leave the existing one-argument `draw` interface intact.

In the persistent ARDD session, add a plot without opening another window:

```sh
./ardd --transport emacsclient eval - <<'LISP'
(push (make-instance 'function-plot
                     :function (make-instance 'real-function
                                              :name "sin(x)"
                                              :evaluator #'sin)
                     :color :red)
      (scene-plots *scene*))
LISP
```

## Footer input

The window reserves 88 pixels below the chart for a raygui group box containing
an editable `f(x) =` field. Click the field to edit; Enter or a click outside
finishes editing. The field stores text without parsing or plotting it yet.
Mouse wheel and drag input over the footer do not move the chart, and chart
content is clipped above the footer.

The footer and axis labels use installed Inter with smooth texture filtering.
If Inter is unavailable, Mathbook tries macOS San Francisco, Arial, and common
Linux sans-serif fonts before falling back to Raylib's built-in font. Set
`MATHBOOK_FONT` to a TrueType font file to prefer another font. Custom fonts are
loaded for each window and released before its graphics context closes.

`scene-input` holds a `function-input` object. `input-text` supports `setf`,
so the shared REPL can inspect or replace the text:

```lisp
(input-text (scene-input *scene*))
(setf (input-text (scene-input *scene*)) "sin(x)")
```

The native input buffer holds up to 4095 UTF-8 bytes. It is reused between frames
and freed when the window closes, while the scene retains its Lisp text for
reopening. `(mathbook:run :input nil)` hides the footer. To start with text, pass
`:input (make-instance 'mathbook:function-input :text "sin(x)")`.

Formula parsing is the next phase; the plotting API currently accepts Lisp evaluators.

## Tests

With Quicklisp loaded, run the following from the repository root:

```lisp
(require :asdf)
(asdf:load-asd (merge-pathnames #p"mathbook.asd" (uiop:getcwd)))
(ql:quickload "mathbook/tests")
(asdf:test-system "mathbook")
```

The Rove tests cover wheel direction, zoom limits, adaptive label sequences,
the centered origin, alignment between grid lines, ticks, and labels, and the
16-square cell subdivisions across zoom levels, panning, zoom after panning,
and mouse drag/release/focus behavior.
Drawing commands are captured so the tests can run without opening a window.
Function plot tests cover coordinate round trips, curve accuracy, clipping,
domain restrictions, poles between sample points, invalid values, evaluation
budgets, cache invalidation, and scene rendering. Run these in a separate Lisp
process from the live ARDD canvas because they temporarily replace drawing functions.
Footer tests cover layout, chart input isolation, edit state, and native buffer
cleanup during normal and failed window exits.

## Project layout

```text
mathbook.asd       Application and test system definitions
run                Launch the window in a standalone SBCL process
src/package.lisp   Shared Mathbook package, UIOP imports, and public exports
src/typography.lisp       Shared sans-serif font loading, drawing, and cleanup
src/dot.lisp       Dot class and drawing method
src/line.lisp      Line subclass and drawing method
src/cartesian-plane.lisp  Cartesian plane class and axis method
src/real-function.lisp    Mathematical function model and evaluation
src/function-plot.lisp    Adaptive sampling, clipping, caching, and rendering
src/function-input.lisp   Footer text entry and native buffer ownership
src/main.lisp      Canvas window loop
tests/main.lisp    Zoom, label, and drawing alignment tests
tests/function-plot.lisp  Function evaluation, sampling, and rendering tests
tests/function-input.lisp Footer layout, editing, and lifecycle tests
README.md         Project overview and development instructions
```

## License

A project license has not been selected yet.
