# The kit

The kit is ui2's set of ready-made controls, adapted from GPUI Kit. Each
control is a VML tag: `Button` lowers to `ui2.ButtonProps`, a props type that
builds an ordinary element tree. The same props types run in compiled VML,
in the interpreter and from V through the generic node runtime. The kit lives
in `ui/kit*.v`; [examples/kit_catalog](../../examples/kit_catalog) shows every
control on a page per group.

```vml
Row(gap: 8, align_items: center) {
    Button(text: "Save", variant: primary, icon: check, on_click: app.save())
    Button(text: "Cancel", on_click: app.cancel())
    Icon(name: bell, size: large)
}
```

## Conventions

A control is a props struct embedding `CommonProps`, with typed enums for its
choices (spelled bare in VML, `variant: primary`), and a
`build(ctx VmlBuildContext) !Element`. A control also declares what applies
to it:

| Method | Meaning |
|---|---|
| `vml_container()` | it takes element children |
| `vml_themed()` | its build reads `ctx.tokens()`; it rebuilds when its owner's theme changes |
| `control_size() ControlSize` | in a Flex it is at least the control height of that size, unless its height is authored |
| `vml_structure() VmlStructure` | `.sourced` when it places or reads its children, `.generated` when it makes its own |
| `apply_event(event)` | it keeps local state that its events update (see [State](#state-and-events)) |
| `validate() !` | checks its own fields only |
| `control_id_required() bool` | it needs a public id (interactive parts, overlays) |

The rules every control follows:

- Geometry comes from layout. `ctx.frame` is passed through as the root frame;
  children are laid out by Flex, Grid or Stack and sized by their content.
  Control heights come from the `control_height_*` tokens as a floor.
- Colors and metrics come from `ctx.tokens()`, read once per build.
- Callbacks capture ids, values and the emitter (`ctx.emitter`), never `ctx`,
  which holds the children.
- A control never calls `validate_element_tree`; the runtime validates once
  per committed batch.
- Timers start from event handlers through `kit_after`, never from `build`;
  `kit_cancel` calls one off.
- Popups are overlays (`with_overlay`), with no z-index layers.
- A control uses few elements. Draw a repeated shape as one vector path or
  gradient, not as a strip of cells.

## Tokens

`ctx.tokens()` returns the `KitTokens` of the owner the control is built in:
the theme of each component ancestor from the root down, over
`default_theme()`. Without an owner it is the default theme's. A theme change
(`set_vml_theme(root, theme)` or a component's `set_theme`) drops the cached
tokens of the component and its descendants and rebuilds their themed
controls in the same batch.

| Method | Result |
|---|---|
| `t.metrics(size)` | `ControlMetrics`: `height`, `font_size`, `padding_x` (1.5 times the control padding token), `padding_y` (centers one line of text in `height`), `gap`, `radius`, `icon` |
| `t.tone_colors(tone)` | the fill of a `Tone` and the text drawn over it |
| `t.popup_shadow()` | the shadow of a popover, menu, dialog or sheet |
| `t.card_shadow()` | the lighter shadow of a toast or card |
| `t.scrim_opacity()` | a modal backdrop's opacity: 0.4 light, 0.6 dark |
| `t.control_paint()` | the `ControlPaint` of renderer-drawn controls, for `Element.paint` |
| `button_variant_colors(t, variant, selected, enabled)` | a `ButtonVariant`'s fill, foreground, border, hover and pressed colors, for controls that match buttons |

`t.dark` is true when the surface is dark; it sets the scrim and shadow
strength. The color math the controls derive states from is `kit_mix`,
`kit_luminance`, `kit_contrast` and `kit_legible` in `kit.v`.

### Colors

Tokens named `on_*` are the text drawn over the color of the same name.

| Token | Light | Dark | Use |
|---|---|---|---|
| `surface` | `#FFFFFF` | `#172033` | the page |
| `surface_muted` | `#F1F5F9` | `#263449` | secondary fills |
| `popover` | `#FFFFFF` | `#1E293B` | menus, popovers, dialogs and sheets |
| `text` | `#172033` | `#F8FAFC` | |
| `muted` | `#64748B` | `#B4C0D0` | secondary text |
| `border` | `#CBD5E1` | `#475569` | |
| `input`, `input_border` | `#FFFFFF`, `#CBD5E1` | `#0F172A`, `#475569` | field fills |
| `accent`, `on_accent` | `#2563EB`, `#FFFFFF` | `#93C5FD`, `#172033` | primary actions |
| `success`, `on_success` | `#15803D`, `#FFFFFF` | `#86EFAC`, `#172033` | |
| `warning`, `on_warning` | `#FBBF24`, `#172033` | `#FBBF24`, `#172033` | |
| `danger`, `on_danger` | `#B91C1C`, `#FFFFFF` | `#FCA5A5`, `#172033` | |
| `info`, `on_info` | `#0369A1`, `#FFFFFF` | `#7DD3FC`, `#172033` | |
| `focus_ring` | `#2563EB` | `#93C5FD` | |
| `hover`, `pressed` | `#E4E8ED`, `#D7DBE1` | `#334054`, `#3F4C5E` | interaction fills |
| `selection` | `#DBEAFE` | `#1E3A8A` | selected rows and segments |
| `track` | `#E2E8F0` | `#334155` | slider, progress and switch tracks |
| `disabled_text` | `#94A3B8` | `#64748B` | |
| `tooltip`, `on_tooltip` | `#172033`, `#F8FAFC` | `#F8FAFC`, `#172033` | |
| `backdrop` | `#0F172A` | `#000000` | modal scrims, at `scrim_opacity()` |
| `shadow` | `#000000` | `#000000` | |

### Metrics

| Size | Height | Font | Padding (vertical token) | Gap | Radius |
|---|---|---|---|---|---|
| `small` | 24 | 12 | 6 | 4 | 4 |
| `medium` | 32 | 14 | 8 | 6 | 6 |
| `large` | 40 | 16 | 12 | 8 | 8 |

These are the tokens `spacing.control_height_*`, `typography.control_*`,
`spacing.control_*`, `spacing.gap_*` and `radius.control_*`. Popovers use
`radius.popover` (8) and dialogs `radius.dialog` (12); `spacing.xsmall` is 4.

## State and events

A control's props are its initial values plus its local state. A control with
state declares `apply_event`, which updates the props from the control's own
events. `bind.field:` writes the updated field back to the author's source,
and a reactive property re-asserts its value when its source changes, so a
control is uncontrolled without a binding and controlled with one.

The parts of a control send the control's events through an emitter:

```v
pub fn (p StepperProps) build(ctx VmlBuildContext) !Element {
	emitter := ctx.emitter(p.element_callback())
	next := f64(p.value + 1)
	plus := kit_button(ctx, 'plus', ButtonProps{
		text:     '+'
		on_click: fn [emitter, next] (event ElementEvent) {
			emitter.emit(ElementEvent{ kind: .change, id: event.id, value: next })
		}
	})!
	// ...
}
```

`emit` delivers the event as the control's: its `id` is the control's public
id and its `target` the part it came from. The control's dispatcher then runs
`apply_event`, the `bind.*` write-backs and the root element's callback, which
calls the author's handlers (`on_change` and so on). A control without state
or bindings has no dispatcher; the emitter then calls the fallback, the root
element's own callback.

| Event | Payload | Controls |
|---|---|---|
| `.change` | `text` | Select, Tabs, Radio, single Accordion |
| `.change` | `value` | Slider, Rating, NumberInput, Pagination, Carousel |
| `.change` | `checked` | Checkbox, Switch, Toggle, Collapsible |
| `.open`, `.dismiss` | sets `open` | popups |
| `.submit` | | Dialog Enter |

## Keys

An element lists the keys it handles in `Element.keys` (`keys:` in VML).
While it or a descendant has focus, a press of one of them reaches its
`on_event` as a `.key_down` event before the application's key handlers and
focus navigation. Key names are the modifiers in the order `cmd`, `ctrl`,
`alt`, `shift`, then the key, joined with `+`: `left`, `enter`, `shift+tab`,
`cmd+s` (`key_event_name`). A focused text field or text area keeps its caret
keys unless it lists the key itself. See
[focus navigation](../focus-navigation.md).

## Parts and records

The internal elements of a control are its parts. A part's id is
`ctx.part_id(name)`, `<id>__<name>`, local to the control's owner like every
element id in a build; a reference to a part from a config (an overlay anchor,
an initial focus) is `ctx.resolve_id(ctx.part_id(name))`. Each part sets its
`accessibility_role`.

A child that describes itself to its parent (a tab, an accordion item, a
slide) attaches a record with `with_record(element, record)`, and the parent,
a `.sourced` control, reads it with `ctx.child_record[T](index)`. Part-only
tags such as `Option` stay `VmlPartProps`.

## Registry

Every tag is also registered for the interpreter. The kit's tags are in three
fragments, `ui/kit_registry_{actions,popups,display}_d_vml_interpreter.v`, one
line per tag; each fragment also lists its bindable fields and part-only tags,
which `ui/vml_registry_test.v` checks against the props types.

## Button

`Button` is a `.view` with button behavior: a row of its icon (or a spinner
while `loading`), its caption, its element children and `icon_end`.

| Property | Values |
|---|---|
| `text` | the caption |
| `variant` | `primary`, `secondary` (default), `outline`, `ghost`, `link`, `danger`, `success`, `warning` |
| `size` | `small`, `medium` (default), `large` |
| `icon`, `icon_end` | an `IconName` |
| `loading` | shows a spinner and ignores clicks |
| `selected` | the pressed look of a toggled button |

An author's `style:` patches the variant's box, interaction states and
caption. A control builds a button part with `kit_button(ctx, part, props)`.

## Icon

`Icon(name: bell)` draws an `IconName` as a portable symbol. `size` picks 14,
16 or 24 units for `small`, `medium` and `large`; `pixel_size` sets any size;
`color` defaults to the `text` token.
