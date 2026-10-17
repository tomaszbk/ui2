# ui2

<img width="1508" height="1043" alt="image" src="https://github.com/user-attachments/assets/fb335b0a-ea55-4c66-8e69-b700f0a402d9" />


<img height="280" alt="image" src="https://github.com/user-attachments/assets/0fb17bf1-ba64-4d70-bba9-76e08069e009" />


`ui2` is a compact declarative UI module for V. It uses retained native controls
on macOS, iOS, and Windows and a custom immediate-mode `gg` renderer on Linux
and Android.

The Linux backend draws and handles widgets directly through `gg`/Sokol; it has
no GTK dependency.

The V API includes responsive Flex and Grid placement with intrinsic text
measurement. See the [layout guide](docs/modern-layout.md) and
[responsive example](examples/responsive_layout/main.v).

You can also build desktop ui2 apps in C or any language with a C FFI. Build
the shared library and the C counter with `make c-example`; the standalone
header is [`c/ui2.h`](c/ui2.h). See the [C API guide](c/README.md) for the build
callback, widget constructors, state access, ownership rules, and a Python
`ctypes` example. Application code needs no V compiler once the library is built.

macOS and Windows use native widgets by default. Pass the compile-time define
`-d ui2_custom_rendering` to use the same custom `gg` renderer there instead:

```sh
v -b c -d ui2_custom_rendering run examples/users/main.v
```

The custom renderer builds on demand. Model changes outside VML handlers
require `request_refresh()`; timers and deadlines must request
updates when external state changes. Workers can post changes through a captured
`ui2.ui_dispatcher()`. Idle drawing currently stops on macOS Metal. GL/EGL/D3D
reuse the declared tree but still repaint because Sokol presents every callback.
See [scheduling and diagnostics](docs/custom-rendering-scheduler.md).
For Windows custom setup, retained D3D presentation and the typecheck
verification scope, see [Windows custom runtime](docs/windows-custom-runtime.md)
and `examples/windows_custom_runtime`.

The custom renderer also supports retained [vector canvases](docs/vector-canvas.md):
typed paths, quadratic/cubic Bézier curves, concave polygons and holes, stroked
caps/joins and shape-based pointer hits. See `examples/vector_canvas`.

Custom windows support [typed drag sources, drop targets and previews](docs/drag-drop.md).
Run `v -b c -d ui2_custom_rendering run examples/drag_drop` to try the interaction.

Custom rendering supports retained [motion](docs/motion.md): entry and exit,
transitions of opacity, transforms and paint, layout transitions, keyframe
timelines, events, handles, reduced motion and controlled clocks. Run
`v -b c -d ui2_custom_rendering run examples/motion_presence` or
`examples/transitions` to try it.

Custom windows support retained [overlays](docs/overlays.md): Dialog, Popover,
MenuOverlay, ContextMenu and Tooltip, with controlled open state, focus
containment and anchored placement. Run
`v -b c -d ui2_custom_rendering run examples/overlays` to try all five.

On macOS, the experimental owned embedder adds native windows, Metal surfaces,
IME composition and a blocking event loop. Enable it with both
`-d ui2_custom_rendering -d ui2_embedder` for idle sleep.
`open_window`/`run_windows` support independent windows with scoped
updates and dispatchers. See [the embedder contract and acceptance tests](docs/custom-embedder.md).

## Requirements

`ui2` needs the `tomaszbk/v` compiler revision pinned in
[`scripts/v-pin.env`](scripts/v-pin.env); the V release binaries do not compile
it yet. Build that compiler with:

```sh
scripts/setup-v.sh            # installs into ~/.local/share/ui2-v
export PATH="$HOME/.local/share/ui2-v:$PATH"
```

CI builds the same pin through [the shared setup action](.github/actions/setup-v/action.yml).
The module is split across `ui/`, `appkit/`, `uikit/` and `windows/` through
the `subdirs` field of `v.mod`.

Build and run ui2 with V's C backend (`v -b c ...`), including the designer
and its shared preview libraries.

Custom desktop builds also need Pango 1.50+, FreeType and their text-library
dependencies. The vglyph runtime is included in the repository. See
[custom desktop text setup](docs/vglyph-text.md) for macOS, Linux and Windows
installation, linking and distribution. Native, Android and headless builds
retain their existing dependencies.

To use `ui2` from a project outside this repository, link the clone into
`~/.vmodules`:

```sh
ln -s "$(pwd)" ~/.vmodules/ui2
```

## State and identity

- `Element.id` identifies a mounted control for `text`, `set_text`, `focus`, and
  other lookup APIs.
- `Element.key` identifies a child during reconciliation. Keys must be unique
  among siblings; IDs must be unique in the tree. Renderers validate both before
  changing native state.
- `Element.on_event` is a typed callback attached to that element.
  `ElementEvent.id` identifies its source; ids never select a callback.
  Attach callbacks with `with_event(element, callback)` or a control config.

Callbacks receive the event kind, committed text/value/checked state and logical
pointer coordinates. Scroll notifications use `.scroll`, with the vertical
logical offset in `value`; VML declares them with `on_scroll`.

Text inputs use controlled-on-change semantics: changing the declared `text`
applies that value, while a refresh with the same declaration preserves the
current native/local edit, selection, focus, and (on native controls) input
method composition. Use `set_text` for an explicit imperative replacement.

Compiled VML `text` declarations accept strings and numbers without explicit
interpolation: `Label(text: app.count)` displays a numeric field, and
`Label(text: app.count + 1)` displays a numeric expression. Strings pass through
unchanged; numbers use V's `.str()` formatting, selected at compile time.
Use interpolation for combined captions such as `"Count: ${app.count}"`.
`bind.text` remains string-typed for editor writeback, and other properties and
expressions keep their normal V types.

Explicit typed sources, lazy computed values, effects, batching and lifetime
cleanup are available through the window-independent signals runtime. See
[the signals API](docs/signals.md) and [the runnable example](examples/signals/main.v).
Ordinary V assignments require explicit observable setters to notify this graph.

The custom renderer builds on demand and reuses its tree while idle. See
[render scheduling](docs/render-scheduling.md) for invalidation, worker delivery,
window lifecycle and the acceptance fixture.

## Motion

Motion is the one animation system: an element's `motion` configuration is
retained with the element by the custom renderer, which draws frames only while
something moves. Compose it from `motion_<name>` pieces, as styles compose from
`style_<name>` pieces:

```v
tile := ui2.with_motion(ui2.view('tile', ui2.rect(app.x, app.y, 82, 82),
	ui2.BoxStyle{ bg: app.color, radius: 14 }, []ui2.Element{}), ui2.compose_motion([
	ui2.motion_fade(0.2),
	ui2.motion_layout(.position), // a new x or y slides there
	ui2.motion_transition(0.75),
	ui2.motion_easing(.in_out_cubic), // a new color fades the same way
	ui2.motion_on(fn [mut app] (event ui2.MotionEvent) {
		if event.source == .layout && event.kind == .complete {
			app.status = 'Arrived'
		}
	}),
]))
```

Keyframe timelines loop, sequence and run in parallel, on the element or on
descendants named by id. In VML a `Timeline` part declares one:

```vml
View(id: "card", motion: app.card_motion()) {
    Image(id: "logo", width: 48, height: 48, source: "logo.png")
    Timeline(duration: 1.2, repeat: true) {
        Keyframe(target: "logo", at: 0.5, opacity: 0.4, scale: 1.1, easing: in_out_sine)
        Keyframe(target: "logo", at: 1, opacity: 1, scale: 1)
    }
}
```

`MotionHandle` cancels, finishes or restarts an element's motion, and
`set_reduced_motion(true)` stills every element for accessibility. See
[motion](docs/motion.md) for layout modes, easing curves and springs, events
and the allocation-free frame contract.

## Compiled VML

VML files compile to typed V constructors through `$vml`; parsing and type errors
are reported against the source file at compile time. The window runner borrows
the application model by reference, exposed as `app`:

```v
fn build(mut app App) ui2.Element {
    return $vml('app.vml')
}

fn main() {
    ui2.run_compiled_vml[App](
        model: &App{}
        build: build
        title: 'My app'
        width: 780
        height: 420
    )!
}
```

For embedding and independent geometry fixtures, `$vml('app.vml', frame)` accepts
an explicit logical `Rect`. Imports are resolved relative to their declaring VML
file during compilation; VML sources are not required beside the built executable.

Ordinary properties read values. `bind.text` and `bind.checked` also write control
edits to a writable source before invoking that event's handler. Numeric editing
requires explicit conversion to a string; display `text` accepts strings and numbers.

```vml
TextInput(bind.text: app.name)
Button(text: "Add", enabled: app.users.len < app.max_users, on_click: app.add_user())
```

Built-in callbacks may take no arguments or one `ui2.ElementEvent` and return
`void`. Explicit calls and assignments run only when the selected event occurs.
IDs identify controls; they never select or imply an event handler. Output events
from components carry their declared payload, accept a matching callback or a
callback with no parameters, and are safe to emit without a listener.

```vml
Repeater(model: app.users, key: item.id) {
    Label(text: "${item.name}")
}
```

A repeater's key identifies siblings independently of position. `item` and `index`
are scoped to each item, and callbacks retain the rendered item's identity.
Application services and business logic can remain in `.v` files.

Presentation uses typed style values:

```vml
style card = [background(color.surface), padding(12), radius(8)]

View(style: [card, background(color.accent)]) {
    Label(text: "Content")
}
```

Lists compose from left to right; a local override replaces only the supplied
properties. Inline lists and component-local declarations use the same rules.
See [VML styles and themes](docs/vml-styles.md) for tokens, variants, interaction
states and theme updates.

## Custom buttons

A `Button` can be styled directly in VML. Leave `native` unset when the
application should own its colors and shape; `native: true` requests the
standard native-style appearance instead.

```vml
Absolute(
    style: [transparent(true)],
) {
    Button(
        id: "save",
        text: "Save",
        on_click: app.save(),
        x: 20,
        y: 20,
        width: 120,
        height: 40,
        style: [background(#2563EB), border_color(#1D4ED8), border_width(1), radius(8), foreground(#FFFFFF), weight(700)],
    )
}
```

When the button needs arbitrary content rather than a single caption, compose
it from a `View` and opt the container into button activation
with `button_behavior: true`. The whole rectangle is the activation target;
noninteractive children such as its `Label` do not block the tap:

```vml
Absolute(
    style: [transparent(true)],
) {
    View(
        id: "save_card",
        button_behavior: true,
        on_click: app.save(),
        x: 20,
        y: 20,
        width: 180,
        height: 56,
        cursor: "pointing_hand",
        style: [background(#2563EB), radius(8)],
    ) {
        Absolute(
            style: [transparent(true)],
        ) {
            Label(text: "Save changes", x: 16, y: 16, width: 148, height: 24, style: [text_align(center), foreground(#FFFFFF), weight(700)])
        }
    }
}
```

`button_behavior` emits the ordinary `on_click` action once when a press starts
on the element and is released inside without becoming a drag or scroll
gesture. It also gives the composite the default accessibility role `button`
and derives its accessibility label from the first visible, noninteractive
descendant with a label or text; set `accessibility_role` or
`accessibility_label` explicitly to override those defaults.

This adds activation semantics without requesting a native bezel or pressed
visuals—the rectangle and its children remain application-drawn. The native
Windows backend exposes the composite as a focusable button to accessibility
tools and supports Enter/Space activation; the other renderers do not add
native keyboard focus treatment. Use `Button` when a platform-drawn bezel and
pressed state are required.

This is deliberately separate from `clickable: true`. A clickable view is a
low-level pointer surface that reports typed `.pointer_down`, `.pointer_drag`
and `.pointer_up` events (and can be combined with `draggable`) for code that needs coordinates
or gesture phases. Use `button_behavior` for a normal action-bearing composite
control. If both flags are set, the surface emits the raw pointer phases and
then its ordinary action after a successful tap.

Reusable VML controls declare their inputs and output events in a component
signature. Each instance owns its state; `computed` declares a pure lazy memo.
Inputs are read-only. A writable port uses `bind` in its signature and an explicit
`bind.name` connection at the call site.

```vml
component Counter(title string = "Count", changed event(value int)) {
    state count := 0
    computed doubled := count * 2

    fn increment() {
        count++
        changed(count)
    }

    Column {
        Label(text: "${title}: ${count} / ${doubled}")
        Button(text: "Add", on_click: increment)
    }
}
```

The application imports it from `counter.vml`:

```vml
import Counter
Screen {
    Counter(title: "First")
    Counter(title: "Second")
}
```

Members are referenced directly inside the component. `app` is reserved for the
application model. Local members and control IDs cannot shadow each other.
State initializers run once per instance, while a local editable copy initialized
from an input retains its own edits when that input changes.
See [compiled components, bindings, lifetime, slots and refs](docs/vml-components.md)
for the complete contracts.

In V code, the equivalent reusable control is an ordinary function returning
an `Element`:

```v
fn primary_button(id string, title string, frame ui2.Rect) ui2.Element {
    return ui2.button(
        id,
        title,
        frame,
        ui2.BoxStyle{
            bg: 0x2563eb
            radius: 8
            border_color: 0x1d4ed8
            border_left: 1
            border_top: 1
            border_right: 1
            border_bottom: 1
        },
        ui2.TextStyle{
            color: 0xffffff
            bold: true
        },
    )
}
```

A button invokes its attached `ElementCallback`. Use `with_event` to attach a
callback; `button_with_image`, `with_tooltip`, and `with_native_style` can be
composed in the same way.

For arbitrary child elements, use `button_view` instead. Child frames are
relative to the view, just as they are for an ordinary `view`:

```v
fn save_card(id string, on_save ui2.ElementCallback, frame ui2.Rect) ui2.Element {
    caption := ui2.label(
        '${id}_caption',
        'Save changes',
        ui2.rect(16, 16, frame.width - 32, 24),
        ui2.TextStyle{ color: 0xffffff, bold: true, align: .center },
    )
    return ui2.with_event(
        ui2.button_view(
            id,
            frame,
            ui2.BoxStyle{ bg: 0x2563eb, radius: 8 },
            [caption],
        ),
        on_save,
    )
}
```

`with_button_behavior(existing_view)` is the modifier form when the composite
already exists. `button_view` and `with_button_behavior` leave the raw
`clickable` flag unset.

### Hover

`hoverable: true` (or `ui2.with_hover(el)`) makes an element with an
`on_event` callback receive `.pointer_enter` when the pointer comes over it and
`.pointer_leave` when it goes, so a hover card can open or a row can highlight.
The event carries the element's id and the pointer position in logical window
coordinates.

Hover follows the CSS `:hover` rule on AppKit, Windows and the custom renderer
alike: an element is hovered while the topmost element under the pointer is it
or one of its descendants. Moving onto a child keeps its hoverable ancestors
hovered, an element covered by another one is not hovered, and hover is checked
again after every render, so content moving under a still pointer is reported
too. Leaves are reported innermost first and enters outermost first. Touch
platforms (iOS, Android) have no hover.

## Box effects

`BoxStyle` can fade, shade and color a box beyond its solid `bg`:

```v
card := ui2.view('card', ui2.rect(20, 20, 280, 160), ui2.BoxStyle{
	bg:     0xffffff
	radius: 12
	shadow: ui2.box_shadow(0x000000, 0.18, 24, 8) // color, opacity, blur, y offset
}, children)

backdrop := ui2.view('backdrop', ui2.rect(0, 0, w, h), ui2.BoxStyle{
	bg:      0x000000
	opacity: 0.4 // the fill only; borders and children keep theirs
}, [])

banner := ui2.view('banner', ui2.rect(0, 0, w, 120), ui2.BoxStyle{
	gradient: ui2.linear_gradient(90, ui2.gradient_stop(0x2563eb, 0),
		ui2.gradient_stop(0x9333ea, 1))
}, [])
```

- `opacity` (0 to 1) fades the fill and nothing else.
- `gradient` replaces `bg` on a view with a linear gradient: `angle` in degrees
  (0 runs left to right, 90 top to bottom) and two or more stops, each with a
  position from 0 to 1 and an optional opacity. Like CSS `linear-gradient`, it
  spans the box corner to corner along its angle. Buttons keep their solid fill
  (a native button draws its title beneath any gradient layer); make a gradient
  button from a view with `button_behavior`.
- `shadow` draws a drop shadow beneath the box: `color`, `opacity`, `blur`,
  offset `x`/`y` and `spread`, as in CSS `box-shadow`. A box that casts a shadow
  does not clip its children to its rounded corners on AppKit and UIKit, since a
  layer masking to its bounds masks its shadow away too.

A shadow animates with [motion](docs/motion.md), as do the element's opacity and
fill color. AppKit and UIKit use CoreAnimation (`NSShadow`/layer shadows and a
`CAGradientLayer`), and the custom renderer draws them itself. Windows draws
fill opacity and gradients with `AlphaBlend` and `GradientFill`, but not a
gradient's per-stop opacity, and it draws no shadows: Win32 child windows cannot
paint outside themselves. Screenshots taken with `UI2_SCREENSHOT_PATH` on AppKit
do not show CoreAnimation shadows, which `cacheDisplayInRect:` does not render.

## Backend capabilities

Call `control_support(kind)` to query support. macOS implements every shared
control kind; native images are `partial` because quad interaction and advanced
presentation require custom rendering. iOS likewise reports images as `partial`,
with text areas reported as `partial`
because rich runs are currently rendered as plain text. Linux, Android, and
opt-in custom desktop builds implement every kind through custom rendering;
dropdowns and text areas are `partial` because the dropdown list is drawn by
the renderer instead of a native menu and rich text-area runs are rendered as
plain text.

A button marked `native` asks the platform for the standard bezel and hands it
the interaction styling. AppKit and Win32 supply theirs; the custom renderer
draws one, including a pressed shade while the pointer is held on it, so the
button does not come out as a bare caption. A button the application gave its
own background keeps it, since the platform styling stops where the
application's own begins.

Box-backed elements (`View`, `Button`, `Scroll`, `Dropdown`,
`TextInput`, `TextArea`) can draw each border edge independently. Widths use
the same logical units as frames and corner radii, so native and custom
renderers scale them with the rest of the element:

```vml
View(style: [background(#10131F), border_color(#28314A), border_left(1), border_top(1), border_right(1), border_bottom(0)])
```

Use `style: [transparent(true)]` to omit a box's fill. It also works on the root
`Screen`; a transparent screen reveals the desktop when its native host window
is configured for transparency, as demonstrated by `examples/custom_window`.

`border_width(1)` supplies all four edges; a later helper such as
`border_bottom(0)` overrides that edge. The equivalent V API fields live
directly on `BoxStyle`.

Images load from `image_path` on every backend. The custom renderer caches
decoded images. Scroll viewports clip both drawing and hit testing.

The Windows backend uses retained Win32 `BUTTON`, `EDIT`, `COMBOBOX`, `STATIC`,
and custom container windows. Its image control currently loads BMP files and
its text area is plain-text, so those two controls report `partial` support.

Shared state includes `hidden`, `enabled`, `accessibility_role`,
`accessibility_label`, and `accessibility_value`. Native backends expose these
through AppKit/UIKit. Roles use ARIA names (`button`, `checkbox`, `tab`,
`progressbar`, `navigation`, …); AppKit maps them onto its own roles, passes
`AX…` roles through unchanged, and leaves a view's native role in place for a
name it has no role for. Standard Windows controls expose their native name and
value; `button_behavior` views also expose a native button role, generated
label, keyboard focus, and accessibility activation. Other explicit Windows
accessibility role/value overrides are not yet implemented.
`autocorrect` and `padding_left` configure applicable mobile text inputs.

## Visual IDE

UI2 Studio in [`ide/`](ide/) is a Delphi/Lazarus-style WYSIWYG form designer
written in V with UI2 itself. It includes a component palette, draggable and
resizable controls, object tree and inspector, undo/redo, VML source editing,
live preview, project save/open, `main.v` generation, and a build messages pane.

```sh
v -b c run ide
```

See [`ide/README.md`](ide/README.md) for the supported visual document shape
and workflow.

## Message boxes

`message_box(...)` shows the operating system's own modal alert and blocks until
the user answers it:

```v
choice := ui2.message_box(
	title:   'Save changes?'
	text:    'The document has unsaved edits.'
	style:   .question
	buttons: .yes_no_cancel
)
```

`title` is the short heading and `text` the body. macOS renders them as an
`NSAlert` message and informative text, Windows as a `MessageBoxW` caption and
body, and Linux as the desktop's own `zenity` or `kdialog` dialog — `kdialog`
first under KDE and Plasma. iOS presents a `UIAlertController` and pumps the run
loop so the call stays synchronous like the desktop backends. `alert(title,
text)` and `confirm(title, text)` wrap the two common cases.

Android has no alert this layer can drive without a JVM callback, so
`message_box_supported()` returns `false` there and `message_box` answers as if
the dialog had been dismissed. Dismissal always reports the non-destructive
result: `cancel` where the button set has one, otherwise `no`, or `ok` for a
single-button alert.

`custom_message_box(...)` is the separate, hand-drawn alternative: a dimmed
overlay with a rounded card that stays inside the window and never blocks. Flip
its `hidden` field from the button events instead of reading a return value. It
is also available from VML as `MessageBox`, whose `Button` children become the
card's actions:

```vml
MessageBox(
    id: "overlay",
    hidden: ! app.visible,
    title: "Hello World",
    text: "This message came from the ui example.",
) {
    Button(id: "close_message", text: "OK", on_click: app.close_message())
}
```

## Window chrome

`set_window_chrome(.hidden_titlebar)` lets the application draw its own title
bar: content runs to the top edge of the window. macOS keeps its close,
minimize and zoom buttons over the content's leading corner
(`window_controls_leading_inset()` is how much room they take); Windows removes
the caption but keeps the resizable border, and `window_draws_own_controls()`
says the application draws the window buttons.

```v
titlebar := ui2.Element{
	...ui2.view('titlebar', ui2.rect(0, 0, width, 36), ui2.BoxStyle{ bg: 0xf4f4f5 }, [])
	clickable: true
	on_event:  fn (event ui2.ElementEvent) {
		if event.kind == .pointer_down {
			ui2.start_window_drag() // the platform moves the window
		}
	}
}
close := ui2.with_event(ui2.button('close', '×', ui2.rect(width - 40, 0, 40, 36),
	ui2.BoxStyle{}, ui2.TextStyle{}), fn (event ui2.ElementEvent) {
	if event.kind == .click {
		ui2.quit()
	}
})
```

`start_window_drag` only works while a press is being handled, so give the
title bar `clickable: true` (or `draggable`) and call it on `.pointer_down`.
`minimize_window` and `toggle_maximize_window` go behind the other buttons'
callbacks the same way.
`window_is_maximized` tells a maximize button which icon to show. These work
for native and custom-rendered windows on macOS and Windows; Linux, Android and
iOS keep their own frame and the calls report false.

## Timers

`after` runs a callback on the UI thread once a delay has passed and then
rebuilds the window, so a notification can dismiss itself or a search can
debounce without the application owning a thread:

```v
toast := ui2.after(4, fn [mut app] () {
	app.toast_visible = false
})
ui2.cancel_timer(toast) // call it off, e.g. when the user dismisses it first
```

Callbacks run on the UI thread just before the window's next build, so
whatever they change is in the tree that build declares. `timer_pending(id)` reports whether a callback has yet to
run. A negative or non-finite delay runs at the next build.

## Clipboard

`set_clipboard_text` replaces the system clipboard with plain text and
`clipboard_text` reads it back (`none` when it holds no text). Text fields
keep their own copy and paste; these are for copying anything else, such as
the contents of a code block.

```v
if !ui2.set_clipboard_text(token) {
	// no clipboard this platform can reach
}
pasted := ui2.clipboard_text() or { '' }
```

macOS uses `NSPasteboard`, iOS `UIPasteboard` and Windows the Win32 clipboard,
for native and custom-rendered windows alike. Linux drives `wl-copy`/`wl-paste`
under Wayland, or `xclip` or `xsel` under X11, so one of them has to be
installed; Android has no clipboard this layer can reach. Check
`clipboard_supported()` before offering a copy action.

## File and folder dialogs

`open_file_dialog`, `save_file_dialog`, and `open_folder_dialog` show the
operating system picker and return the selected absolute paths. They block while
the picker is open; cancellation is an empty array. `open_file_dialog` can
return several paths when `multiple: true`.

```v
paths := ui2.open_file_dialog(
	title: 'Open a V source file'
	directory: '/work/project'
	filters: [ui2.FileDialogFilter{
		name: 'V source'
		extensions: ['v', 'vv']
	}]
)
if paths.len > 0 {
	println('Opening ${paths[0]}')
}

destination := ui2.save_file_dialog(
	title: 'Save report'
	filename: 'report.txt'
	filters: [ui2.FileDialogFilter{
		name: 'Text'
		extensions: ['txt']
	}]
)
```

The API uses `NSOpenPanel`/`NSSavePanel` on macOS, standard Win32 open/save
and folder dialogs on Windows, and the desktop's `zenity` or `kdialog` picker
on Linux. Linux requires a graphical session and one of those helpers;
`file_dialog_supported()` reports that availability. The synchronous API is not
available on iOS or Android, where a document picker needs an app-specific
asynchronous presentation callback.

For Linux and custom-rendered applications, `FilePicker` provides an in-window
picker with no `zenity` or `kdialog` dependency. It uses the same
`FileDialogConfig` for open, save, and folder modes. Keep the picker in app
state and add `picker.render(ui2.bounds())` as the last screen child. Its
controls attach callbacks directly. `FilePickerConfig.on_result` receives a
`FilePickerResult` with `.selected` and absolute paths, or `.cancelled`.

```v
mut picker := ui2.new_file_picker(
    id: 'picker'
    dialog: ui2.FileDialogConfig{ kind: .open directory: '/work/project' multiple: true }
    on_result: fn (result ui2.FilePickerResult) {
        if result.kind == .selected { println(result.paths) }
    }
)!
picker.open()!
ui2.request_refresh()
```

Run `v -b c run examples/custom_file_picker/main.v` for a complete example. The
picker lists directories first, filters files by extension, supports multiple
selection in open mode, and validates save filenames before returning an
absolute path.

## Menus and the tray

`set_menu_bar(...)` installs the application's top level menu bar and
`set_tray(...)` docks an icon in the status area. Both are plain declarations,
and each menu leaf carries `on_select`; a menu-less tray icon carries
`on_event`. Both receive `ElementEvent` with `.click` and source identity.

```v
ui2.set_menu_bar([ui2.Menu{
    title: 'File'
    items: [ui2.MenuItem{
        id: 'file_new'
        title: 'New Note'
        shortcut: 'cmd+n'
        on_select: fn (event ui2.ElementEvent) { println('New note') }
    }]
}])
ui2.set_tray(
    title: 'ui2'
    icon: 'symbol:cup.and.saucer.fill'
    on_event: fn (event ui2.ElementEvent) { println('Tray clicked') }
)
```

A shortcut names the platform's primary modifier as `cmd`: Command on macOS,
Control on Windows and Linux. A row's `checked` state is declared rather than
remembered — after handling the event, install the menu again with the new
value. Either call may come before `run_window`; what was declared is installed
as soon as there is a window to attach it to. `remove_tray()` undocks the icon.

macOS builds an `NSMenu` main menu, keeping its own application menu with
"Quit <app>" first, and an `NSStatusItem` for the tray, whose `icon` may name an
SF Symbol as `symbol:<name>`. Windows builds an `HMENU` menu bar with an
accelerator table, and a `Shell_NotifyIcon` notification area icon that opens
its menu on either mouse button. The custom renderer has no platform menu bar,
so it draws one across the top of the window — `bounds()` reserves that strip,
so a screen laid out at y 0 starts below it — and it owns nothing outside its
window, so `tray_supported()` is `false` there. iOS and Android have neither, so
both calls are accepted and ignored; check `menu_bar_supported()` and
`tray_supported()` before offering them in a shared UI.

`validate_menus(...)` rejects an untitled menu, an empty leaf declaration, a
duplicated id, a submenu with a callback, and a decorated separator, so a
declaration can be checked in a test without a window.

## Layout and text offsets

VML provides `Flex` for content-sized, growing/shrinking and wrapping
children, and `Grid` for rows/columns, responsive automatic columns and
cell spans. Both assign parent-local child frames. `Stack` overlays aligned
children; `Absolute` preserves explicit parent-local geometry. `Row` and `Column`
are Flex conveniences.
Authored VML x/y and geometry expressions used in layout dimensions require a direct Absolute parent.

Responsive layouts can combine wrapping, automatic Grid columns and conditional
visibility with expressions such as `root.width < 600`. Flex/Grid layout is
shared by native backends and the custom renderer.
See [modern layout](docs/modern-layout.md) for properties, intrinsic measurement,
limits and the executable `examples/responsive_layout` example.

Retained layout and subtree updates are described in [Incremental layout](docs/incremental-layout.md),
with a V/compiled-builder example in `examples/incremental_layout`.

A label, button, checkbox, or dropdown whose text is wider than its frame ends
in an ellipsis rather than running over whatever is beside it: the native
backends hand their cells `NSLineBreakByTruncatingTail`, and the custom
renderer shortens the line itself. Text fields and text areas are the
exception, since they place the caret by measuring the whole string.

`TextEditor` positions are Unicode rune offsets. Native text-area selection APIs
use UTF-16 code-unit offsets. This is intentional; grapheme-cluster editing is
outside the portable editor's current contract.

Read-only text that an application paints itself (a transcript on a canvas,
say) can use `TextRangeSelection` for mouse selection. Register the lines you
draw each frame as `SelectableTextLine` values, map pointer events to a
`TextPosition` (block, line, rune column) with `text_position_at`, and feed it
to `press`, `drag`, and `release`; `line_columns` then tells you which runes
of each line to highlight and copy. A press only turns into a selection once
the pointer moves past `text_selection_drag_threshold`, so clicks on links
drawn in the same text still work. `ClickCounter` and `text_word_range` cover
double-click word selection, and `text_column_at_x` maps an x offset to a
column given a prefix-width function.

## Scrolling

A `Scroll` element scrolls over its children, vertically unless told otherwise.
`scroll_mode`, named after vlang/gui's setting, chooses the axes:
`vertical_only` (the default), `horizontal_only`, or `both`. The content is as
wide as its rightmost child reaches and as tall as its lowest, and whatever
overflows along an axis the mode leaves out is clipped.

```v
ui2.scroll_with_mode('columns', frame, 0xffffff, .horizontal_only, columns)
```

```vml
Scroll(id: "columns", scroll_mode: horizontal_only) { ... }
```

The horizontal scroller runs along the bottom edge. A trackpad or a tilt wheel
scrolls sideways directly, and Shift turns a plain wheel sideways. Scroll
elements nest: a gesture along an axis the element under the pointer does not
scroll moves the nearest enclosing one that does, so a strip of columns that
each scroll vertically still scrolls sideways with the pointer over a column.

`scroll_offset(id)` and `scroll_horizontal_offset(id)` read the position,
`scroll_to_offset`, `scroll_to_horizontal_offset` and `scroll_to_rect` set it,
and a `.scroll` element callback reports a change along either axis.
The event carries both offsets in `x` and `y`, with the vertical offset in `value`.
An offset asked for before
the element exists is taken up when it is first laid out. To scroll to content
the event being handled has just added, call `request_refresh()` first: an
offset past the current range, asked for while a rebuild is pending, is taken up
again once that rebuild has laid out the new range. The iOS backend scrolls the
same modes but does not expose these functions.

## Fonts and text sizes

`TextStyle.size` and VML `font_size` are logical em sizes on every platform,
using the same units as geometry. The default size of 15 means a 15-unit em
square. Device DPI scales presentation separately; it does not change layout,
text sizes or line breaks. There is no unit profile or `units` VML property.
See [logical units](docs/logical-units.md) for migration and rounding rules.
For affine presentation, exact clipping and pan/zoom, see
[visual transforms](docs/visual-transforms.md).

The custom desktop renderer uses vglyph/Pango for layout and shaping and
FreeType for rasterization. Its CPU measurement works before opening a window
and uses the same font resolution, wrapping and logical sizes as drawing.
Device DPI is applied separately for each drawing context. See
[the text backend contract](docs/vglyph-text.md#measurement-and-units).

The renderer picks a default text face from UI2's font discovery. `ui2` ships
Roboto and Roboto Mono in `assets/fonts/`, giving custom windows the same
default text faces on each platform. These fonts are found directly while
the module is on the build machine; to ship a binary elsewhere, copy
`assets/fonts/` next to it or put the files in a `fonts/` directory beside it.

Failing all of those, the renderer looks for Inter, Roboto, Noto Sans, Open
Sans, DejaVu Sans, Liberation Sans, Ubuntu, Cantarell, FreeSans, and Arial among
the installed fonts, in that order, and settles for any upright sans face.

`UI2_FONT` and `UI2_FONT_BOLD` override everything and take file paths, which is
the quickest way to compare faces:

```sh
UI2_FONT=/usr/share/fonts/truetype/roboto/Roboto-Regular.ttf ./users
```

The bundled fonts and default discovery use static faces. vglyph can shape
variable fonts, but UI2's public styles still expose the existing bold/italic
flags; additional weight and variation controls need their own API.

`TextStyle.font_family` names a family. The native backends hand the name to the
platform's font manager; the custom desktop renderer registers a matching
file from UI2's font directories or asks Pango/Fontconfig to resolve the family.
An unavailable family falls back through the default text face before symbol
fonts.

A family that names a fixed-pitch face is the exception: dropping to the
proportional default would lose the column alignment it was asked for. So
`monospace`, `Consolas`, `Courier New`, `Menlo`, and anything ending in `Mono`
fall back through Roboto Mono, JetBrains Mono, DejaVu Sans Mono, Liberation
Mono, Noto Sans Mono, Ubuntu Mono, Cascadia Mono, Consolas, Menlo, and Courier
New. The bundled Roboto Mono means that list always resolves.

### Symbols

UI2 bundles Material Icons, Noto Sans Symbols 2 and monochrome Noto Emoji
alongside the text faces. The desktop text adapter registers the bundled
files with Pango/Fontconfig before measurement or drawing. Pango shapes
clusters and uses separate preferences for normal text and emoji, preserving
UI2's explicit and bundled fallback priorities. The current
profile prefers bundled monochrome Noto Emoji; installing a color emoji font
does not switch that default. System fonts cover scripts and codepoints still
missing from those faces. Use the same font set and preferences when comparing
logical layout across machines.

`UI2_FONT_SYMBOLS` supplies an additional symbol font file, preferred before
the bundled symbol and emoji fallbacks in both the desktop adapter and the
remaining Fontstash paths:

```sh
UI2_FONT_SYMBOLS=/usr/share/fonts/truetype/ancient-scripts/Symbola.ttf ./treeview
```

Android custom and headless measurement still use Fontstash. Those paths
retain UI2's explicit symbol fallback chain, the font's ascender/descender
conversion and monochrome emoji. Their `stb_truetype` rasterizer does not
apply variable font axes or render bitmap/layered color emoji, so use static
outline fonts there.

## Images and assets

Custom rendering supports fit modes, source crops, RGBA tint, rotation,
context-owned atlases and explicit DPI variants. See [images and assets](docs/images-assets.md)
and the `image_assets` example for the API and resource diagnostics.

## Charts

`ui2.chart` creates line, grouped bar, scatter, pie, and doughnut charts. Its
`type`, `data`, and `options` configuration follows the basic shape of
[Chart.js](https://www.chartjs.org/docs/latest/). It returns an ordinary
`Element`, so it can be placed in any V-built layout on native or custom
backends, without JavaScript or a web view.

```v okfmt
sales := ui2.chart(
	id:      'sales'
	frame:   ui2.rect(16, 16, 480, 300)
	type:    .bar
	data:    ui2.ChartData{
		labels:   ['Jan', 'Feb', 'Mar']
		datasets: [
			ui2.ChartDataset{ label: 'Revenue', data: [f64(12), 19, 25] },
			ui2.ChartDataset{ label: 'Profit', data: [f64(-2), 5, 9] },
		]
	}
	options: ui2.ChartOptions{ title: 'Monthly sales' }
) or { panic(err) }
```

Line and bar charts use category labels; missing labels default to the
one-based data index. Series can have different lengths. Scatter datasets use
`points: [ui2.ChartPoint{x: 1, y: 3}, ...]` instead of `data`, with numeric
x coordinates. Pie and doughnut accept one visible dataset, with labels and
colors per slice. Non-positive slice values are skipped.

Axes scale automatically with rounded tick intervals, including zero by default.
Set `begin_at_zero: false`
for a tighter line/scatter y range. Bars always include zero unless explicit
`y_min` / `y_max` bounds override it. Values outside explicit bounds are clamped
to the plot edges. NaN and infinite values are skipped, leaving gaps in lines.
Empty data produces an empty chart; invalid options return an error.

Options include `legend`, `grid`, `tooltips`, `ticks` (a target count from 1 through 20),
`background`, `text_color`, `grid_color`, and a nonempty `palette` of RGB colors.
Set a dataset's `color` to override its series color, or `colors` to override
pie/doughnut slice colors. `hidden: true` excludes a dataset from the chart and
its scales. `line_width` and `point_radius` accept values from 0 through 20;
zero disables the corresponding line or markers. Doughnut `cutout` is the
inner radius fraction, defaults to 0.5, and must be in `[0, 1)`.

Charts expose their title and data through accessibility metadata. Data markers
and slices use the existing backend tooltip support. Legends wrap, and category
labels are thinned to fit. The frame must be at least 120 by 100 and have enough
height for its title and legend. For resizing, derive the frame from
`ui2.bounds()` in your build function. Update the model and call `ui2.request_refresh()`
to rebuild with new data.

This is a basic chart component rather than the complete Chart.js API: it has
no chart animations, clickable legends, zoom, stacking, time axes, or plugins.
It composes views and labels, including scan-converted strips for lines and
slices, and is intended for modest datasets and chart sizes.

Run `v -b c run examples/charts/main.v` to see all five chart types in a layout that
adapts to the window width. Add `-d ui2_custom_rendering` to try the custom
renderer on macOS or Windows.

## Keyboard events

Keyboard focus, Tab order, scopes, directional navigation and portable semantic
hooks are documented in [Focus navigation](docs/focus-navigation.md). Try the
[focus_navigation example](examples/focus_navigation/main.v) in native or custom mode.

Use `on_key_event` when a shortcut should follow a physical key across keyboard
layouts. `KeyEvent.code` is a portable `KeyCode`; text entry still follows the
active layout.

```v
fn handle_key(event ui2.KeyEvent) {
	if event.cmd && !event.shift && !event.ctrl && !event.alt
		&& event.code == ui2.KeyCode.n {
		ui2.consume_key()
		// New document
	}
}

ui2.on_key_event(handle_key)
```

Pointer events do not carry modifier keys; `ui2.key_modifiers()` reports the
ones held right now (`shift`, `ctrl`, `alt`, and `cmd` for Command or the
Windows key), so a click handler can tell a Shift- or Cmd-click apart.

The existing `on_key` callback remains available for normalized strings such as
`cmd+n` and `up`. On AppKit those strings are now also derived from physical key
codes for known keys, so command shortcuts are independent of the input source.

## Examples

Typed-VML ports from `v-ui` include:

- `v -b c run examples/counter/main.v` — two independent Counter components with typed events.
- `v -b c run examples/temperature_converter/main.v` — the two-way 7GUIs
  temperature converter.
- `v -b c run examples/flight_booker/main.v` — the validated 7GUIs flight booker.
- `v -b c run examples/dropdown/main.v` — a dropdown with selection feedback.
- `v -b c run examples/switch/main.v` — a boolean switch represented by the
  portable checkbox control.
- `v -b c run examples/crud/main.v` — create, filter, update, and delete people.
- `v -b c run examples/rgb_color/main.v` — validate RGB components and preview the
  resulting color.
- `v -b c run examples/group/main.v` — grouped text fields, checkboxes, and form
  validation.
- `v -b c run examples/rectangles/main.v` — the original four-color rectangle row.
- `v -b c run examples/textbox/main.v` — editable and read-only multiline text
  areas with live character counts.
- `v -b c run examples/box_layout/main.v` — fixed, relative, nested, and
  window-anchored rectangles.
- `v -b c run examples/dynamic_layout/main.v` — add, remove, reorder, hide, and
  rename controls through a keyed repeater.
- `v -b c run examples/grid/main.v` — the original compact three-column data grid.
- `v -b c run examples/label_justify/main.v` — left, center, and right label
  alignment plus single-line clipping.
- `v -b c run examples/message/main.v` — compare the system alert from
  `message_box` with the hand-drawn in-window dialog.
- `v -b c run examples/demo_label/main.v` — the original minimal centered-label
  demonstration.
- `v -b c run examples/group2/main.v` — two responsive groups with text fields,
  a checkbox, native buttons, and validation feedback.
- `v -b c run examples/logview/main.v` — append scan batches to a read-only log.
- `v -b c run examples/nested_scrollview/main.v` — scroll a list of independently
  scrollable multiline text areas.
- `v -b c run examples/scrollview/main.v` — two independently scrollable read-only
  text panes with generated content.
- `v -b c run examples/horizontal_scroll/main.v` — a column browser whose strip of
  columns scrolls sideways while each column scrolls its own rows.
- `v -b c run examples/box_layout_with_textbox/main.v` — fixed and proportional box
  layout with an editable multiline text area.
- `v -b c run examples/files_dropped/main.v` — collect dropped files and plain text
  in a keyed, scrollable list.
- `v -b c run examples/nested_scrollview_box_layout/main.v` — a scrollable 5×5 box
  layout of independently editable multiline areas.
- `v -b c run examples/demo_radio/main.v` — exclusive country choices that switch
  between compact horizontal and vertical layouts.
- `v -b c run examples/demo_style_4colors/main.v` — select four-color palettes and
  preview them across portable and native controls.
- `v -b c run examples/box_layout_inside_row/main.v` — proportional box layout
  inside an inset row, with switchable text-area bounds.
- `v -b c run examples/rectangles_resizable/main.v` — four rounded color boxes that
  share the available width as the window resizes.
- `v -b c run examples/accordion/main.v` — collapsible component pages with one
  active section at a time.
- `v -b c run examples/tabs/main.v` — three keyed pages selected through a native
  tab-style button bar.
- `v -b c run examples/double_listbox/main.v` — transfer keyed values between two
  scrollable lists and inspect the result.
- `v -b c run examples/treeview/main.v` — expand nested folders and select files in
  a keyed, scrollable tree.
- `v -b c run examples/dirbrowser/main.v` — browse and choose folders from the local
  filesystem.
- `v -b c -d ui2_custom_rendering run examples/fontchooser/main.v` — apply font family, size, color, and
  emphasis choices to an editable preview.
- `v -b c run examples/rasterview/main.v` — show a bundled bitmap in a responsive
  image frame.
- `v -b c run examples/resizable_menu_window/main.v` — resize a native context-menu
  control between compact and stretched layouts.
- `v -b c run examples/filebrowser/main.v` — browse folders, select files, and
  confirm or cancel the current selection.
- `v -b c run examples/splitpanel/main.v` — adjust nested responsive panes around
  editable text and a scrollable data grid.
- `v -b c run examples/row_layout/main.v` — experiment with row proportions,
  margins, spacing, and control height.
- `v -b c -d ui2_custom_rendering run examples/demo_event/main.v` — inspect normalized pointer and keyboard
  events in a live event log.
- `v -b c -d ui2_custom_rendering run examples/demo_chunkview/main.v` — compose nested styled text chunks
  and toggle their visibility and alignment.
- `v -b c -d ui2_custom_rendering run examples/cells/main.v` — edit a compact spreadsheet and recalculate
  dependent `sum` formulas.
- `v -b c run examples/circle_drawer/main.v` — add and resize circles with
  selection-aware undo and redo.
- `v -b c run examples/gg2048/main.v` — play a deterministic, responsive version
  of the 2048 tile game.
- `v -b c -d ui2_custom_rendering run examples/editor/main.v` — browse, create, edit, and save text files
  from a responsive editor.
- `v -b c -d ui2_custom_rendering run examples/calculate/main.v` — evaluate arithmetic expressions with
  precedence, unary operators, and parentheses.
- `v -b c -d ui2_custom_rendering run examples/timer/main.v` — run, pause, resume, and restart a timer with
  a draggable duration control.
- `v -b c run examples/slider_textbox/main.v` — keep horizontal and vertical slider
  values synchronized with validated text fields.
- `v -b c run examples/transitions/main.v` — animate a movable tile between canvas
  targets with cubic easing.
- `v -b c run examples/gradient_texture/main.v` — generate an interactive HSV
  gradient from keyed color tiles.
- `v -b c run examples/change_title/main.v` — validate a title and update the native
  desktop window caption.
- `v -b c run examples/nested_clipping/main.v` — toggle a scroll viewport per box, or
  per quadrant, and watch the unclipped bars spill over their neighbours.
- `v -b c run examples/canvas_layout/main.v` — drag a themed tile across a sheet that
  is taller than its viewport, and read live canvas coordinates.
- `v -b c run examples/grid2/main.v` — sort a scrollable data grid of text, factor,
  and boolean columns, then edit the selected record.
- `v -b c run examples/colorbox/main.v` — pick a color from a hue strip and an HSV
  square, store it in a slot, and drive a rectangle's text with it.
- `v -b c run examples/child_window/main.v` — open a movable child panel with its own
  field, checkbox, and native greeting dialog.
- `v -b c run examples/accent_color/main.v` — drag three channels into an accent and
  derive a shade, a tint, and a readable font color from it.
- `v -b c -d ui2_custom_rendering run examples/text_style/main.v` — apply a family found in this machine's
  font trees, at a chosen size and emphasis, to an editable sample.
- `v -b c -d ui2_custom_rendering run examples/canvas_layout_inside_row/main.v` — drag a rotatable logo
  across two panes and read its position in each pane's own coordinates.
- `v -b c run examples/calculator_resizable/main.v` — a calculator whose keys, type,
  and spacing are all fractions of the window.
- `v -b c run examples/users_box_layout/main.v` — a fixed registration column, with a
  progress bar and country choices, beside a table pane anchored to the window.
- `v -b c run examples/menubar/main.v` — a top level menu bar with shortcuts,
  separators, disabled and checked rows, and nested submenus.
- `v -b c run examples/tray_icon/main.v` — a status area icon whose menu sets a
  status, toggles a setting, and docks or hides the icon again.
- `v -b c run examples/custom_window/main.v` — a borderless desktop widget with
  ui2-drawn chrome, draggable content, and genuinely transparent space between
  its rounded surfaces on the native macOS and Windows backends.

Run the calculator demo with:

```sh
v -b c run examples/calculator/main.v
```

It ports the `v-ui` calculator to typed VML: the display reads from the model,
a keyed `Repeater` builds the keypad, and button actions call the calculator's
business logic directly. It includes decimal input, sign and percentage
controls, exponentiation, repeated equals, and division-by-zero recovery.

Run the responsive users demo with:

```sh
v -b c run examples/users/main.v
```

It ports the native-widget users example from `v-ui`. The complete screen is
declared in `examples/users/users.vml` and compiled with `$vml`; V only
contains the typed model and business actions. The example includes validated
text entry, password masking, country selection, toggles, a progress indicator,
and a keyed, scrollable user table.

### Android

Build Android examples on a Linux, macOS, or Windows development computer with
[V Android Bootstrapper (`vab`)](https://github.com/vlang/vab). It requires V,
a Java JDK, the Android SDK, and the Android NDK; Android Studio itself is not
required. Install `vab` on macOS or Linux with:

```sh
v install vab
v ~/.vmodules/vab
export PATH="$HOME/.vmodules/vab:$PATH"
vab doctor
```

See the `vab` installation guide linked above for Windows setup and environment
variables if the SDK or NDK is not detected. Then, from the `ui2` repository
root, build an APK for an example:

```sh
mkdir -p build/android
vab --name "ui2 counter" --package-id io.vlang.ui2.counter \
  -o build/android/counter.apk examples/counter
```

Replace `counter` in the source path, output name, application name, and package
ID to build another example. Use a different package ID for each example if you
want several of them installed at the same time. The default build includes all
supported Android CPU architectures.

Install the resulting APK on a connected device or emulator with:

```sh
adb install -r build/android/counter.apk
```

After installation, open **ui2 counter** from the device's app launcher.

Alternatively, let `vab` build, install, and launch the example in one step:

```sh
vab run --device auto --name "ui2 counter" \
  --package-id io.vlang.ui2.counter examples/counter
```

## Verification

Run `make test` for portable and host-native tests. `make examples` compiles
every example under `examples/` for the host platform and reports all failures
at once; `make examples-custom` repeats that with the custom `gg` renderer.
GitHub Actions runs focused desktop tests on Linux, macOS, and Windows,
including native and custom profiles, for every push and pull request. These
cover Counter, menus, compiled VML contracts, scrolling, text, and backend checks.
`make check-macos`,
`make check-ios`, `make check-android`, `make check-linux`, and
`make check-windows` type-check each renderer; cross-target checks require their
normal platform SDK/toolchain. `make check-custom` additionally type-checks the
opt-in custom macOS and Windows builds.
`make check-embedder-macos` checks the owned Metal embedder;
`make test-embedder` runs its focused suites on a macOS host with GPU access.

`make screenshot EXAMPLE=<name>` renders one example and writes a single frame
to a PNG, so a layout can be checked without a person watching the window:

```sh
make screenshot EXAMPLE=message
v -b c run examples/screenshot_example.vsh message --frame 30 --out shots
```

It drives gg's own recorder rather than a desktop screenshot utility, so it
needs no screen recording permission and captures the window alone. The
recorder reads the presented framebuffer back, which only the GL backend
implements, so the script builds macOS examples against GL instead of Metal.
Text is a third wider at 96 dpi than it is on macOS, so a layout that only just
fits in a macOS screenshot still has to be checked on Linux or Windows.

The Windows backend also has an executable Wine smoke test. It creates every
native widget kind, reads text back from the Win32 controls, verifies text-area
selection, and closes itself with a non-zero exit status on failure:

```sh
smoke_dir="$(mktemp -d)"
v -enable-globals -os windows \
  -o "$smoke_dir/ui2-windows-smoke.exe" examples/windows_smoke/main.v
mingw_sysroot="$(x86_64-w64-mingw32-gcc -print-sysroot)"
mingw_runtime="$(find "$mingw_sysroot" -name libwinpthread-1.dll -type f -print -quit)"
test -n "$mingw_runtime" && cp "$mingw_runtime" "$smoke_dir/"
WINEARCH=win64 WINEPREFIX="$smoke_dir/prefix" \
  wine "$smoke_dir/ui2-windows-smoke.exe"
```

A successful run prints `UI2_WINE_SMOKE_OK`. The runtime DLL copy is required
by the default MinGW-w64 thread runtime; it should likewise be shipped beside
applications unless the final executable is linked without that dependency.

Native objects returned by `alloc` follow a +1 creation contract. Renderers
release that ownership after a retaining parent/property accepts the object and
remove observers, delegates, actions, menus, and pointer registries on unmount.

## License

MIT. See [LICENSE](LICENSE).
