# Linux event and deadline wait

The default Linux custom renderer uses the pinned Sokol X11 host and GLX.
UI2 blocks on the X11 connection and a per-window `eventfd` until input, a worker
result or the coordinator's next monotonic visual deadline. XWayland can use
this X11 path. Native Wayland and a new SDL3 host are outside this implementation;
a host without an X11 display fails explicitly.

```v
ui2.run_window('Idle wait', 520, 220, build)
```

Run `examples/idle_wait` for a stationary-pointer tooltip, worker delivery and an
editable English/Spanish draft. The worker captures `ui_dispatcher()` on the UI
thread and calls `dispatcher.post(callback)`. Only that callback mutates the
model, on the UI thread. Posts coalesce, a request during a flush survives for
the next flush, and a closed dispatcher rejects late work. `dispatcher.stats()`
is synchronized and can be read from a worker without waking the window.

The existing Sokol host owns input, clipboard, resize, minimize/restore and GPU
resources. The wait does not consume X events or change text/editing semantics.
It runs at the start of the UI2 callback, after the previous frame was presented.
An X event can therefore cause an additional retained repaint before Sokol
dispatches it on its next iteration. Every returned visible GL callback still
paints the complete image before Sokol swaps buffers. UI2 does not reuse a
discarded backbuffer. Exposure repaints the retained tree; resize, DPI changes and
restoration request a complete build and paint. Context loss/recreation remains
the existing Sokol host contract; this change does not add context recovery.
Closing releases the context's cached images and drops their ids, so a new run
loads textures on its new device rather than retaining ids from the closed one.

An idle callback remains blocked instead of returning at every refresh interval.
No swap occurs while it waits. Once stable, a window without active timers or
animations can have zero additional builds, draws and loop callback entries.
This claim must be established by measurement on the actual host. It does not
change GL's `presentation_required` flag. During animation the coordinator uses
the last usable Sokol presentation interval; timing samples spanning long idle
waits are excluded. Hidden windows suppress visual work while still delivering
business callbacks. The next restore repaints completely.

## Measurement

`RenderStats` separates work from host activity:

| Field | Meaning |
| --- | --- |
| `loop_callbacks` | UI2 frame callback entries, counted before any wait |
| `callbacks` | Scheduler `begin_frame` attempts after waiting and delivering tasks |
| `waits` | Completed Linux waits, including interrupted waits and buffered X events |
| `event_wakeups` | Waits observing X events; events remain owned by Sokol |
| `worker_wakeups` | Waits observing `eventfd`; several posts may share one wake |
| `deadline_wakeups` | Waits that timed out, followed by a check of the absolute deadline |
| `interrupted_waits` | Waits interrupted by a signal; deadline is recomputed |
| `builds`, `draws`, `flushes` | Declarative construction, complete paints, completed flushes |

An event and worker can be observed by the same wait, so wake counters are not
necessarily disjoint. Reading counters does not measure CPU or OS-wide wakeups.
A blocked wait has entered but has not incremented `waits` yet. The surrounding
Sokol loop may also perform its own short presentation pacing wait while active.

Compile `tests/render_scheduler` and run `--seconds 30` on Linux. It observes the
stable window from a worker without posting, waits for its first complete paint
and settling, reports separate activity deltas,
and measures process user+system CPU for that interval with `getrusage`. It then
checks worker delivery without input, coalescing, invalidation inside a build,
animation completion and return to idle, followed by normal quit/teardown.
Use `--interactive` for tooltip, selection, scrolling, pointer capture and
resize/restore checks. Run deterministic Linux wait fixtures with
`v test ui/idle_wait_linux_test.v`. Backend typechecks and interrupted screenshots
are separate evidence; neither establishes idle or normal teardown.

With the pinned Docker runner and Xvfb, compile the fixture to `/outputs` and
run the platform script before the static measurement:

```sh
v -o /outputs/acceptance tests/render_scheduler
python3 tests/render_scheduler/linux_runtime.py /outputs/acceptance /outputs
/outputs/acceptance --seconds 30
v test ui/idle_wait_linux_test.v
```

The script uses libX11, xdotool, a persistent English/Spanish keyboard mapping
and the runner's stdlib PNG capture helper at `/runner/x11_capture.py`. It checks
actual X11 input and UI-thread state snapshots, then normal quit and a new run
with a recreated GL context. Each captured image is checked for black pixels
inside the window and the four colors of an independently defined texture;
captures can also be reviewed separately. Minimize/restore is exercised
through ICCCM `WM_STATE` and actual unmap/map because Xvfb has no window manager.
This does not represent a compositor or sudden GPU context-loss test.

Container execution should report compiler/vlib pin, architecture, X server,
GPU renderer, GC mode and resource limits. Xvfb/llvmpipe verifies software GL
behavior, not a physical GPU, compositor energy usage, native Wayland, monitor
DPI changes or genuine GPU context loss. Repeat runtime acceptance after any
compiler/vlib pin change using a rebuilt, matching compiler layer.
