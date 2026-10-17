# GPUI Kit component migration

This port is in progress; the [parity tracker](#parity-tracker) lists every
GPUI Kit component and its status. Batch 1 compared
UI2 at `15709bb28ddb4a05c499f52936a11cf0feedb22d` with
[GPUI Kit](https://github.com/longbridge/gpui-kit) at
`1b6059c13315dc5c304759ad3aa666e0b6e301d8`.

## Added components

All constructors return `!Element`, validate finite/non-negative frame
geometry, and compose existing UI2 elements rather than introducing renderer
kinds or a Rust dependency. Their child frames are parent-local.

| GPUI Kit concept | UI2 API | Behavior in this migration |
| --- | --- | --- |
| Badge | `badge(BadgeConfig)` | Text, capped counters, zero visibility, dot display |
| Avatar | `avatar(AvatarConfig)` | Image or Unicode-scalar first/last initials |
| Tag | `tag(TagConfig)` | Solid/outline styling, optional close callback |
| Separator | `separator(SeparatorConfig)` | Horizontal/vertical, bounded thickness |
| Skeleton | `skeleton(SkeletonConfig)` | Static rounded or centered circular placeholder |
| Kbd | `kbd(KbdConfig)` | Display-only keyboard shortcut hint |
| Link | `link(LinkConfig)` | Button activation with application-owned navigation |
| Alert | `inline_alert(InlineAlertConfig)` | Inline title/message and optional dismiss callback; `alert()` remains the OS message box |
| Empty | `empty_state(EmptyStateConfig)` | Empty-state text and optional primary action |
| GroupBox | `group_box(GroupBoxConfig)` | Labeled border and padded content body |
| DescriptionList | `description_list(DescriptionListConfig)` | Two-column term/value rows |
| Collapsible | `collapsible(CollapsibleConfig)` | Controlled disclosure; closed content unmounted |
| Breadcrumb | `breadcrumb(BreadcrumbConfig)` | Stable item keys, disabled items, non-actionable current location |
| Pagination | `pagination(PaginationConfig)` | Controlled page navigation, page windows, compact mode |

The display and container builders are new V implementations following the
catalog's concepts. The pagination state/window algorithm is adapted from
`crates/base/src/pagination.rs`; see the [attribution](../third_party/gpui-kit/NOTICE.md)
and Apache-2.0 license. Existing UI2 code remains under its existing license.

## Added primitives

`ComponentSize` and `component_metrics` supply small/medium/large metrics.
`ComponentTheme`, `ComponentTone`, and `component_theme(dark)` provide explicit,
immutable semantic color tokens. Pass the same theme to related components;
there is no global theme singleton. `component_inset` safely pads a `Rect`,
preserving its coordinate space and clamping padding for tiny frames.

`PaginationState` contains normalized, immutable controlled state. It clamps
empty totals to one page, rejects disabled/current/out-of-range transitions,
and exposes `items()`, `previous_page()`, `next_page()`, and `request_page()`.
The requested visible window is clamped to 5..100; total pages are not capped.
Ellipses expose half-open hidden ranges, so clients can implement their own
jump UI without allocating a list for every page in the dataset.

`on_page` receives the page a click asks for, already checked with
`request_page` against the state the control was built from. Store it and
rebuild:

```v
state := ui2.pagination_state(5, 1000).with_visible_pages(7)
pages := ui2.pagination(
    id: 'results'
    frame: ui2.rect(20, 20, 420, 40)
    state: state
    theme: ui2.component_theme(false)
    on_page: fn [mut app] (page int) {
        // Rebuild pagination with pagination_state(page, state.total_pages()).
        app.page = page
        ui2.request_refresh()
    }
) or { panic(err) }
```

Disabled state and out-of-range destinations never reach `on_page`. Previous,
next, and numbered controls all report through it. The current page is an
enabled button marked `current` (a disabled one is dimmed and announced as
unavailable by native backends); activating it reports nothing. Ellipses are
labels in this version, not clickable page-jump menus.

## Identity and state

Interactive components require a non-empty `id`. Internal actionable parts
reserve `${id}:component:` for their mounted IDs; application children must
not reuse that namespace. Each component reports through typed callbacks in its
config rather than action strings: tag `on_close`, alert `on_dismiss`, empty
state `on_action` and link `on_event` receive the click's `ElementEvent`;
collapsible `on_toggle` receives the open state asked for; breadcrumb
`on_navigate` receives the item key (an item's own `on_event` hears the click
first). A part whose callback is unset does not take the action, and a dismiss
or action button whose callback is unset is not drawn. Generated children are
anonymous where lookup is unnecessary. Each constructor checks the resulting
subtree with `validate_element_tree`; the renderer still validates the complete
tree.

Handle a disclosure or dismiss event in application state and rebuild. No
builder mutates a model or creates timers. Collapsible removes its body while
closed, so local native edits/focus in that body are not retained. Group-box
and collapsible children are positioned relative to their body, not the root.
Application-supplied child geometry is not automatically resized or clipped
by these builders beyond the existing backend's behavior.

Button text is centered in its frame on every backend, so give a link a frame
sized to its text. UI2 has no backend-neutral text measurement, so breadcrumb
items are sized from an estimate of their label width and packed from the
left, shrinking evenly when the trail does not fit.

Accessibility roles, labels, and current/expanded state are attached to the
resulting elements. This is metadata, not a claim of GPUI's AccessKit parity;
keyboard behavior and native accessibility mapping remain backend-dependent.
AppKit exposes `group`, `navigation`, `status` and `alert` as `AXGroup`,
`separator` as `AXSplitter` and `img` as `AXImage`.
Images use the existing image implementation: initials are chosen only when
`image_path` is empty, not after a load failure. Image masking also depends on
the backend. Skeletons do not shimmer; keyboard hints do not register shortcuts;
links never automatically launch a URL. Display strings are application-owned;
pagination's built-in accessibility strings are currently English.

These are V APIs. This migration does not add VML tags, compiled-VML lowering,
or C ABI constructors for the new components.

## Existing counterparts retained

UI2 already provides buttons, checkboxes, switches, sliders, text input,
dropdowns, progress bars, charts, accordion, carousel, tabbed panel, tree view,
menus, tooltips, retained overlays, animation, and several layout families.
They are retained rather than replaced by parallel implementations. These are
counterparts, not assertions that every GPUI option or interaction is present.
The existing `spinner` is a selection control, not a GPUI loading indicator.

## Parity tracker

The target is every component GPUI Kit documents (`website/component/*.md`,
80 pages). Status per page: **Done** — ported with its documented, portable
features; **Existing** — a ui2 component predating the port covers it, but its
options have not yet been compared with GPUI Kit's; **Partial** — some of it
exists; **Planned** — scheduled for the named batch. Per-group details live in
[`docs/gpui-kit/`](gpui-kit/).

| GPUI Kit | ui2 | Status | Notes |
| --- | --- | --- | --- |
| accordion | `accordion` | Existing | Feature audit pending |
| alert-dialog | `alert_dialog` | Done (batch 3) | Custom renderer; native `confirm` also exists; [dialogs](gpui-kit/dialogs.md) |
| alert | `inline_alert` | Done (batch 1) |  |
| attachment | — | Planned (batch 7) |  |
| avatar | `avatar` | Partial | Avatar group in batch 2 |
| badge | `badge` | Done (batch 1) |  |
| bubble | — | Planned (batch 7) |  |
| button | `styled_button`, `button_group`, `button` | Done (batch 2) | Variants and button group; [choice](gpui-kit/choice.md) |
| calendar | — | Planned (batch 4) |  |
| carousel | `carousel` | Existing | Feature audit pending |
| chart | `chart` | Partial | Line, bar, scatter, pie, doughnut; area, candlestick, radar, sankey, stacking in batch 9 |
| checkbox | `checkbox` | Existing | Feature audit pending |
| clipboard | `clipboard_button`, `copyable_text` | Done (batch 3) | [notifications](gpui-kit/notifications.md) |
| collapsible | `collapsible` | Done (batch 1) |  |
| color-picker | — | Planned (batch 4) |  |
| combobox | — | Planned (batch 5) |  |
| command | — | Planned (batch 5) |  |
| data-table | — | Planned (batch 5) |  |
| date-picker | — | Planned (batch 4) |  |
| description-list | `description_list` | Done (batch 1) |  |
| dialog | `modal_dialog`, `with_overlay` | Done (batch 3) | Custom renderer; [dialogs](gpui-kit/dialogs.md) |
| diff | — | Planned (batch 8) |  |
| dock | — | Planned (batch 6) |  |
| dropdown_button | `dropdown_button` | Done (batch 3) | [popovers](gpui-kit/popovers.md) |
| editor | `text_editor`, `text_area` | Partial | Code-editor features in batch 8 |
| empty | `empty_state` | Done (batch 1) |  |
| focus-trap | `focus_trap_next`, `FocusTrap` | Done (batch 3) | [dialogs](gpui-kit/dialogs.md) |
| form | — | Planned (batch 6) |  |
| group-box | `group_box` | Done (batch 1) |  |
| hover-card | `hover_card`, `HoverCardState` | Done (batch 3) | [popovers](gpui-kit/popovers.md) |
| icon | `named_icon`, `IconName`, `symbol:` images | Done (batch 2) | [feedback](gpui-kit/feedback.md) |
| image | `image` | Existing | Feature audit pending |
| index | — | Not applicable | Upstream documentation landing page |
| input-group | `input_group` | Done (batch 2) | [inputs](gpui-kit/inputs.md) |
| input | `text_input`, `input_group` | Done (batch 2) | Prefix, suffix and clear button through `input_group`; [inputs](gpui-kit/inputs.md) |
| kbd | `kbd` | Done (batch 1) |  |
| label | `label` | Existing |  |
| list | — | Planned (batch 5) |  |
| marker | — | Planned (batch 7) |  |
| menu | `dropdown_menu`, `set_menu_bar`, `Element.menu`, tray | Done (batch 3) | Dropdown/popup menus with submenus; [popovers](gpui-kit/popovers.md) |
| message-scroller | — | Planned (batch 7) |  |
| message | — | Planned (batch 7) |  |
| notification | `NotificationList`, `notification_stacks` | Done (batch 3) | [notifications](gpui-kit/notifications.md) |
| number-input | `number_input` | Done (batch 2) | [inputs](gpui-kit/inputs.md) |
| otp-input | `otp_input` | Done (batch 2) | [inputs](gpui-kit/inputs.md) |
| pagination | `pagination` | Done (batch 1) |  |
| plot | — | Planned (batch 9) |  |
| popover | `popover`, `popover_place` | Done (batch 3) | [popovers](gpui-kit/popovers.md) |
| progress | `progress_bar`, `linear_progress`, `progress_circle` | Done (batch 2) | [feedback](gpui-kit/feedback.md) |
| questionnaire | — | Planned (batch 7) |  |
| radio | `radio`, `radio_group` | Done (batch 2) | [choice](gpui-kit/choice.md) |
| rating | `rating` | Done (batch 2) | [choice](gpui-kit/choice.md) |
| resizable | — | Planned (batch 6) |  |
| root | `screen` | Not applicable | GPUI window root; ui2 builds a `screen` |
| scrollable | `scroll` | Existing |  |
| select | `dropdown`, `spinner` | Partial | Searchable select in batch 5 |
| settings | — | Planned (batch 6) |  |
| sheet | `sheet` | Done (batch 3) | [dialogs](gpui-kit/dialogs.md) |
| shimmer | `shimmer`, `shimmer_text` | Done (batch 2) | [feedback](gpui-kit/feedback.md) |
| sidebar | — | Planned (batch 6) |  |
| skeleton | `skeleton` | Done (batch 1) |  |
| slider | `slider` | Existing | Feature audit pending |
| speech | — | Planned (batch 7) | Needs platform speech recognition |
| spinner | `loading_spinner` | Done (batch 2) | `spinner` is ui2's selection control; [feedback](gpui-kit/feedback.md) |
| status-bar | — | Planned (batch 6) |  |
| stepper | `stepper` | Done (batch 2) | [choice](gpui-kit/choice.md) |
| switch | `switch_control` | Existing |  |
| table | — | Planned (batch 5) |  |
| tabs | `tabbed_panel` | Existing | Feature audit pending |
| tag | `tag` | Done (batch 1) |  |
| text-view | — | Planned (batch 8) | Markdown/HTML |
| textarea | `text_area` | Existing |  |
| theme | `ComponentTheme` | Partial | Light/dark tokens; theme registry later |
| time-field | — | Planned (batch 4) |  |
| title-bar | — | Planned (batch 6) |  |
| toggle | `toggle`, `toggle_group` | Done (batch 2) | [choice](gpui-kit/choice.md) |
| toolbar | — | Planned (batch 6) |  |
| tooltip | `with_tooltip` | Existing |  |
| tree | `tree_view` | Existing | Feature audit pending |
| virtual-list | — | Planned (batch 5) |  |

GPUI's application runtime, WebAssembly and JavaScript extension infrastructure
are not part of this port.

## Verification and gallery

With V 0.5.2+ and the repository's normal native dependencies installed:

Run these from the directory that contains the `ui2` checkout:

```sh
v test ui2/ui/component_catalog_test.v
v run ui2/examples/component_catalog/main.v
# macOS/Windows custom renderer:
v -d ui2_custom_rendering test ui2/ui/component_catalog_test.v
v -d ui2_custom_rendering run ui2/examples/component_catalog/main.v
```

The gallery exercises all 14 additions, themes, dismiss callbacks, disclosure,
breadcrumb navigation and pagination. The regression suite covers identity,
disabled and callback behavior, invalid and tiny geometry, Unicode initials,
page-window coverage and large totals. The existing CI matrix now runs that
suite and builds the gallery with the other examples.
Manual visual/keyboard/screen-reader testing is still required on each backend.
