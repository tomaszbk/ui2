# Render scheduling

The custom renderer builds its initial element tree and then updates it when
application work invalidates the window. A static window reuses its retained tree.
Input, model actions, resize, worker deliveries and running
[motion](motion.md) request the work they need. A motion frame draws without
building; a frame whose motion events ran a handler builds again. Requests raised during a frame are kept for the next frame.

Call `request_refresh()` on the window after changing model data outside an
input, timer or motion event callback: `w.request_refresh()` where the window
is at hand, or `event.window.request_refresh()` from an event. Control setters such as `set_text` request a paint
and preserve other controls' current editing state.

Capture `w.dispatcher()` on the UI thread and pass the handle to workers.
Its `post(fn () { ... })` method queues model work on the UI thread and requests a
frame. The handle belongs to that window; after close, `post` returns `false`.

`w.render_stats()` reports callbacks, builds, draws, flushes and pending work.
On Metal, idle callbacks skip both builds and draws. GL, EGL and D3D present after
each platform callback, so idle callbacks repaint the retained tree, and so
does Metal on iOS.

The scheduler suspends painting while the window is iconified or suspended,
continues to deliver queued business work, and refreshes the surface on restore.
Close cancels queued work and visual timers.

## Acceptance fixture

Build and run the renderer acceptance fixture on macOS:

```sh
v -b c -cc clang run tests/render_scheduler --seconds 3
```

The fixture checks static reuse, worker delivery, request coalescing, a request
issued during a build, a layout transition's completion event and return to
idle. Add `--lifecycle`
to exercise real window minimize and restore on macOS, or `--interactive` to
inspect editing, scrolling and tooltips with counter output.
