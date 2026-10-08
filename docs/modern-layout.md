# Modern layout

UI2 uses declarative containers to assign parent-local frames. New screens can
use `Flex`, `Grid`, explicit alignment, and viewport expressions.
They work with runtime VML (`run_vml`, `VmlApp`, `element_from_vml_model`) and the
V API, on native backends and the custom renderer. Resizing invalidates layout
in the custom renderer too.

The layout containers are Flex (including Row and Column), Grid, Stack, Absolute,
and Scroll. Stack overlays children in declaration order with alignment; Absolute
provides explicit parent-local positioning for canvases and designer surfaces.

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
Flex {
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
Descendant layout sees the allocated dimensions. Element geometry expressions
are valid only for direct children of Absolute.
Min/max bounds freeze an item at its limit and redistribute the remaining space.
Explicit minima and `flex_shrink: 0` can intentionally overflow a small parent.
Use a scroll container when the content cannot fit. Without wrapping, the cross
axis fills the available line; wrapped lines use their natural cross-axis size.

For V callers, use `FlexConfig`, `FlexChild`,
`flex_frames`, `flex`, and `flex_preferred_size`.
V callers supply measured preferred frames before arranging children.

## Responsive grid

```text
Grid {
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
`GridSpan`, `GridConfig.child_spans`, `auto_columns_min_width`,
`max_columns`, and `grid_preferred_size`.

## Measurement and limits

`LayoutConstraints` describes minimum/maximum sizes; `LayoutSize` describes a
measured result. `measure_layout_element` accepts a text-measurement callback,
so layout can be tested without a window. `measure_layout_text` supplies actual
font metrics in logical units: the active custom renderer
uses gg, native macOS uses AppKit, and measurement before a custom window opens
uses a CPU-only fontstash context. Windows/iOS native measurement currently uses
that fontstash fallback, so it is not an exact native-control measurement there.
Flex and Grid use content measurement for omitted preferred dimensions.
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
intrinsic metrics, wrapping after width assignment, nested layouts, responsive
screens, repeaters, events/bindings and the wide/compact example.

Use `make check-backends` for cross-target type checks and
`make screenshot EXAMPLE=responsive_layout` for a custom-rendered capture.
Cross-target checks do not substitute for execution on those platforms.

## Stack and Absolute

`Stack` overlays children in declaration order. Container `align_x` and `align_y`
accept `start`, `center`, `end` and `stretch`. Child `align_self_x` and
`align_self_y` accept the same values plus `auto` to inherit. Padding leaves an
inner alignment area. Preferred size is the largest child plus padding.

`Absolute` keeps child frames parent-local. It is the container for explicit
coordinates and element geometry expressions. An omitted extent grows to cover
children; a declared width or height is exact. Neither container rounds layout.

V APIs: `StackConfig`, `StackChild`, `stack`, `stack_frames`,
`stack_preferred_size`, `AbsoluteConfig`, `absolute`, `absolute_frames`,
`absolute_preferred_size`. Independent fixtures are in `ui/stack_layout_test.v`
and `ui/absolute_layout_test.v`.

## View and geometry validation

`View` is the general styled container. Use Flex, Row, Column, Grid or Stack to
arrange its contents, or an Absolute child for free positioning. `Rectangle` is
removed. Authored child `x`/`y`, including zero, require a direct Absolute parent.
Element geometry expressions such as `root.width - 32` in width/height require
the same context, including preferred-size limits, basis, gap, padding and track
dimensions. Viewport predicates can still select visibility or responsive modes.
Repeaters inherit their containing layout. App and item data
remain valid size bindings. Layout-generated frames are already allocated.
