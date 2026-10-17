# Owned embedder: macOS / Metal

The embedder is a macOS host variant of the renderer (see `ui/platform.v`):
instead of drawing in a sokol_app window, the same renderer draws into AppKit
windows and Metal surfaces that ui2 owns, with its own event loop. That gives
it several windows, NSTextInputClient text input and an event loop that sleeps
while idle. Compile with `-d ui2_embedder`; it requires macOS/Metal, and every
other OS keeps its sokol window.

```sh
v -d ui2_embedder run examples/text_input
```

`App` and the VML runners use the owned host under this define. The
host builds and paints on demand; no render policy configuration is required.
It installs the same native menu bar and status item as the sokol host, plus a
standard Edit menu whose Cut, Copy, Paste and Select All rows its text view
answers.

## Window ownership and scheduling

```v
mut app := ui2.new_app()
mut first := app.new_window(title: 'First', width: 600, height: 400, build: build_first)!
mut second := app.new_window(title: 'Second', width: 600, height: 400, build: build_second)!
dispatcher := first.dispatcher()
// Pass dispatcher to a worker; apply its result inside dispatcher.post(...).
app.run()
```

Each window owns its coordinator, declared tree, editor/focus/selection state,
scroll positions, input capture, menus, tooltips, motion, images and font
atlas. Element ids may be identical in different windows. Windows share the Metal
device; the Sokol renderer resources shut down after the final drawing context closes.

There is no active window. A builder receives its window (`fn (mut w
ui2.Window) ui2.Element`), and element, key and drop events carry the window
they happened in as `event.window`. `bounds`, `text`, `focus`,
`request_refresh` and the other window functions are methods of the window
they act on, and motion handles wake the window that shows their element. On
the main thread any window can be called directly, from any window's
callbacks. Workers use the captured dispatcher instead. A closed dispatcher
rejects posts and never redirects them to a replacement window.

`window.quit()` closes that window. `app.run()` returns after all its windows
close. A close inside a callback cancels
pending work immediately and defers renderer resource destruction until its
outer callback returns. `native_handle()` returns a borrowed NSWindow for
main-thread platform integrations while the window remains open.

The host waits for events or the earliest visual deadline. An idle window has
no periodic pump callback. Worker messages post one coalesced native wake event.
Tooltips and long presses use deadlines; running motion uses the screen's
reported presentation cadence and stop requesting frames when they finish.
The coordinator preserves invalidations issued during a frame. An unavailable Metal drawable is retried
after a bounded wait while business messages continue to be delivered.

Minimized or occluded windows suspend visual work, retain pending model updates
and redraw a complete surface when restored. Business callbacks can execute
while visual work is suspended. This is a scheduling contract, not a promise
that the operating system or application has zero CPU use or energy cost.

## Text input

The AppKit view implements
[NSTextInputClient](https://developer.apple.com/documentation/appkit/nstextinputclient):
marked text, selection, replacement, committed text and candidate coordinates
cross the platform boundary separately. Native ranges use UTF-16, whereas the
existing editor uses rune offsets. The adapter translates between them,
including supplementary characters.

Preedit is staged without changing `text(id)` or notifying VML bindings. It is
visible and underlined in text fields and text areas. A commit applies the
staged transaction and fires the existing field-change event. An unrelated
rebuild preserves composition; explicit text replacement, focus retargeting
or unmount removes obsolete composition. The native client receives the
displayed document, actual marked range, selection and caret rectangle after
updates. Input methods handle composing keys before ordinary editing commands.

This keeps platform input separate from committed application state. It does
not add shaping, bidi, color emoji or new typography units. Those remain work
for the text phase. The renderer continues using gg's drawing primitives behind
the UI2 `DrawContext` adapter, with Sokol passes supplied by the owned surface;
it never runs the `sokol_app` loop on this path.

## Verification

```sh
make check-backends
make test-embedder
v -d ui2_embedder -o /tmp/ui2-embedder tests/embedder
/tmp/ui2-embedder --seconds 30
/tmp/ui2-embedder --interactive --japanese-ime
xcrun clang -std=c11 -Wall -Wextra -Werror -fobjc-arc \
  tests/embedder_macos/host_contract.m -framework Cocoa -framework Metal \
  -framework QuartzCore -o /tmp/ui2-embedder-host-test
/tmp/ui2-embedder-host-test
/tmp/ui2-embedder-host-test --idle-ms 30000
```

The native harness defaults to a 200 ms idle interval; `--idle-ms N` selects
a longer sample. Failed harness checks report the condition, request window
cleanup on the main thread and exit with status 1. Worker failures wait up to
500 ms for cleanup. Runtime assertions and exceptions retain their normal
crash reports.

GPU/native execution requires a normal macOS GUI session. Keep the default GC.
The two-window acceptance checks native host pump counters separately from
renderer callbacks, builds and draws. It also checks target-specific worker
wakes, equal-id editors and their selections, scroll preservation, tooltip
deadlines, layout motion completion, UTF-16 composition through the native client,
minimize/restore and independent close. A short `--seconds 2` run is useful for
iteration; the idle acceptance interval is thirty seconds.

The native event counter records input, geometry, lifecycle and text deliveries;
worker wakeups and deadline pumps do not increment it. The fixture may restart
an idle sample when native events interrupted it, but fails periodic pump work
without such events. Each completed sample must still have zero new pumps,
renderer callbacks, builds and draws.

The optional Japanese session selects an already available Hiragana source
for the fixture's input context and restores the previous source on exit.
The fixture uses an available system TrueType font with Japanese coverage.
Type `nihon`, Space and Return to inspect actual preedit, candidates and commit.
The synthetic NSTextInputClient checks exercise the protocol and cannot alone
establish that a real input method works.

## Observed verification (2026-09-30)

On macOS/Metal with the default GC:

- All backend type checks and the eight focused embedder test files passed.
  Other platforms were type-checked only and still use their existing hosts.
- The two-window acceptance completed with a two-second uninterrupted idle
  sample: zero native events, host callbacks, renderer callbacks, builds and
  draws in both windows. Target worker wake, animation isolation, tooltip,
  native composition, readonly/disabled changes, minimize/restore, independent
  close and dispatcher-only GC lifetime checks passed.
- Four actual Metal windows rendered and closed; a subsequent window recreated
  the renderer resources and rendered successfully.
- The actual Japanese input source produced visible underlined preedit and
  committed text in the model. The final native preedit was empty and the
  previous ABC source was restored. Candidate geometry passed the native client
  checks; the window capture excludes the system candidate panel, so its visual
  placement was not established by that capture.
- A separate thirty-second native-host wait with two hidden windows passed:
  each host pumped once for initialization, remained asleep until the worker
  wake, and waking the first did not pump the second. This checks the host loop
  independently of renderer counters.
- The thirty-second visible-window sample was interrupted by desktop pointer,
  focus and occlusion events. It did not pass; it must be repeated in a quiet GUI
  session with both windows visible.
- `make test` reported 131 passed, 12 failed and 2 skipped. Failures involve
  existing native/custom test guards, compiler failures, slider syntax, editor
  word navigation, VML equality and example assertions; it is not an all-pass
  result. `make examples` and `make examples-custom` stop in the existing build
  script's array-slice syntax. Direct compilation of text_input, users and
  dropdown with the embedder, plus legacy custom text_input, passed.

## Window context

Every window is an explicit context: a `Window` owns updates, dispatch,
metrics and resources, and the `App` owns the collection of windows.
`run_window` remains a convenience entry point that opens one window and runs
it. The independent view/metrics boundary in modern embedders is also
illustrated by
[FlutterWindowsView](https://api.flutter.dev/windows-embedder/classflutter_1_1_flutter_windows_view.html).
The host's native callbacks name their window through their opaque userData,
so no window state is swapped in or out around a callback.

Compiled VML shares the same window ownership. Its callbacks retain typed
application and component contexts; component scopes own signals and cleanup.
The convenience `run_compiled_vml` runner owns one application window.
