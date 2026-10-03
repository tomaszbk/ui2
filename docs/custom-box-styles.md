# Custom box borders and interaction styles

The custom renderer draws borders inside the declared frame, independently of
background transparency. Each side can override `border_color`, including black.
Rounded corners join the sides as a single ring. `border_pattern: "dashed"` uses
logical `dash_length` and `dash_gap` (defaults 6 and 4), continuing around corners.
Widths that exhaust the frame are proportionally clamped so the ring stays inside.

```qml
View {
    id: card
    button_behavior: true
    on_tap: app.open()
    width: 200 height: 80
    background: #ffffff
    radius: 12
    border_width: 2
    border_color: #64748b
    border_top_color: #2563eb
    hover_background: #eff6ff
    hover_color: #1a1a2e
    focus_border_color: #2563eb
    focus_outline_color: #2563eb
    focus_outline_width: 3
    focus_outline_offset: 3
    pressed_background: #dbeafe
    disabled_background: #f1f5f9
}
```

Visual state properties use the `hover_`, `focus_`, `pressed_` and `disabled_`
prefixes with `background`, `radius`, `transparent`, `border_color`, `border_width`,
individual border widths/colors, `border_pattern`, `dash_length`, `dash_gap`,
`outline_color`, `outline_width` or `outline_offset`. `hover_color` and corresponding
state prefixes change the caption color using `TextStylePatch`. Rich Run colors
retain their explicit styles. Outlines paint outside the frame and preserve hit
bounds; a nonnegative offset separates them from the border. Parent clipping
applies to outlines.
Omitted properties inherit the declared box. Explicit zero, black and false work.
State precedence is hover, focus, pressed; disabled uses only its declared patch.
These changes affect paint, preserving layout, identity, actions and editor state.

In V, use `with_interaction_style(element, InteractionStyle{...})` with sparse
`BoxStylePatch` values. Focus follows existing focused editors or the explicit
`Element.focused` state. This API does not add keyboard focus traversal to views.
Hover uses the pointer's clipped region; a captured press applies while the pointer
remains inside and the gesture has not become a drag. Touch presses work too.

Per-edge colors, rounded border joins, dash patterns and these state patches are
currently custom-renderer features. Native controls keep their platform interaction
and their existing common-color border implementation.
