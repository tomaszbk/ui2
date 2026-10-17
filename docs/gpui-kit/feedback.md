# Feedback components: progress, spinner, shimmer, icon

This group ports GPUI Kit's
[Progress](https://github.com/longbridge/gpui-kit/blob/main/website/component/progress.md),
[Spinner](https://github.com/longbridge/gpui-kit/blob/main/website/component/spinner.md),
[Shimmer](https://github.com/longbridge/gpui-kit/blob/main/website/component/shimmer.md) and
[Icon](https://github.com/longbridge/gpui-kit/blob/main/website/component/icon.md).

| GPUI Kit | ui2 | Source |
| --- | --- | --- |
| `Progress` | `linear_progress(LinearProgressConfig)`; `progress_bar` is kept | `ui/component_feedback_progress.v` |
| `ProgressCircle` | `progress_circle(ProgressCircleConfig)` | `ui/component_feedback_progress.v` |
| `Spinner` | `loading_spinner(LoadingSpinnerConfig)` | `ui/component_feedback_spinner.v` |
| `ShimmerText`, `ShimmerStyle` | `shimmer_text(ShimmerTextConfig)` | `ui/component_feedback_shimmer.v` |
| `Skeleton` with a sheen | `shimmer(ShimmerConfig)` over `skeleton` shapes | `ui/component_feedback_shimmer.v` |
| `Icon`, `IconName` | `named_icon(IconConfig)`, `IconName` | `ui/component_feedback_icon.v` |

Shared helpers live in `ui/component_feedback.v`, the tests in
`ui/component_feedback_test.v`, and `examples/gpui_feedback/main.v` shows every
component and variant with its loops running:

```sh
# from the directory that contains the ui2 checkout
v run ui2/examples/gpui_feedback/main.v
```

The loading spinner is called `loading_spinner` because ui2's `spinner` is a
selection control (Kivy's Spinner), and the icon builder is `named_icon` because
`icon` is a local variable in `ui/message_box_windows.c.v`, which a function of
that name would shadow.

## How the loops work

ui2 has no canvas, no clipping view and no per-frame callback, so every moving
part is an ordinary view whose [motion](../motion.md) plays a looping timeline
over it: keyframes of its position, box width, opacity or color from the start
of the cycle to its end. A part is laid out once; its timeline moves it and
sizes its box by presentation alone, and nothing allocates while it runs.

- Every animated component requires a non-empty `id`. Its parts use stable ids
  under `${id}:component:`.
- A loop plays while its part is mounted and ends when the part leaves the
  tree, so a spinner that is no longer shown stops on its own and the window
  returns to idle.
- Rebuilding with the same settings keeps the loops running; a new size, speed
  or fading color is a new timeline, which starts over.
- Every animated component takes `reduce_motion`, which draws it at rest: GPUI
  does the same when the system asks for reduced motion. `set_reduced_motion`
  does the same for every component in the application.
- Android and iOS, which have no motion, draw the components at rest, as
  `reduce_motion` does. Linear progress changes its value at once there.

ui2 colors are opaque, so GPUI's translucent tracks are flattened: a track
defaults to the indicator color mixed 20% over the theme's background. Rings
fill their hole with the background too; give `background` the surface color
when a ring sits on a card or inside a colored button.

### Rings on the two kinds of renderer

ui2 cannot rotate a view or draw an arc, so rings are built from simple views:

- **Headless:** overlapping round cells along the ring, half a stroke apart, so
  an arc gets round ends.
- **Custom renderer:** gg draws a rounded rectangle with about 370 sokol-gl
  vertices and its buffer holds 65,536 a frame, so a few hundred round cells blank
  the whole window. There a ring is scan-converted into horizontal strips half a
  point tall, the way `chart.v` draws doughnut slices, at six vertices each, with
  the round ends scan-converted too.

The track is two discs (the track color and the background-colored hole). An
indeterminate arc moves by showing and hiding its cells (or, for strips, 24
sectors of strips) at the right moments, so only one element per cell changes
per frame and none is recolored.

## Progress

### `linear_progress`

```v
bar := ui2.linear_progress(
	id:    'upload'
	frame: ui2.rect(16, 16, 320, 12)
	value: model.percent // 0...100, clamped
	theme: theme
)!
busy := ui2.linear_progress(id: 'sync', frame: ui2.rect(16, 40, 320, 12), loading: true)!
```

| Field | Meaning |
| --- | --- |
| `value` | Percent, clamped to 0...100 (`progress_percent`); NaN is 0 |
| `loading` | GPUI's indeterminate slide: the right edge eases to the end over a 1 s cycle while the left edge follows in the second half (`linear_progress_loading_span`) |
| `transition` | Seconds a value change takes (0.25, out-cubic); 0 jumps |
| `duration` | Seconds per indeterminate cycle (1.0) |
| `size` / `thickness` | Bar height: small 6, medium 8, large 10 (GPUI's xsmall is `thickness: 4`), centered in the frame |
| `radius` | Corner radius; a pill by default |
| `tone`, `color`, `track_color` | Indicator color from the tone (primary), track at 20% over the background |
| `accessibility_label` | `progressbar` role; the value is announced as `40%`, nothing while loading |

The existing `progress_bar` keeps its Kivy value/max API. `linear_progress` adds
the GPUI sizes, the indeterminate mode, value transitions and theme colors.

### `progress_circle`

```v
ring := ui2.progress_circle(
	id:       'upload-ring'
	frame:    ui2.rect(16, 16, 96, 96)
	diameter: 88
	value:    model.percent
	label:    '${int(model.percent)}%'
	caption:  'Uploaded'
	size:     .large
	theme:    theme
)!
inline := ui2.progress_circle(id: 'download', frame: ui2.rect(16, 120, 16, 16), value: 40)!
```

| Field | Meaning |
| --- | --- |
| `value`, `loading` | Determinate arc from twelve o'clock, or GPUI's indeterminate arc that grows round the ring and is chased off it by its tail (`progress_circle_loading_arc`) |
| `size` / `diameter` | small 12, medium 16, large 20 (GPUI's presets), centered in and limited to the frame |
| `thickness` | GPUI's stroke: 15% of the diameter, at most 5 |
| `tone`, `color`, `track_color`, `background` | Arc, track and hole colors |
| `label`, `caption` | Centered text, the caption smaller and muted below the label; `size` picks the font |
| `children` | Extra content, placed relative to the ring's square |
| `duration`, `reduce_motion`, `accessibility_label` | As for `linear_progress`; at rest the loading ring shows a quarter arc |

Omitted from Progress and ProgressCircle:

- GPUI's `Styled` refinements (borders, arbitrary styles): ui2 configs take the
  explicit fields above instead.
- A transition when a ring's value changes: the arc is rebuilt from cells, which
  motion cannot interpolate. Linear bars do transition, with a `.box` layout
  transition of their indicator.
- Reading the system's reduce-motion setting: pass `reduce_motion`, or call
  `set_reduced_motion` once for the whole application.

## Spinner: `loading_spinner`

```v
spinner := ui2.loading_spinner(id: 'saving', frame: ui2.rect(16, 16, 16, 16))!
ring := ui2.loading_spinner(
	id:         'button-busy'
	frame:      ui2.rect(12, 8, 16, 16)
	kind:       .ring
	color:      theme.primary_foreground
	background: theme.primary // the button's fill
	theme:      theme
)!
```

| Field | Meaning |
| --- | --- |
| `kind` | `.dots` (default, GPUI's `Loader`): eight dots, a bright head with a fading tail. `.ring` (GPUI's `LoaderCircle`): a three-quarter arc going round a faint track |
| `size` / `diameter` | small 14, medium 16, large 24 (GPUI's xsmall is `diameter: 12`), centered in the frame |
| `duration` | Seconds per revolution (0.8, like GPUI); the head eases in and out (`loading_spinner_head`) |
| `tone`, `color`, `track_color`, `background` | Defaults to the muted text color, like a neutral GPUI spinner |
| `reduce_motion`, `accessibility_label` | At rest; `progressbar` role labelled `Loading`, no value |

Omitted: rotating an arbitrary icon (`.icon(...)`) and a custom easing function.
Views cannot be rotated and the custom renderer does not rotate symbol glyphs, so
both looks are built from parts that light up in turn instead.

## Shimmer

### `shimmer`: skeleton shapes with a sweeping sheen

```v
mut shapes := [ui2.ShimmerShape{
	frame:  ui2.rect(0, 0, 44, 44)
	circle: true
}]
shapes << ui2.shimmer_paragraph(56, 6, 300, 3, 12, 8) // three lines, the last shorter
card := ui2.shimmer(id: 'card-loading', frame: ui2.rect(16, 16, 360, 64), shapes: shapes)!
```

Each shape is drawn by batch 1's `skeleton`. A soft band, six nested views
stepping from the base color to the highlight, sweeps across the rectangles; a
circle brightens as the band passes its center. The timing follows GPUI's
`ShimmerStyle`:

| Field | Meaning |
| --- | --- |
| `duration` | One sweep, 2 s; shorter values are clamped to 1 ms |
| `spread` | Band half-width as a fraction of the frame width, clamped to 0.05...1 (0.3); a non-finite value keeps the default |
| `spread_pixels` | An absolute half-width (at least 1) used instead, so neighboring shimmers share a band width |
| `reverse`, `once` | Right to left; one sweep only |
| `base_color`, `highlight_color` | Shape fill and the brightest band color. In a light theme the base is a step darker than `skeleton`'s muted fill so the lighter band shows; in a dark theme the band moves toward the foreground |
| `reduce_motion`, `accessibility_label` | Shapes without a sweep; a `status` labelled `Loading` |

Renderers do not clip a view to its parent's rounded corners, so the band
crosses only the straight middle of a rounded shape and leaves its round ends
in the base color.

### `shimmer_text`

```v
thinking := ui2.shimmer_text(id: 'assistant', frame: ui2.rect(16, 16, 200, 20), text: 'Thinking…')!
```

GPUI paints its band over individual glyphs. ui2 has neither per-glyph painting,
clipping nor text measurement, so the whole label brightens while the band is
over its frame's center: the label's text color pulses toward GPUI's theme-aware
highlight (`shimmer_text_highlight`: toward the background in a light theme and
the foreground in a dark one, or the other way when the text already has that
lightness). `duration`, `spread`, `spread_pixels`, `once`, `highlight_color`,
`color`, `font_size`, `bold`, `align` and `reduce_motion` are supported; `reverse`
has no visible effect on a pulse and is omitted. The text stays a normal label
for assistive technology.

Not ported: Marker and Attachment integration (those components are not in ui2).

## Icon: `IconName` and `named_icon`

```v
search := ui2.named_icon(name: .search, frame: ui2.rect(16, 16, 16, 16), theme: theme)!
warning := ui2.named_icon(
	name:       .info
	frame:      ui2.rect(40, 12, 24, 24)
	pixel_size: 24
	color:      theme.danger
)!
tagged := ui2.named_icon(symbol: 'tag', frame: ui2.rect(72, 16, 16, 16))!
```

`named_icon` returns an `image` element whose path is `symbol:<SF Symbol>`, tinted
with `text_style.color`, centered in `frame` at `pixel_size` (or the size preset:
small 14, medium 16, large 24; GPUI's xsmall is 12). Its role is `img` and its
label the icon's title (`IconName.title()`), unless `accessibility_label` is set.
`symbol` takes any name `symbol_known` accepts instead of an `IconName`; other
names are rejected because the renderer would draw a question mark for them.
`icon_names()` lists every `IconName`.

The renderer draws the Material Icons glyph from `ui/symbols.v` in the text
color. `rotation` (degrees clockwise) is the element's visual rotation, which
Android and iOS do not support.

`IconName` has the GPUI names with a counterpart in `ui/symbols.v` that draws the
same thing in both faces:

| IconName | SF Symbol | IconName | SF Symbol |
| --- | --- | --- | --- |
| `a_large_small` | `textformat.size` | `align_justify` | `text.justify` |
| `case_sensitive` | `textformat` | `align_left` | `text.alignleft` |
| `chevrons_up_down` | `arrow.up.and.down` | `align_right` | `text.alignright` |
| `circle_user` | `person.crop.circle` | `badge` | `seal` |
| `close` | `xmark` | `book_a` | `character.book.closed` |
| `copy` | `doc.on.doc` | `box` | `cube.transparent` |
| `dash` | `minus` | `braces` | `curlybraces` |
| `delete` | `trash` | `chart_column` | `chart.bar` |
| `ellipsis` | `ellipsis` | `clipboard_list` | `list.bullet.clipboard` |
| `eye` | `eye` | `cloud_download` | `icloud.and.arrow.down` |
| `eye_off` | `eye.slash` | `cloud_upload` | `icloud.and.arrow.up` |
| `folder`, `folder_closed` | `folder` | `columns_3` | `rectangle.split.3x1` |
| `info` | `info.circle` | `copy_plus` | `plus.square.on.square` |
| `layout_dashboard` | `rectangle.3.group` | `crop` | `crop` |
| `menu` | `line.3.horizontal` | `download` | `arrow.down.to.line` |
| `minus` | `minus` | `file_plus` | `doc.badge.plus` |
| `palette` | `paintpalette` | `file_up` | `doc.badge.arrow.up` |
| `panel_right` | `sidebar.right` | `hash` | `number` |
| `plus` | `plus` | `history` | `clock.arrow.circlepath` |
| `redo`, `redo_2` | `arrow.uturn.forward` | `image` | `photo` |
| `refresh_cw`, `rotate_cw` | `arrow.clockwise` | `indent_increase` | `increase.indent` |
| `search` | `magnifyingglass` | `layers` | `square.stack.3d.up` |
| `settings` | `gearshape` | `layout_grid` | `rectangle.grid.2x2` |
| `settings_2` | `slider.horizontal.3` | `list_ordered` | `list.number` |
| `star` | `star` | `message_square_text` | `text.bubble` |
| `undo`, `undo_2` | `arrow.uturn.backward` | `mouse_pointer` | `cursorarrow` |
| `window_close` | `xmark` | `move_horizontal` | `arrow.left.and.right` |
| `window_minimize` | `minus` | `move_vertical` | `arrow.up.and.down` |
| | | `padlock` (Lucide `Lock`) | `lock` |
| | | `paintbrush`, `pencil`, `printer`, `scissors`, `tag` | same name |
| | | `repeat` | `arrow.2.squarepath` |
| | | `share` | `square.and.arrow.up` |
| | | `square_function` | `function` |
| | | `square_minus`, `square_plus` | `minus.rectangle`, `plus.rectangle` |
| | | `table` | `tablecells` |
| | | `user_round_plus` | `person.crop.circle.badge.plus` |
| | | `users` | `person.2` |

The left column comes from GPUI's default component icons, the right from the
wider Lucide catalog.

Gaps:

- GPUI's other default icons (check, chevrons, arrows, bell, calendar, the circle
  status icons, heart, globe, sun/moon, play/pause, user, file, thumbs, the
  window and panel variants and so on) have no entry in `ui/symbols.v`, and some
  names there draw a different picture in Material Icons (`asterisk` draws an
  outlined star, `rectangle.split.1x2` and `rectangle.split.2x1` draw the wrong
  panes, `arrow.right.to.line` draws an indent, the four-way move arrow draws
  diagonal ones), so they are left out until the table has them.
- The bundled Material Icons glyphs are filled where Lucide's are outlines.
- SVG paths and bytes (`Icon::path`, `Icon::data`) and custom `IconNamed` types:
  draw files with `image()`.
- `rotate`/`transform`: use `rotation`, the element's visual rotation.

## Accessibility

| Component | Role | Label | Value |
| --- | --- | --- | --- |
| `linear_progress`, `progress_circle` | `progressbar` | `accessibility_label` (`Progress`) | `40%`; empty while loading |
| `loading_spinner` | `progressbar` | `Loading` | empty (indeterminate) |
| `shimmer` | `status` | `Loading` | |
| `shimmer_text` | the label itself | its text | |
| `named_icon` | `img` | the icon's title | |

## Tests

```sh
# from the directory that contains the ui2 checkout
v test ui2/ui/component_feedback_test.v
```

The suite covers value clamping and announcement, size presets and geometry,
both ring builders (cells cover the centerline, strips cover the annulus and the
caps by area), value transitions from the width on screen, the indeterminate
curves sampled from the parts' timelines, eased spinner windows, loop restarts
on new settings, reduced motion, GPUI's
shimmer spread, band and highlight rules, `once`, the icon table against
`symbol_known`, and tiny or empty frames for every component.
