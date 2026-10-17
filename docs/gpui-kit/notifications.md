# Notifications and clipboard

Ports of GPUI Kit's [notification](https://github.com/longbridge/gpui-kit/blob/main/website/component/notification.md)
and [clipboard](https://github.com/longbridge/gpui-kit/blob/main/website/component/clipboard.md)
pages, compared with GPUI Kit `main` at `f8cf0bd964f9ef2e5b7be79f3a8fc391371feb4a`.
The gallery is `examples/gpui_notifications`.

Both are new V implementations of the documented behavior; no GPUI Kit code was
translated. Like every ported component they are controlled: the application
owns the state, builds never change it, and each part reports to a typed
callback in its config.

## Notification

GPUI Kit keeps a `NotificationList` inside the window's `Root` and pushes into
it with `window.push_notification`. In ui2 the application owns a
`NotificationList` value and draws it with `notification_stacks`. Every change
to the list returns the timers it needs as `[]NotificationTimer` data, which
`list.schedule(timers)` turns into `after`/`cancel_timer` calls; when a
timer is due it is fed back to `list.fire(timer)`. The list itself never
starts a timer, so it is deterministic and is tested with a fake clock.

### API

| Item | Purpose |
| --- | --- |
| `Notification` | `key`, `kind`, `title`, `message`, `icon`, `action`, `clickable`, `autohide ?bool`, `duration`, `placement`, `content`/`content_height` |
| `NotificationKind` | `plain` (no icon), `info`, `success`, `warning`, `error` |
| `NotificationPlacement` | `inherit`, `top_left`, `top_center`, `top_right`, `left_center`, `right_center`, `bottom_left`, `bottom_center`, `bottom_right` |
| `NotificationList` | Settings `placement` (default `top_right`), `max_visible` (10), `enter_duration` (0.4 s), `exit_duration` (0.2 s), `clock` |
| `list.push(n)` | Adds the newest notification; a `key` already in the list is replaced |
| `list.dismiss(seq)`, `list.dismiss_key(key)`, `list.clear()` | Start the slide out (GPUI Kit's dismiss, `remove_notification`, `clear_notifications`) |
| `list.pause(placement)`, `list.resume(placement)` | Stop and restart every countdown, keeping the time left |
| `list.settle()` | Finish every slide in now, for notifications already on screen when a window opens |
| `list.fire(timer)` | Advance the notification a due timer belongs to; stale timers change nothing |
| `list.schedule(timers)` | Run timer requests with `after`/`cancel_timer` |
| `list.entries()`, `list.visible()`, `list.find(key)`, `list.remaining(seq)`, `list.is_paused()`, `list.len()` | Read the list |
| `notification_stacks(NotificationStackConfig) ![]Element` | One stack per placement in use |
| `NotificationEvent` | `kind` (`close`, `action`, `click`, `hover_start`, `hover_end`), `seq`, `key`, `placement`: what `on_notification` receives |
| `list.respond(event)` | GPUI Kit's built-in responses: close, action and click dismiss; hover pauses |

`NotificationStackConfig` has `id`, `frame` (usually `ui2.bounds()`), `list`,
`width` (382, GPUI Kit's), `margin` (16), `gap` (12), `animate` (true), `size`,
`theme` and `on_notification fn (NotificationEvent)`. `notification_stacks` returns a list rather than one element:
each stack is only as large as its notifications, so the rest of the window
stays clickable and hoverable on AppKit and Windows, where a transparent view
covering the window would take every click. Append the stacks after the other
children so they are drawn on top.

### Example

```v
@[heap]
struct App {
mut:
	notes ui2.NotificationList
}

const app = &App{}

fn build() ui2.Element {
	state := unsafe { app }
	theme := ui2.component_theme(false)
	mut children := []ui2.Element{}
	children << ui2.with_event(ui2.button('save', 'Save', ui2.rect(20, 20, 120, 32), ui2.BoxStyle{},
		ui2.TextStyle{}), save)
	// Last, so the stacks draw on top.
	children << ui2.notification_stacks(
		id:              'toasts'
		frame:           ui2.bounds()
		list:            state.notes
		theme:           theme
		on_notification: answer_notification
	) or { panic(err) }
	return ui2.screen(theme.background, children)
}

fn answer_notification(note ui2.NotificationEvent) {
	mut state := unsafe { app }
	if note.kind == .action && note.key == 'connection' {
		// Retry here.
	}
	state.notes.schedule(state.notes.respond(note))
	ui2.request_refresh()
}

fn save(event ui2.ElementEvent) {
	mut state := unsafe { app }
	state.notes.schedule(state.notes.push(
		kind:    .success
		title:   'Saved'
		message: 'Your changes have been saved.'
	))
	ui2.request_refresh()
}
```

A failed connection with a retry button that stays until it is handled, and an
upload whose notification is replaced when it finishes:

```v
state.notes.schedule(state.notes.push(
	key:     'connection'
	kind:    .error
	title:   'Connection lost'
	message: 'Unable to connect to the server.'
	action:  'Retry' // An action turns auto-hide off unless autohide says otherwise.
))
state.notes.schedule(state.notes.push(key: 'upload', kind: .info, message: 'Uploading…', autohide: false))
// Later: same key, so it replaces the first one.
state.notes.schedule(state.notes.push(key: 'upload', kind: .success, message: 'Uploaded'))
```

Keep the list in heap-allocated state (as above): `schedule` hands its address
to the timers it starts. Call `schedule` from a callback or a timer, never from
a build.

### Behavior

- Order and limits. The list is oldest first. Stacks put the newest
  notification nearest the edge they grow from: at the top of a top or
  side-centered stack, at the bottom of a bottom stack. `visible()` is the
  newest `max_visible` notifications plus every one still sliding out, as GPUI
  Kit's `ToastManager::visible`; the rest wait, still counting down.
- Auto-hide. A notification hides itself after `duration` seconds (default 5)
  unless `autohide` is false, or it has an `action` and `autohide` is unset.
  Like GPUI Kit, the countdown starts once the slide in is over.
- Pause. The stacks report `.pointer_enter`/`.pointer_leave` hover events as
  `.hover_start`/`.hover_end`; while any stack is
  hovered every countdown stops and keeps its time left (GPUI Kit pauses all of
  them while its stacks are expanded). A stack that disappears under the
  pointer releases its pause even if no leave event arrives.
- Phases. A notification is `entering`, `present` or `leaving`, after GPUI
  Kit's toast transition status, and is dropped once its exit timer fires.
- Motion. Entering notifications slide in from just past the edge their stack
  grows from (sideways for the side-centered placements), all of a stack's
  arrivals by one distance so they move together; leaving ones slide out
  sideways. The card moves inside its slot and the slot inside the stack, along
  axes whose declared offset is otherwise zero, with the cards' and slots' own
  [motion](../motion.md), which ends with their elements. `animate: false`
  turns it off, as do renderers without motion.
- Callbacks. Each part's callback is computed from the list the stacks were
  built from: a notification that is leaving has none, a part it does not have
  (an action on one without, a click on one that is not clickable) is not
  built or not clickable, and a hover change the list already reflects is not
  reported.
- Icons. The kinds use SF Symbols `info.circle`, `checkmark.circle`,
  `exclamationmark.triangle` and `xmark.circle`, after GPUI Kit's Lucide icons.
  Only `info.circle` is in the portable symbol table today, so until all four
  are, every kind is drawn as a ring holding `i`, `✓`, `!` or `✕` in the kind's
  color, which looks the same on every renderer. `icon` takes any symbol name.
- Accessibility. Cards are `status`, or `alert` for warnings and errors, named
  by their title and message; a clickable card is a `button`. Stacks are
  `group`s named "Notifications"; the close button is "Dismiss notification".

### Implemented and omitted

| GPUI Kit feature | ui2 |
| --- | --- |
| Message, title, types with icons, custom icon | Implemented |
| Auto-hide after 5 s, `autohide(false)`, action disables auto-hide | Implemented; `duration` is configurable |
| Pause while hovered | Implemented for every stack, as in GPUI Kit |
| Pause while a notification has keyboard focus | Omitted: components cannot observe focus |
| Placement, global default and per notification, stacked separately | Implemented, all eight anchors |
| `max_items` | `max_visible` |
| Action button | Implemented as a title; `on_notification` receives `.action` |
| `on_click` (click dismisses and reports) | `clickable`; `respond` dismisses |
| `on_close` callback | `on_notification` receives `.close`; the application sees every other dismissal it starts, and `find(key)` tells whether a notification is still there |
| Unique ids (`id::<T>()`, `id1`) and `remove_notification` | `key`, replacing on push, and `dismiss_key` |
| `clear_notifications` | `clear` |
| Custom content builder | `content` elements in a `content_height` box below the message |
| Enter/exit animation (slide and fade) | Slide only |
| Collapsed Sonner-style stack that expands on hover | Omitted: notifications are always listed; expanding on hover would move cards under the pointer without the springs GPUI Kit animates them with |
| Close button shown on hover only | Always shown: touch backends have no hover, and a hidden control is hard to discover |
| Middle-click to dismiss | Omitted: ui2 reports no auxiliary clicks |
| Shadow | Omitted: ui2 boxes have no shadow; the card has a border |
| System notifications (`NotificationDelivery`) | Omitted: ui2 has no OS notification API |
| `margins`, `width` settings | `margin` and `width` on `NotificationStackConfig` |

## Clipboard

`clipboard_button` is GPUI Kit's `Clipboard`: a ghost button with a copy icon
that turns into a check mark after copying. Building it never touches the
clipboard; a press calls `on_copy` and the application copies the current
value there (GPUI Kit's `value`/`value_fn`), then shows the copied state, which
ui2 leaves to application state.

| Item | Purpose |
| --- | --- |
| `clipboard_button(ClipboardButtonConfig) !Element` | Icon-only, or with `label` an outlined button reading `label` then `copied_label` |
| `copyable_text(CopyableTextConfig) !Element` | A read-only value with a copy button at its end |
| `set_clipboard_text(value) bool` | Copies `value` to the system clipboard; reports success |
| `ClipboardFeedback` | `copy(id, value)`, `show(id)`, `copied(id)`: the copied state for `duration` seconds (2, GPUI Kit's) through `after` |

`ClipboardButtonConfig` has `id`, `frame`, `label`, `copied_label`, `copied`,
`supported`, `hide_unsupported`, `enabled`, `tooltip`, `accessibility_label`,
`size` (default `.small`), `theme` and `on_copy fn ()`. `CopyableTextConfig` has
`id`, `frame`, `text`, `copied`, `supported`, `monospace`, `enabled`,
`tooltip`, `accessibility_label`, `size`, `theme` and `on_copy`. A disabled or
unsupported button has no callback.

```v
@[heap]
struct App {
mut:
	clips ui2.ClipboardFeedback
	notes ui2.NotificationList
}

const app = &App{}
const clipboard_ok = ui2.clipboard_supported() // Cache it: on Linux it searches PATH.

fn build() ui2.Element {
	state := unsafe { app }
	return ui2.screen(0xffffff, [
		ui2.copyable_text(
			id:                  'api-key'
			frame:               ui2.rect(20, 20, 300, 36)
			text:                'sk-1234567890abcdef'
			monospace:           true
			copied:              state.clips.copied('api-key')
			supported:           clipboard_ok
			accessibility_label: 'Copy API key'
			on_copy:             copy_api_key
		) or { panic(err) },
	])
}

fn copy_api_key() {
	mut state := unsafe { app }
	if state.clips.copy('api-key', 'sk-1234567890abcdef') {
		// GPUI Kit's on_copied: here, a notification.
		state.notes.schedule(state.notes.push(kind: .success, message: 'API key copied'))
		ui2.request_refresh()
	}
}
```

### Implemented and omitted

| GPUI Kit feature | ui2 |
| --- | --- |
| Copy icon, check icon after copying, for 2 s | Implemented through `ClipboardFeedback`; `copied` is controlled |
| `value` and `value_fn` | The value is read in `on_copy`, so it is always current |
| `on_copied` | `ClipboardFeedback.copy` returns true; react in `on_copy` |
| Localized "Copy" accessible name, `accessibility_label` | Implemented (English default) |
| `tooltip` | Implemented; `tooltip_show_delay` omitted (the backend owns the delay) |
| Sizes | `ComponentSize`, default `.small` (GPUI Kit's default is XSmall) |
| Clicking while copied does nothing | Copying again re-copies and restarts the feedback, so a value that changed can be copied without waiting |
| Label beside the icon, input suffix (documented compositions) | `label` variant and `copyable_text` |
| Platforms without a clipboard | `supported: false` disables the button with a tooltip, or `hide_unsupported` hides it |

The check icon uses the SF Symbol `checkmark` when every renderer has it and
the `✓` character until then; the copy icon is `doc.on.doc`.
