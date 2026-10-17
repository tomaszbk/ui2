# Keyboard focus and semantic hooks

Desktop windows have sequential navigation, explicit focus scopes, button
activation and geometric directional navigation. Run
`v run examples/focus_navigation` to try them.

A keyboard target needs a unique `Element.id`. Buttons, composed views with
`button_behavior`, checkboxes, switches, toggles, sliders, dropdowns and text
inputs are focusable automatically. A clickable View does not become a button.
Set `focus_policy: .focusable` to opt another element into focus, or
`focus_policy: .unfocusable` to exclude it. Views accept explicit focus;
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
focus containment. [Overlays](overlays.md) manage these scopes automatically
for Dialog, MenuOverlay and ContextMenu, including initial focus and restoration.
A Popover with explicit initial focus also enters its own scope.

Enter and Space activate semantic buttons and composed `button_behavior` Views
once per physical press; autorepeated activation events are consumed. Checkboxes,
toggles and switches use their existing change actions. Pointer activation keeps
its captured callback and release eligibility checks. Tab/arrow repetition moves
once per delivered event. Every desktop OS shares one traversal
implementation.

Application key callbacks run before focus handling and may call `consume_key()`
(or `consume_text_key()` for text-area commands). Open custom menus/dropdowns
handle their keys first. Editor Enter/Space and arrows keep their existing
editing/submit meanings, and the existing native IME command paths remain in use.

An element takes keys of its own by listing their names in `Element.keys`
(`keys` in VML), such as `['left', 'right', 'shift+tab']`. While the element
or one of its descendants has focus, a press of a listed key reaches the
nearest such element's `on_event` as a `key_down` event, before the application
key callbacks and focus handling: `key` is the key's name and `target` the
focused element. Names are `key_event_name(KeyEvent)`, the spelling `on_key`
receives: modifiers in the order `cmd`, `ctrl`, `alt`, `shift`, then the key.
A focused text field or text area passes a key on only when it lists the key
itself, so its caret keys stay with it. Autorepeated Enter and Space are
claimed but not delivered again.

Changing focus through these APIs does not move an existing editor selection to
its end. Unrelated declarations keep current focus, local text, selection and
scroll. Unchanged declared text preserves edits; a changed declaration or
`set_text(id, value)` replaces the edit buffer intentionally. `set_text`
keeps its existing selection clamping behavior. IME composition stays attached
to its editor across unrelated updates and is discarded when that editor loses
focus, is removed, hidden, disabled, or becomes readonly. This does not add
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
require an extra paint. These hooks do **not** establish an OS accessibility
bridge: the renderer does not publish the tree to VoiceOver, UIA or AT-SPI.

macOS keyboard behavior is exercised by the example and backend fixtures. Windows and Linux backend checks are distinct from runtime
acceptance on those operating systems. On iOS the renderer shows sokol's
on-screen keyboard while an editable field has focus; a hardware keyboard
reaches the same key handlers as on the desktop.
