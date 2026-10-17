# Motion

Motion is ui2's animation system. An element's `motion` is a typed
`MotionConfig` that the renderer keeps with the retained element: there
is no id registry, nothing is started by hand, and a window draws frames only
while some motion runs, then returns to idle. Motion changes presentation, not
layout: it preserves the element's layout identity, local editor text and
selection, and a running animation never lays the tree out again.

One configuration covers:

- **presence**: the `enter` style an element appears from when it mounts or is
  shown, and the `exit` style it leaves to when it is hidden or removed;
- **transitions**: a declared value that changes while the element is shown
  eases from what is on screen to the new value;
- **layout transitions**: with `layout`, a change of the element's laid-out
  frame animates from where the element was shown (FLIP);
- **timelines**: keyframes, sequences, parallels, repeats and loops played over
  the element, or over descendants named by id;
- **events and control**: `on_motion` hears every run start, progress, complete
  or cancel, and a `MotionHandle` cancels, finishes or restarts them.

Motion runs in the renderer on Linux, macOS and Windows and in the headless
backend. Android and iOS keep gg/Fontstash text and reject motion and
nondefault opacity with a diagnostic.

## Composing motion

Each `motion_<name>` helper returns one `MotionPatch`; `compose_motion` merges
a list of them left to right into a `MotionConfig`, as `compose_styles` merges
`style_<name>` pieces into a `StylePatch`. A later piece replaces what an
earlier one set; enter and exit styles merge channel by channel.

```v
card := ui2.with_motion(ui2.view('card', ui2.rect(app.card_x, 20, 240, 120),
	ui2.BoxStyle{ bg: app.card_color, radius: 12 }, children), ui2.compose_motion([
	ui2.motion_fade(0.2), // enter from and exit to opacity 0 over 0.2 s
	ui2.motion_slide_y(12), // and from 12 units below
	ui2.motion_spring(170, 26), // ease with a damped spring
	ui2.motion_layout(.position), // slide to a new x instead of jumping
]))
```

Changing `app.card_x` or `app.card_color` in a later build moves or recolors
the card from where it is shown.

| Helper | Sets |
| --- | --- |
| `motion_fade(seconds)` | enter and exit opacity 0, and their durations |
| `motion_slide_x(d)`, `motion_slide_y(d)` | enter and exit translation |
| `motion_scale(s)`, `motion_rotate(degrees)` | enter and exit scale or rotation |
| `motion_enter(style)`, `motion_exit(style)` | any enter or exit channels |
| `motion_duration(seconds)` | entering, exiting and transitions |
| `motion_enter_duration(s)`, `motion_exit_duration(s)` | one of them |
| `motion_transition(seconds)` | value and layout changes while shown |
| `motion_easing(curve)` | the curve of all three |
| `motion_spring(stiffness, damping)` | a spring for all three, lasting its settle time |
| `motion_layout(mode)` | layout transitions: `.box`, `.position` or `.scale` |
| `motion_timeline(timeline)` | a timeline played over the element |
| `motion_target(id, timeline)` | a timeline played over the descendant `id` |
| `motion_on(handler)` | the event handler |
| `motion_handle(handle)` | a handle that controls the element's motion |
| `motion_reduced(bool)` | reduced motion for this element |
| `motion_clock(clock)` | a controlled clock |

`compose_motion` starts with no enter or exit effect, so
`compose_motion([motion_layout(.box)])` animates only layout. A `MotionConfig`
literal starts from its defaults instead: opacity 0 enter and exit over 0.18
and 0.12 seconds, and 0.2 second transitions.

## What animates

The present values come from the element's declaration: `opacity`,
`translate_x`, `translate_y`, `scale_x`, `scale_y`, `rotation`, `origin_x` and
`origin_y`, the box's `bg`, `border_color`, `radius` and `shadow`, and the text
color. `MotionStyle` is a partial set of those channels plus `box_scale_x` and
`box_scale_y`, which size the element's own fill, border and shadow from its
top-left corner without scaling its content. Every channel a style leaves unset
keeps the value beneath it.

Opacity includes every descendant, including glyphs, images and vector shapes;
nested opacity multiplies. The renderer draws paint channels from the sampled
values, so a color, radius or shadow change costs no relayout, and interaction
styles such as hover still apply over them. A font size animates with the
`.scale` layout mode or a scale transform rather than by laying text out every
frame.

`MotionTransition` is a duration in seconds and an easing: one of Kivy's and
Penner's named curves (`MotionEasing`: `linear`, `in_quad` ... `in_out_bounce`),
a custom `easing_fn`, or a `MotionSpring`. Opacity, scales and colors clamp an
easing's overshoot; translation, rotation and lengths keep it. Durations are
finite nonnegative seconds and scales must stay nonsingular.

## Layout transitions

With `layout` set, layout runs once with the new declaration and the element
is then shown moving from its previous frame to the new one by presentation
alone, over the element's `transition`:

- `.position` animates the position; the size changes at once.
- `.box` also resizes the element's own fill, border and shadow. Its text and
  children take their new layout immediately and only move, so nothing
  stretches. A progress bar's width is the typical use.
- `.scale` maps the whole element and its content from the old frame, the
  classic FLIP transform. Text scales with it.

A change that arrives while a layout transition runs starts from where the
element is shown. Resizing the window shows the new layout at once. Pointer hit
testing, focus geometry and scroll culling follow the presented frame.

## Timelines

A `MotionTimeline` plays keyframes over the element's presentation while it is
mounted. It starts when the element mounts or is shown and again whenever the
timeline changes; rebuilding with an equal timeline keeps it running.

```v
pulse := ui2.motion_keyframes(1.2, ui2.MotionKeyframe{
	at:     0.5
	style:  ui2.MotionStyle{ opacity: 0.4, scale_x: 1.1, scale_y: 1.1 }
	easing: .in_out_sine
}, ui2.MotionKeyframe{
	at:    1
	style: ui2.MotionStyle{ opacity: 1, scale_x: 1, scale_y: 1 }
})
there_and_back := ui2.motion_sequence(
	ui2.motion_tween(ui2.MotionStyle{ translate_x: 120 }, ui2.MotionTransition{ duration: 0.4 }),
	ui2.motion_tween(ui2.MotionStyle{ translate_x: 0 }, ui2.MotionTransition{ duration: 0.4 }),
)
logo := ui2.with_motion(logo_view, ui2.compose_motion([
	ui2.motion_timeline(ui2.motion_parallel(pulse, there_and_back).looped()),
]))
```

- A keyframe's `at` is a fraction of its timeline's duration and its `easing`
  shapes the segment that ends there. Keys sharing an `at` jump. A channel
  without a key at 0 starts from the value beneath it.
- `motion_sequence` plays timelines one after another, each continuing from
  where the previous one left every channel; `motion_parallel` plays them
  together, and its children must animate different channels.
- `repeated(n)` plays a timeline n more times and `looped()` repeats it until
  the element leaves. `alternate` plays every other cycle backwards, `step`
  samples it every `step` seconds and `delay` waits before it starts. Only the
  outermost timeline may loop forever, alternate, step or hold.
- When a finite timeline ends, its channels glide back to the declaration over
  the element's transition, or keep their final values with `hold: true`.

`MotionConfig.targets` (or `motion_target`) plays a timeline on a descendant by
its public id, so one element orchestrates its children. A descendant without
motion of its own runs it on the clock and reduced motion setting of the
element that targets it; a timeline in the descendant's own configuration takes
precedence.

## Events and handles

`on_motion` receives a `MotionEvent` for every run: `kind` is `start`,
`progress` (every frame, with `progress` from 0 to 1), `complete` or `cancel`;
`source` is `enter`, `exit`, `transition`, `layout` or `timeline` (whose
`progress` is that of the current `cycle`). A run replaced before it ends
reports `cancel` at the progress it reached. Events are delivered on the UI
thread after a frame has sampled every element, in tree order, and a frame that
delivered events builds again, so a handler may change application state.

```v
ui2.motion_on(fn [mut app] (event ui2.MotionEvent) {
	if event.source == .layout && event.kind == .complete {
		app.status = 'Arrived'
	}
})
```

A `MotionHandle` controls the element whose configuration holds it. Create one
per element with `&ui2.MotionHandle{}` and keep it with the state that builds
the element:

- `cancel()` stops every run where it stands, like Kivy's `cancel`: the values
  reached stay until the declaration changes, and each run reports `cancel`;
- `finish()` jumps every run to its end, like Kivy's `stop`; a looping timeline
  stops and a held one keeps its final values. Each run reports `complete`;
- `restart()` plays the timeline again from its start;
- `mounted()`, `running()` and `values()` report the element's state.

## Reduced motion

`app.set_reduced_motion(true)` applies the platform's accessibility preference
to every element of the app's windows, and `MotionConfig.reduced_motion` (or `motion_reduced`) to
one. Transitions and layout changes show their end at once, and timelines do
not play, except that a held finite timeline shows its final values. Exits still
perform unmount and cleanup exactly once. Turning it off does not restart a
finished transition; loops resume. The GPUI Kit's feedback components draw
their still variants while it is set.

## Compiled VML

A `motion` property takes the same configuration from an application method:

```vml
Column(gap: 12) {
    Repeater(model: app.rows, key: item.id) {
        Row(motion: app.card_motion(), opacity: app.card_opacity(item.id),
            translate_x: app.card_offset(item.id), height: 72, gap: 12) {
            Label(text: item.title)
            TextInput(text: "España, café y ñ")
        }
    }
}
```

`app.card_motion()` returns `ui2.MotionConfig`; the other methods return numeric
presentation targets. The helpers can also be written in place, as styles are:
`motion: [fade(0.2), slide_y(12), spring(170, 26)]` is
`ui2.motion_compose(ui2.motion_fade(0.2), ui2.motion_slide_y(12),
ui2.motion_spring(170, 26))`, and a single `motion: fade(0.2)` is composed the
same way. Interpreted VML supports the helpers whose arguments are numbers,
names, booleans or model values; `on`, `handle` and `clock` take V callbacks
and handles, so they need compiled VML.

`Timeline` and `Keyframe` parts declare a timeline in the document. A Timeline
under an element plays on that element; its keyframes animate the element
itself, or the descendant their `target` names:

```vml
View(id: "card", width: 240, height: 120) {
    Image(id: "logo", width: 48, height: 48, source: "logo.png")
    Timeline(duration: 1.2, repeat: true) {
        Keyframe(target: "logo", at: 0.5, opacity: 0.4, scale: 1.1, easing: in_out_sine)
        Keyframe(target: "logo", at: 1, opacity: 1, scale: 1)
        Keyframe(at: 1, background: #DBEAFE)
    }
}
```

Timeline takes `duration`, `delay`, `repeat` (loop while mounted) or `times`,
`alternate`, `step` and `hold`. Keyframe takes `target`, `at`, `easing` and the
channels `opacity`, `translate_x`, `translate_y`, `scale` (both axes),
`scale_x`, `scale_y`, `rotation`, `origin_x`, `origin_y`, `background`,
`border_color`, `text_color`, `radius`, `box_scale_x` and `box_scale_y`. A
Timeline joins the element's own `motion`, if any. The VML runtime builds these
parts today; compiled VML takes them once the compiler lowers part tags
generically.

Compiled VML components retain the same motion state as their retained nodes.
Removing a keyed list item starts its configured exits, removes it from the
active layout order, and keeps its last resolved frame while painting. Its
component unmount and cleanup hooks run after the last descendant exit
finishes. Reinserting the same key during exit reverses from its current
presentation and retains its state, nodes, editor text and selection. The
[motion presence example](../examples/motion_presence) shows show/hide,
transforms, keyed removal/reentry and reduced motion; the
[transitions example](../examples/transitions) moves a tile with a layout
transition declared in VML.

## Presence

Exiting content becomes unavailable to keyboard focus, pointer capture and
editing immediately. Hidden changes animate the same retained node; completing
a hide does not dispose its component. Making it visible again starts entry.
Disposing an owner or closing its window cancels pending motion and releases
its scopes once. Removing the motion configuration applies the authored
presentation immediately and completes any pending structural exit.

[Overlays](overlays.md) use the same retained motion state. A dialog's backdrop
fades with the surface, and its focus scope ends as soon as closing starts.
An overlay's hidden state keeps its component mounted; structural removal
uses the ordinary delayed unmount and cleanup contract.

## Frames and cost

Motion requests paint frames while anything runs and returns the scheduler to
idle after the last run ends; a motion frame draws without building unless an
event handler ran. Elements under a hidden ancestor never
keep the window drawing. In the steady state a running transition, layout
transition or loop allocates nothing: states, compiled timelines and the event
buffer are retained and every frame reuses them (`ui/motion_allocation_test.v`).

## Controlled clocks

The default clock uses monotonic seconds. `MotionConfig.clock` accepts a
`fn () f64` returning finite, monotonically increasing seconds. Keep the same
clock for a mounted element's lifetime; changing it while mounted produces an
error. A test or guest host can advance its clock and request a presentation
frame without sleeping.

The independent `new_motion_controller()` API can also be driven directly:

```v
mut motion := ui2.new_motion_controller(ui2.MotionControllerConfig{
	initial: ui2.MotionValues{ opacity: 0 }
	clock: clock
})!
motion.set_present_at(true, ui2.MotionValues{}, ui2.MotionTransition{
	duration: 0.2
}, 1.0)!
halfway := motion.sample_at(1.1)!
assert halfway.phase == .entering
assert halfway.values.opacity > 0 && halfway.values.opacity < 1
```

Controller samples expose the phase (`absent`, `entering`, `present`, `exiting`),
the current values, progress and whether another frame is needed. Repeating the
same presence and target does not restart its transition. A host that uses this
API owns attachment, removal and frame scheduling.
