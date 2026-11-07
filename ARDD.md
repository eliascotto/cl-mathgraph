# Agentic REPL Driven Development

ARDD lets you and an agent develop Mathbook against **one persistent SBCL
process**. You use Emacs SLY; the agent submits evaluations through your Emacs.
Both can inspect and change the same objects without restarting the application.
The default transport uses project files, so the agent needs no socket access.

## Start once

Requires the normal Mathbook dependencies, threaded SBCL, Emacs with SLY,
and Python 3. Use the same SLY checkout that Emacs loads.
In Emacs, `M-: (locate-library "sly")` shows its location.

1. From the project directory, start the standalone process:

   ```sh
   ./dev-repl /absolute/path/to/sly
   ```

   Pass the directory containing `sly.el`, not its `slynk` subdirectory.
   Alternatively set `SLY_DIR`. The launcher opens the canvas and starts Slynk
   on `127.0.0.1:4005`. `ARDD_PORT=4006` selects another port;
   `ARDD_NO_WINDOW=1` starts without a canvas. Compiled files go in `.ardd-cache/`.

2. In Emacs, use `M-x sly-connect`, host `127.0.0.1`, port `4005`.
   Use this instead of `M-x sly`, which starts another Lisp process.

3. Load this project's `dev/ardd.el` with `M-x load-file`.

4. In the connected SLY REPL buffer, run `M-x mathbook-ardd-use-connection`.
   This pins the agent to that connection and opens `*Mathbook ARDD*`.
   Emacs also starts watching `.ardd/` for agent requests.

## Work together

The agent uses these commands from the project directory:

```sh
./ardd status
./ardd eval '(+ 2 3)'
./ardd load src/dot.lisp
```

For longer expressions, send a UTF-8 file or a heredoc through stdin:

```sh
./ardd eval - <<'LISP'
(push (make-instance 'dot :x 200 :y 150 :radius 8 :color :blue)
      (scene-dots *scene*))
(length (scene-dots *scene*))
LISP
```

`*Mathbook ARDD*` records each submitted expression, its output, all returned
values, and errors. The command returns that same result to the agent; failures
produce a nonzero exit status. Requests and replies travel through ignored files
in `.ardd/`, which Emacs checks every 0.1 seconds. No Emacs server is required.
`M-x mathbook-ardd-stop-mailbox` stops accepting file requests.

Alternatively, where local sockets are permitted, start `M-x server-start` and
use `./ardd --transport emacsclient eval '(+ 2 3)'`. Add `--socket-name NAME` for
a named Emacs server (or set `ARDD_EMACS_SOCKET`). `EMACSCLIENT` can specify its
executable path. This transport prints results as quoted Emacs strings.

You can use `M-x mathbook-ardd-eval` to evaluate through this same path and
transcript. Ordinary SLY evaluation, inspection, and `C-c C-c` still work, but
their results stay in SLY's usual buffers. For scene changes from the SLY REPL,
serialize them on the main thread:

```lisp
(mathbook-dev:on-main-thread
 (lambda () (setf (mathbook:dot-radius
                  (first (mathbook:scene-dots mathbook:*scene*)))
                 14)))
```

Agent expressions default to the `MATHBOOK` package. Save definitions in source
files and reload them with `./ardd load ...`; definitions created only in the
REPL disappear when Lisp exits. Agree on who is editing a particular file.

## What stays live

`mathbook:*scene*` holds the plane, dots, function plots, and footer input. Change them with
`scene-plane`, `scene-dots`, `scene-plots`, `scene-input`, and their existing accessors.
`(input-text (scene-input *scene*))` reads the footer text and supports `setf`.
The main thread processes queued
evaluations **between frames**, then calls `mathbook:run-frame`. Reloading drawing
methods or that function affects subsequent frames. Changing a macro requires
recompiling its callers; redefining an already executing loop does not replace it.

```sh
./ardd eval '(mathbook-dev:close-window)'
./ardd eval '(mathbook-dev:open-window)'
./ardd eval '(mathbook-dev:stop)'
```

Closing the window or pressing Escape keeps Lisp, SLY, and the scene alive.
Reopening reuses the scene. `stop` exits the development process. A frame error
is reported in the launch terminal and `mathbook-dev:*last-frame-error*`; the
queue stays available so you can fix and reload code. `status` includes the last
recorded frame error. Ordinary evaluation errors return to the shared transcript.

Function plots cache their sampled geometry. After reloading sampling code or
code used by an evaluator, invalidate the live plots to resample the next frame:

```sh
./ardd eval '(mapc (function invalidate-plot) (scene-plots *scene*))'
```

See [Function plots](README.md#function-plots) for the class API and a live example.

Keep evaluations finite: a long evaluation pauses rendering. The queue cancels
requests that have not started within ten seconds; it does not forcibly terminate
running code. The CLI waits 30 seconds for a reply (`--timeout SECONDS` changes
this). A CLI timeout cancels an unclaimed file request; if Emacs already claimed
it, the command reports that it may still execute. Cancelling an Emacs command or
losing a connection does not undo an evaluation, so inspect the state before
retrying a command that changes it.

Do not call `mathbook:run` from SLY on macOS. The launcher owns the main thread
required by Raylib; use `open-window` instead. Use the shared evaluation path for
scene mutations and graphics resources, rather than changing them concurrently
from worker threads. Draw calls themselves still belong inside drawing frames.

Occasionally restart and run the tests to check that saved source reproduces the
working state. The normal `./run` launcher remains available without SLY.

## Verify

```lisp
(asdf:test-system "mathbook")
(asdf:test-system "mathbook/dev")
```

Run tests in a separate fresh SBCL process: some tests temporarily replace drawing
functions. To check the Emacs bridge (substitute your SLY path):

```sh
emacs -Q --batch -L /path/to/sly -l dev/ardd.el -l tests/ardd.el \
  -f ert-run-tests-batch-and-exit
```

SLY setup follows its [standalone server documentation](https://joaotavora.github.io/sly/#Setting-up-the-Lisp-image).
