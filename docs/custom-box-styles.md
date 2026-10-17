# Custom box borders and interaction styles

The custom renderer draws borders inside the declared frame, independently of
background transparency. Each side can override `border_color`, including black.
Rounded corners join the sides as a single ring. `border_pattern(dashed)` uses
logical `dash_length` and `dash_gap` (defaults 6 and 4), continuing around corners.
Widths that exhaust the frame are proportionally clamped so the ring stays inside.

```vml
View(
    id: "card",
    button_behavior: true,
    on_click: app.open(),
    width: 200,
    height: 80,
    style: [
        background(#ffffff),
        radius(12),
        border_width(2),
        border_color(#64748b),
        border_top_color(#2563eb),
        hover([background(#eff6ff), foreground(#1a1a2e)]),
        focus([
            border_color(#2563eb),
            outline_color(#2563eb),
            outline_width(3),
            outline_offset(3)
        ]),
        pressed([background(#dbeafe)]),
        disabled([background(#f1f5f9)])
    ],
)
```

Visual states compose nested `hover([...])`, `focus([...])`, `pressed([...])` and
`disabled([...])` patches inside the element's style list. These accept box
helpers and `foreground(...)`; layout and metric text properties are rejected
inside an interaction state. `foreground(...)` changes the caption color.
Rich Run colors
retain their explicit styles. Outlines paint outside the frame and preserve hit
bounds; a nonnegative offset separates them from the border. Parent clipping
applies to outlines.
Omitted properties inherit the declared box. Explicit zero, black and false work.
State precedence is hover, focus, pressed; disabled uses only its declared patch.
These changes affect paint, preserving layout, identity, actions and editor state.

In V, use `with_interaction_style(element, InteractionStyle{...})` with sparse
`BoxStylePatch` values. Focus follows existing focused editors, or the element
named by `set_backend_text_focus` when an input backend in another process owns
text focus. This API does not add keyboard focus traversal to views.
Hover uses the pointer's clipped region; a captured press applies while the pointer
remains inside and the gesture has not become a drag. Touch presses work too.

Per-edge colors, rounded border joins, dash patterns and these state patches are
currently renderer features. On iOS, VML diagnoses unsupported presentation
properties; UIKit controls keep their platform interaction and supported
common-color border implementation.
