# Modern layout

UI2 uses declarative containers to assign parent-local frames. New screens can
use `FlexLayout`, `GridLayout`, explicit alignment, and viewport expressions.
They work with runtime VML (`run_vml`, `VmlApp`, `element_from_vml_model`) and the
V API, on native backends and the custom renderer. Resizing invalidates layout
in the custom renderer's `on_demand` mode too.

This is not CSS compatibility. Layout tables (`table`/`tr`/`td`), CSS floats and
clearfix, inline-block layout hacks, and absolute-position/transform centering
are outside the product contract. Data tables remain valid controls. Explicit
positioning remains useful for canvases and overlays; rotation/animation still
exist. The existing `FloatLayout` means proportional positioning, not CSS float.
Existing `Row`, `Column`, `BoxLayout`, and fixed-frame documents keep their APIs.

## Run the example

From the repository root:

```sh
v -d ui2_custom_rendering run examples/responsive_layout
v -d ui2_custom_rendering run examples/responsive_layout --compact
```

On macOS/Windows, omit the define to use native controls. The example includes a
wrapping toolbar, a flexible search field, a grid with a featured spanning card,
and model actions. Automatic columns collapse as the window narrows; the featured
card becomes a single cell. The outer scroll view makes shorter windows usable.
Text typed into the search field survives unrelated actions and resizes.

## Flex

```text
FlexLayout {
    orientation: horizontal
    gap: 12
    wrap: true
    align_items: center

    Label { text: "Projects" font_size: 22 flex_grow: 1 }
    Button { text: "New project" }
    Button { text: "Settings" }
}
```

| Container property | Meaning |
| --- | --- |
| `orientation` | `horizontal` (default) or `vertical` |
| `padding`, `padding_left/top/right/bottom` | Inner space |
| `gap` | Minimum distance between items, default 0 |
| `line_gap` | Distance between wrapped lines; defaults to `gap` |
| `wrap` | Start another line when preferred sizes do not fit |
| `justify` | `start`, `center`, `end`, `space_between`, `space_around`, `space_evenly` |
| `align_items` | Cross-axis `start`, `center`, `end`, or `stretch` (default) |

| Child property | Meaning |
| --- | --- |
| `width`, `height` | Preferred size; omitted dimensions use content measurement |
| `flex_basis` | Preferred main-axis size; defaults to the measured/declared size |
| `flex_grow` | Share of additional main-axis space, default 0 |
| `flex_shrink` | Shrink weight multiplied by basis, default 1 |
| `min_width`, `min_height` | Lower bounds, default 0 |
| `max_width`, `max_height` | Upper bounds, default unbounded |
| `align_self` | Override cross-axis alignment; default `auto` inherits the parent |

The parent owns the resulting frame: a preferred width of 200 may shrink or grow.
Nested expressions referencing the child's own id see its allocated dimensions.
Min/max bounds freeze an item at its limit and redistribute the remaining space.
Explicit minima and `flex_shrink: 0` can intentionally overflow a small parent.
Use a scroll container when the content cannot fit. Without wrapping, the cross
axis fills the available line; wrapped lines use their natural cross-axis size.

For V callers, use `FlexLayoutConfig`, `FlexLayoutChild`,
`flex_layout_frames`, `flex_layout`, and `flex_layout_preferred_size`.
V callers supply measured preferred frames before arranging children.

## Responsive grid

```text
GridLayout {
    auto_columns_min_width: 240
    max_columns: 3
    spacing: 16

    View { column_span: 2 }
    View { }
    View { }
}
```

Automatic mode requires omitted `columns` and `rows`. The column count follows
the available inner width and spacing, up to `max_columns` if set. It uses at
least one column, which shrinks below the requested minimum on narrow windows.
Alternatively declare `columns: root.width < 600 ? 1 : 3` for an explicit
breakpoint. Static VML without a model does not evaluate viewport expressions.

`column_span` and `row_span` default to 1. Placement uses declaration-order
first-fit cells in the selected orientation, without overlap. The unconstrained
axis grows as needed. In automatic mode a column span is capped to the current
column count, so a featured card can collapse to one column. Explicit grids
reject spans that cannot fit or exceed a fully specified capacity.

Tracks share surplus space after configured defaults/minimums. The existing
`col_default_width`, `row_default_height`, `col_force_default`,
`row_force_default`, padding and spacing properties still apply. In V, use
`GridSpan`, `GridLayoutConfig.child_spans`, `auto_columns_min_width`,
`max_columns`, and `grid_layout_preferred_size`.

## Measurement and limits

`LayoutConstraints` describes minimum/maximum sizes; `LayoutSize` describes a
measured result. `measure_layout_element` accepts a text-measurement callback,
so layout can be tested without a window. `measure_layout_text` supplies actual
font metrics with the existing point-size conversion: the active custom renderer
uses gg, native macOS uses AppKit, and measurement before a custom window opens
uses a CPU-only fontstash context. Windows/iOS native measurement currently uses
that fontstash fallback, so it is not an exact native-control measurement there.
Content sizing in VML
is opt-in through `FlexLayout`; old controls outside it keep their defaults.
Nested Flex and Grid containers measure their content before arrangement.
Images, sliders and switches still need declared preferred dimensions.

This does not implement the CSS specifications: no selectors/cascade, percentages
syntax, named grid areas, CSS track expressions, baseline alignment or subgrid.
Other container types should keep explicit preferred dimensions when nested in
Flex. Text shaping, bidirectional layout and complete grapheme handling remain
the separate text-stack work in the product plan. Font metrics and native control
appearance may differ across backends. The external V compiler's `$vml` lowering
has not been extended by this change; use runtime VML or the V API for Flex.

## Verification

The focused suites are `ui/flex_layout_test.v`, `ui/grid_layout_test.v`,
`ui/layout_measure_test.v`, `ui/layout_measure_darwin_test.v`, and
`ui/vml_modern_layout_test.v`. Run them with `v test <files>` and again with
`v -d ui2_custom_rendering test <files>`. They cover constrained allocation,
intrinsic metrics, wrapping after width assignment, nested layouts, adaptive
screens, repeaters, events/bindings and the wide/compact example.

Use `make check-backends` for cross-target type checks and
`make screenshot EXAMPLE=responsive_layout` for a custom-rendered capture.
Cross-target checks do not substitute for execution on those platforms.
