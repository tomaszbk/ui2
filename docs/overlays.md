# Overlays

Custom desktop windows support Dialog, Popover, MenuOverlay, ContextMenu and
Tooltip. Each surface is a retained View owned by its declaration or component,
presented above the window content. Scrolling, clipping and transforms around
its owner do not clip or transform the surface. The current presented anchor
frame determines placement. Android and iOS reject overlays with a
diagnostic.

Run the compiled VML example:

```sh
v -b c run examples/overlays
```

## Controlled state

`open` comes from application or component state. Escape, outside presses,
menu selection, pointer departure and unavailable owners request dismissal
through `on_dismiss`. The handler changes the state to close the surface, or
leaves it open to veto the request. Outside presses are consumed even when
closing is vetoed; they cannot activate a background control.

```vml
Dialog(id: settings, width: 360, height: 240,
    open: app.settings_open, initial_focus: "name",
    on_dismiss: app.close_settings(event.dismiss_reason)) {
    Column(gap: 12) {
        TextInput(id: name, text: "España, café y ñ", width: 300, height: 32)
        Button(text: "Done", on_click: app.save(), width: 100, height: 32)
    }
}
```

`event` is a typed `ElementEvent`. Its `.dismiss` kind carries
`dismiss_reason`: `escape`, `outside_pointer`, `selection`,
`owner_unavailable` or `pointer_leave`. Set `dismiss_on_escape: false` or
`dismiss_on_outside: false` to suppress those requests. Ordinary button and
control callbacks keep their normal typed events.

Closing changes visibility without removing the declaration. Reopening keeps
the same component, local edit buffer, selection and scroll state. Unchanged
declared text preserves edits; bindings and `set_text` keep their ordinary
contracts. Removing the declaration disposes its owner normally, after any
configured exit motion completes.

## Placement and ownership

An overlay needs a unique stable id. Dialog centers in the logical window
content viewport. Other kinds require an `anchor` id or a typed `point`.
The frame's width and height specify the surface size. Placement flips to the
opposite side when that fits, then clamps within `margin` (default 8 logical
units). Oversized surfaces shrink to the available area and reflow their
children. `gap` defaults to 6 logical units.

```vml
Popover(id: details, anchor: "details_button", placement: bottom_end,
    width: 240, height: 160, open: app.details_open,
    on_dismiss: app.hide_details()) {
    Label(text: "Retained content", width: 200, height: 30)
}
```

Placements are `bottom_start`, `bottom`, `bottom_end`, `top_start`, `top`,
`top_end`, `right_start`, `right`, `right_end`, `left_start`, `left`, `left_end`.
Coordinates stay fractional logical units; pointer points use the window
content viewport below the application menu bar.

An optional `owner` id adds an availability dependency. Removing, hiding or
disabling an owner or anchor hides the surface from input and requests
`owner_unavailable` once. An anchor clipped completely out of its scroll
viewport is unavailable. A surface anchored inside another overlay inherits
its logical owner and focus containment, even if declared before that owner.
Cycles between overlay owners/anchors are diagnosed. A Dialog reserves
`<id>__backdrop` for its backdrop; declarations cannot reuse that id.

Literal `anchor`, `owner` and `initial_focus` names resolve within a compiled
component's namespace. Dynamic strings and ids inside an opaque `OverlayConfig`
are already resolved ids. V application code can use
`component.control_id("local_id")` to obtain the same id; an empty id stays empty.
When a literal names another component instance, declare that instance first
so its exported root id is available. A forward component alias is diagnosed;
forward names of ordinary local controls remain valid.

## Focus and input

Dialog makes background controls inert while preserving their appearance.
It enters a focus scope, selects `initial_focus` or the first eligible child,
and traps Tab, Shift-Tab and directional navigation. Closing restores the
previous target, or an eligible target in the surviving outer scope if the
saved target disappeared. Nested dialogs and menus restore each enclosing
destination in order. An empty Dialog can receive programmatic focus itself.

MenuOverlay and ContextMenu use the same scope behavior. Up/Down wrap between
items; Home/End select the first/last item. Enter and Space retain semantic
button activation. Selection requests dismissal after the action callback.
Escape and Tab request dismissal. `MenuOverlay` is distinct from the existing
application menu declaration `Menu`.

Popover preserves existing focus by default. Supplying `initial_focus` opts
it into a focus scope with restoration. Tooltip never receives input or focus.

ContextMenu requests `.open` through `on_open` on a secondary press on its
anchor. Read `event.x`/`event.y`, store an `OverlayPoint`, and set `open`.
Another secondary press on that owner can request a new point while already
open. Secondary presses do not activate the anchor's primary click callback.

Tooltip requests opening after `tooltip_delay` seconds (default 0.5) of a
stationary pointer over its anchor, or immediately when its anchor receives
keyboard focus. Pointer departure requests closing. Pending deadlines are
retired with their owner and do not keep the scheduler awake after completion.
The same controlled state and veto behavior applies to open requests.

## V API and motion

```v oksyntax
surface := ui2.with_overlay(
	ui2.view('confirmation', ui2.rect(0, 0, 320, 180), ui2.BoxStyle{
		bg:     0xffffff
		radius: 12
	}, children),
	ui2.OverlayConfig{
		kind:          .dialog
		open:          confirming
		initial_focus: 'confirm'
		on_dismiss:    dismiss
	},
)!
```

`View(overlay: app.config)` accepts the same typed configuration in compiled
VML. Invalid sizes, coordinates, delays and opacity produce diagnostics.
`overlay_frame` exposes pure placement for independent geometry fixtures.

Attach ordinary `motion: app.surface_motion()` in VML or `with_motion` in V.
The surface and Dialog backdrop share sampled opacity. Closing disables input
and restores focus immediately while an exit continues painting. Reentry can
reverse that exit without losing local edits. Reduced motion, controlled
clocks and component cleanup use the existing [motion contract](motion.md).
Stable overlay projections reuse retained geometry and layout snapshots.