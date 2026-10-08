# Drag and drop in custom windows

Attach a `DragSource` and a `DropTarget` to `View` or `Image` elements with
`with_drag_source` / `with_drop_target`. Both require an `on_event` callback.
Native profiles diagnose these declarations as unsupported. This API moves data
inside a UI2 window. Existing external window `DropEvent` handlers are independent.

```v
struct Card {
    name string
}
fn (card Card) drag_type() string { return 'card' }

fn accept_card(offer ui2.DragOffer) ui2.DragOperation {
    if offer.payload is Card { return .move }
    return .none
}

source := ui2.with_drag_source(ui2.with_event(card_view, handle_event), ui2.DragSource{
    payload: Card{'Niño / café'}
    allowed: [.move, .copy]
    preview: ui2.DragPreview{text: 'Niño / café', width: 90, height: 38}
})
target := ui2.with_drop_target(ui2.with_event(destination_view, handle_event),
    ui2.DropTarget{accept: accept_card})
```

Implement `DragPayload` on application value types; narrow the interface with a
V type check in the acceptance query and drop handler. `DragText` is provided for
text values. Acceptance must be a pure query returning `.none`, `.copy`, `.move`
or `.link`. The chosen operation must be in the source's allowed operations,
including its current declaration. UI2 reports the operation; the application's
`.drop` handler performs the data mutation. A drag captures its payload, allowed
operations, callback and preview at pointer-down; unrelated rebuilds do not
replace that data. Use immutable payload values or application-owned references;
UI2 retains the payload handle and does not deep-clone arbitrary objects.
The captured operation list is copied, so changes to the application's original
array cannot add operations to an ongoing gesture.
Callbacks, `cancel_drag()` and `drag_active()` use the UI thread. Background
tasks must post actions with `UiDispatcher.post`.

The default threshold is six **window-logical** units; movement must exceed it.
A short press keeps normal tap/button behavior. Crossing the threshold emits
`.drag_start` on the source and suppresses tap, swipe, long press and residual
activation for the entire gesture. Raw `clickable` sources, `draggable`, long press and swipe cannot
share a drag source/target declaration. A drag source owns content dragging over
Scroll; wheel scrolling remains available. Scrollbar capture wins before source
capture. Existing sliders, scrollbars and raw `draggable` gestures retain their
own input path.

Targets follow current shared hit geometry and clipping in reverse paint order.
The top ordinary interactive control blocks targets below it. Preview never
participates in hit testing. A declared target receives `.drag_enter`, then
`.drag_over` on each pointer update, even when rejected (`operation: .none`).
Changing destinations emits `.drag_leave` before entering the next destination.
Moving, clipping, hiding, disabling or removing a target also updates a stationary
drag after the next render. Stable acceptance/geometry does not emit repeated
over events on idle redraws. A target removed during `over` cannot receive drop.

Release reevaluates acceptance and current ownership/geometry. A valid release
emits exactly one `.drop`, `.drag_leave`, then `.drag_end` on the source. An
invalid release emits leave and `.drag_cancel` with `.invalid_target`.
`cancel_drag()`, Escape, focus loss, touch cancellation, suspension and window
close release capture; an active drag receives one cancel event. Cancellation
before the threshold has no drag lifecycle events. Removing/hiding/disabling
the source cancels with `.source_removed`. Repeated release/cancel calls are
safe. Capture is cleared before terminal callbacks, so handlers may remove the
source or target. Callbacks during start/enter/over may cancel synchronously.

Give persistent sources and targets an `id` or stable sibling `key`. IDs remain
stable through reorder; anonymous elements use the existing reconciliation path.
Mount generations distinguish removal followed by remount in a subsequent
render. A captured source scrolled out of view stays mounted. UI2 does not modify
focus, editor selection, UTF-8 draft text, composition or scroll offsets to drag.
An application that deliberately removes an editor still follows normal teardown.

`ElementEvent.drag` contains `DragEvent { offer, operation, reason }`. Existing
`ElementEvent.x/y` semantics are preserved: composition coordinates after inverse
mapping, **not coordinates relative to the element's top-left**. `DragOffer`
names its spaces explicitly: `window_x/y`, `source_x/y` and `target_x/y`. Visible
source and target positions use current rendered transforms; a culled source uses
its last captured geometry. `source_id` / `target_id` identify the participants.
There is no target on invalid background; its target coordinates are window
coordinates with an empty target id.

Preview dimensions and offset use source-composition units and the source
transform at drag start. Its origin follows the window pointer, escaping the
source's Scroll/ScaledContent clip; the preview clips to the window. DPI remains
separate and DrawContext projects/presents it once. Text and optional `image_path`
use the normal drawing and per-context image cache; a preview has no separate
image loader. Resources remain retained while a preview uses them. Drag requests
on-demand updates only while input, ownership or model state changes; it does
not create an animation loop or recurring timer.

Run `v -d ui2_custom_rendering run examples/drag_drop`. Edit the text field, drag
the blue card to green/red/background, and verify the counters and preserved
draft. Set `UI2_DRAG_AUDIT=1` to print a read-only 30-second scheduler comparison
following each terminal event. Metal can skip idle draws; GL still presents the
retained tree. Callback counts are reported separately from builds/draws.

Current shared geometry supports scale/translation and ScaledContent. Drag-drop
uses the shared hit/transform/cache helpers. General affine rotation, exact
rotated clipping, vector shape membership and new image resource combinations
require independent tests with the integrated renderer APIs before they can be
accepted.

## Renderer integration fixture

On macOS gg/Sokol with Metal (without `ui2_embedder`), run the opt-in fixture
on a quiet desktop:

```sh
v -d ui2_custom_rendering -d ui2_drag_runtime_probe test ui/drag_drop_runtime_immediate_test.v
```

It drives gg pointer events through the existing handler on the UI thread, checks
one drop and one Escape cancellation, preserves a live UTF-8 draft/selection/IME
composition through redraws, verifies that content and preview share one cached
image, and measures two 30-second idle intervals. Its input gate excludes unrelated
desktop pointer/key/focus events while preserving real surface/lifecycle events.
This is renderer integration evidence; an OS pointer drag remains a separate interaction check. Resize/DPI or
surface activity legitimately invalidates the window during measurement.

For preview raster evidence, compile the fixture with `-d gg_record` and
`-d darwin_sokol_glcore33`, then run with `UI2_DRAG_CAPTURE=1`,
`VGG_SCREENSHOT_OUTPUT=file`, `VGG_SCREENSHOT_FOLDER=<directory>`,
`VGG_SCREENSHOT_FRAMES=40,140` and `VGG_STOP_AT_FRAME=160`. The first image shows
the projected preview; the second shows its clip at the window edge. GL recording
is a presentation path and does not serve as a zero-draw idle measurement.
