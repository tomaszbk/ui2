# Keyboard focus and semantic hooks

Desktop native and custom windows share sequential navigation, explicit focus
scopes, button activation and geometric directional navigation. Run
`v run examples/focus_navigation` for native controls, or
`v -d ui2_custom_rendering run examples/focus_navigation` for custom rendering.

A keyboard target needs a unique `Element.id`. Buttons, composed views with
`button_behavior`, checkboxes, switches, toggles, sliders, dropdowns and text
inputs are focusable automatically. A clickable View does not become a button.
Set `focus_policy: .focusable` to opt another element into focus, or
`focus_policy: .unfocusable` to exclude it. Native Views accept explicit focus;
using a semantic Button remains the appropriate choice for an action.

`tab_index: 0` follows declaration order. Positive indices come first, sorted
ascending with declaration order for ties. Negative indices exclude a target
from both sequential and directional traversal while allowing `focus(id)` and
semantic focus actions.
Hidden or disabled elements, including descendants of hidden or disabled
ancestors, cannot receive focus. Clipping and Scroll culling do not unmount a
control: traversal includes these destinations and reveals them inside out
through their Scroll ancestors, including anonymous Scroll containers.

```v
ui.focus('name')
ui.focus_next()       // Tab
ui.focus_previous()   // Shift-Tab
ui.focus_direction(.right)
println(ui.focused_id())
```

Traversal wraps within the window. Arrow keys move between controls using their
projected window geometry. Candidates must lie in the requested direction;
controls overlapping the source's perpendicular span win over diagonal ones.
Within that group the score is forward distance plus squared perpendicular
distance divided by forward distance. Exact ties use the same stable traversal
order. Text inputs retain their editing arrows; dropdowns and sliders retain
control-specific input. `focus_direction` explicitly requests navigation from
any focusable control. Geometry uses `ContentTransform`, shared with rendering,
so ScaledContent and scroll offsets do not introduce another coordinate system.

Declare a scope on a container, then enter and leave it explicitly:

```v
panel := ui.Element{
    kind: .view
    id: 'settings'
    focus_scope: true
    children: [/* controls */]
}
// After mounting panel:
ui.enter_focus_scope('settings')
ui.leave_focus_scope()
```

Entering focuses the first eligible child and saves the previous destination.
Nested scopes must belong to the current scope. Tab and automatic directional
navigation stay inside the active scope. Leaving restores the saved target,
or the first eligible target in the enclosing scope/window if it was removed
or became unavailable. Removing, hiding or disabling an active scope unwinds
it and restores the enclosing destination. Empty scopes cannot be entered.
`active_focus_scope()` returns the active id, or an empty string. Scopes provide
focus containment; they are not a Dialog/overlay API. Bind Escape to
`leave_focus_scope()` if your screen needs that behavior.

Enter and Space activate semantic buttons and composed `button_behavior` Views
once per physical press; autorepeated activation events are consumed. Checkboxes,
toggles and switches use their existing change actions. Pointer activation keeps
its captured callback and release eligibility checks. Tab/arrow repetition moves
once per delivered event. Windows consumes shared Tab handling before the native
control fallback; it has one traversal implementation.

Application key callbacks run before focus handling and may call `consume_key()`
(or `consume_text_key()` for text-area commands). Open custom menus/dropdowns
handle their keys first. Editor Enter/Space and arrows keep their existing
editing/submit meanings, and the existing native IME command paths remain in use.

Changing focus through these APIs does not move an existing editor selection to
its end. Unrelated declarations keep current focus, local text, selection and
scroll. Unchanged declared text preserves edits; a changed declaration or
`set_text(id, value)` replaces the edit buffer intentionally. Custom `set_text`
keeps its existing selection clamping behavior. Custom IME composition stays attached
to its editor across unrelated updates and is discarded when that editor loses
focus, is removed, hidden, disabled, or becomes readonly. Native controls keep
their platform IME behavior. This does not add
advanced grapheme/bidi editing.

`semantic_tree()` returns portable `SemanticNode` snapshots with id, tree path,
parent path, role, name, label, current value, projected frame, state and actions.
`semantic_node(id)` queries one node. `accessibility_role`,
`accessibility_name`, `accessibility_label` and `accessibility_value` provide
explicit metadata; built-in controls supply sensible role/name defaults. Input
names default to their label or placeholder. Secure inputs expose neither their
text nor value. Snapshots include effective hidden/disabled state, focus,
checked/selected state, readonly, secure and custom dropdown expansion.

```v
if node := ui.semantic_node('save') {
    println('${node.role}: ${node.name}')
}
ui.perform_semantic_action('save', .activate)
ui.perform_semantic_action('name', .focus)
ui.perform_semantic_action('volume', .increment)
```

Actions are checked against the current declaration, ancestor availability and
scope before dispatch. They use the same live control state and callbacks as
input. Semantic metadata updates with reconciliation and snapshots do not
require an extra paint. These hooks do **not** establish a verified OS
accessibility bridge. Existing native controls and press bridges are preserved;
VoiceOver/UIA/AT-SPI support is not newly claimed.

macOS native and custom keyboard behavior is exercised by the example and
backend fixtures. Windows and Linux backend checks are distinct from runtime
acceptance on those operating systems. UIKit keeps its existing responder/IME
bridges and exposes the shared programmatic hooks where its controls accept
first responder; this change does not introduce a mobile hardware-key host.
UIKit dropdown activation uses the public `UIControl.performPrimaryAction`
API (iOS 17.4 or later) to present its native menu. On systems without that API,
the dropdown snapshot omits `.activate` and `perform_semantic_action` returns
`false` without a change event. Opening the menu does not change its value;
choosing a native menu command commits the title and emits the optional callback.
Stateful UIKit semantic actions commit once even without a handler and respect
toggle groups, while real pointer releases retain their captured callbacks.
