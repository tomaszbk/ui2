# Display, feedback, disclosure and navigation

These kit controls show content and status, open and close sections, and move
between pages. Display controls are in `ui/kit_display.v`, feedback in
`kit_feedback.v`, disclosure in `kit_disclosure.v` and navigation in
`kit_navigation.v`. Their pure logic (badge counts, initials, the pagination
window, slide indexes, keyboard selection and tree rows) is in
`kit_logic_display.v`, which has its own tests. The catalog's display page,
[display_page.vml](../../examples/kit_catalog/display_page.vml), shows each
one. The conventions they follow are in the [kit overview](README.md).

```vml
Column(gap: 12) {
    Alert(title: "Saved", text: "Your changes are live.", tone: success)
    Progress(value: app.uploaded, max: app.total)
    Tabs(id: "sections", bind.value: app.section) {
        Tab(value: "overview", text: "Overview") {
            Label(text: "A summary of the project.")
        }
        Tab(value: "activity", text: "Activity", icon: history) {
            Label(text: "Recent commits and reviews.")
        }
    }
}
```

A `tone` is `neutral`, `primary`, `info`, `success`, `warning` or `danger`.
A `size` is `small`, `medium` or `large`. Controls marked *id* need an `id`,
because they hold focus or have parts that do.

## Display

| Tag | Properties | Shows |
|---|---|---|
| `Badge` | `count`, `max` (99), `dot`, `tone` (`danger`) | a count in a bubble at the top right of its children, or a dot. A zero count hides the bubble, and a count past `max` reads `99+`. |
| `Avatar` | `name`, `src`, `size` | a circle with the image at `src`, or else the initials of `name` |
| `Tag` | `text`, `tone` (`neutral`), `outline`, `size`, `icon` | a short label in a tinted box; `outline` draws the tone as a border |
| `Separator` | `orientation`, `text` | a one-unit rule across its parent, or down it when `vertical`; `text` sits between two rules |
| `Kbd` | `text` | a key or shortcut as a keycap |
| `Link` (*id*) | `text`, `on_click` | underlined accent text, focusable like a button |
| `Alert` | `title`, `text`, `tone` (`info`), `icon` | a tinted box with the tone's icon, the title, the text and its children |
| `Empty` | `title`, `text`, `icon` (`folder`) | the centered placeholder of a list or page with no content, with its children (an action) below |
| `GroupBox` | `title` | its children in a bordered box under the title |
| `DescriptionList` | `label_width` (120), `bordered` (true) | a row per `DescriptionItem(label:, text:)` child, the label beside the value |

A `DescriptionItem`'s value is its `text` followed by its children.

## Feedback

| Tag | Properties | Shows |
|---|---|---|
| `Progress` | `value`, `max` (100), `size`, `tone` (`primary`), `loading` | a bar filled to value / max; `loading` sweeps a segment along it |
| `ProgressCircle` | the same | a ring filled clockwise from twelve o'clock; `loading` turns a quarter arc. A width or height sets the diameter. |
| `Spinner` | `size`, `color` | a turning three-quarter ring, in the secondary text color by default |
| `Skeleton` | `circle` | a pulsing placeholder box 16 units tall, or a 40-unit circle. A width or height sets its size. |
| `Shimmer` | `lines` (3), `spread` (0.3), `reverse` | a placeholder paragraph with a light band sweeping across each line |
| `Clipboard` (*id*) | `value`, `copied`, `text`, `variant` (`ghost`), `size` (`small`) | a button that copies `value` to the system clipboard |

After a copy, a Clipboard shows a check and `copied` is true for two seconds.
`copied` is bindable. The click handler starts the timer that clears it,
through the window's `after`.

Each animated control plays a looping motion timeline built once per build.
It asks for frames only while it is shown. Under reduced motion (see
[motion](../motion.md#reduced-motion)) none of them moves: a Spinner and a
loading ProgressCircle stand still, a loading Progress is a full bar, and
Skeleton and Shimmer are plain placeholders.

## Disclosure

`Collapsible` (*id*) is a header with `text` and an optional `icon` that shows
and hides the children below it. `open` is bindable.

`Accordion` (*id*) takes `AccordionItem(value:, title:, icon:)` children and
draws a header before each one. An item's children are laid out in a column,
and its `value` defaults to its `title`. A header click emits a change whose
`text` is the item's value:

- by default one item is open, the one named by `value`, and clicking it
  closes it;
- with `multiple`, any number are open, named by `values`.

Both `value` and `values` are bindable. `bordered` (true) boxes the accordion
and rules its items apart.

A header is a button: a click, or Enter or Space while it has focus, opens or
closes its content. Its value is `expanded` or `collapsed`. Opened content
fades in, closed content hides at once, and the box around it slides to its
new height.

## Navigation

| Tag | Bindable | Emits | Keys while focused |
|---|---|---|---|
| `Tabs` (*id*) | `value` (string) | change `text` | Left, Right, Home, End |
| `Breadcrumb` (*id*) | | its items' `on_click` | |
| `Pagination` (*id*) | `page` (int) | change `value` | |
| `Tree` (*id*) | `value` (string) | change `text` | Up, Down, Left, Right, Home, End, Enter, Space |
| `Carousel` (*id*) | `index` (int) | change `value` | Left, Right, Home, End |

**Tabs** shows the panel of the `Tab(value:, text:, icon:)` child named by
`value`, or of the first enabled tab when no tab has that value. A Tab's
`value` defaults to its `text`, and its children are laid out in a column.
The hidden panels stay mounted. `variant` is `underline` (default), `pill` or
`segmented`, and `size` sizes the triggers. The tab list is the one tab stop:
its arrow keys move to the next enabled tab and wrap around.

**Breadcrumb** takes `BreadcrumbItem(text:, icon:, enabled:, on_click:)`
parts, separated by chevrons. Every item but the last that has an `on_click`
is a link. The last item is the current page.

**Pagination** shows `total_pages` pages as previous and next buttons around
up to `visible_pages` (5) page buttons. The first and last pages are always
shown, and an ellipsis stands for the pages left out. Choosing a page emits
its number, which starts at 1.

**Tree** draws a row per shown `TreeItem(value:, text:, icon:, expanded:)`.
TreeItems nest, and a TreeItem's `value` defaults to its `text`. A click
selects a row, and a click on a parent row also expands or collapses it. A
TreeItem's `expanded` is bindable. With the keys:

- Up and Down move the selection.
- Right expands a parent, or else enters it.
- Left collapses a parent, or else goes to the row's parent.
- Enter and Space expand or collapse.

**Carousel** shows the `CarouselSlide` child at `index`, above previous and
next buttons and a dot per slide. A slide's children are laid out in a
column, and its `accessibility_label` names it in the carousel's value
(`Slide 2 of 3: Forest`). With `loop`, the buttons and arrow keys wrap
around. A slide fades in from the right and out to the left.

Tabs, Tree and Carousel each keep one tab stop, which takes the keys. The
triggers, rows and buttons inside take clicks, so focus never moves when the
selection does.
