# Motion and presence

Custom rendering can fade and transform a retained element during entry, target
changes and exit. Motion changes presentation in logical units; it preserves
the element's layout identity, local editor text and selection.

```v
card := ui2.with_motion(
	ui2.view('card', ui2.rect(20, 20, 240, 120), ui2.BoxStyle{
		bg: 0xffffff
	}, children),
	ui2.MotionConfig{
		enter: ui2.MotionStyle{
			opacity: 0
			transform: ui2.VisualTransform{ translate_y: 12, scale_x: 0.96, scale_y: 0.96 }
		}
		exit: ui2.MotionStyle{
			opacity: 0
			transform: ui2.VisualTransform{ translate_y: -8 }
		}
		enter_transition: ui2.MotionTransition{ duration: 0.2, easing: .out_cubic }
		exit_transition: ui2.MotionTransition{ duration: 0.15, easing: .in_quad }
		transition: ui2.MotionTransition{ duration: 0.25, easing: .in_out_cubic }
	},
)
```

The present target comes from `Element.opacity` and the ordinary
`translate_x`, `translate_y`, `scale_x`, `scale_y`, `rotation`, `origin_x` and
`origin_y` properties. Changing those properties retargets from the currently
presented style. Opacity includes every descendant, including glyphs, images
and vector shapes; nested opacity multiplies.

`MotionStyle` specifies absolute presentation values. Its default transform is
the identity. The default enter and exit styles have opacity zero, with
durations of 0.18 and 0.12 seconds; target changes take 0.2 seconds. Set enter
and exit transforms explicitly when the present target has a persistent
transform. Durations are finite nonnegative seconds, opacity ranges from zero
to one, and scales must remain nonsingular throughout a transition.

Compiled VML takes the same typed configuration from a V application method:

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
presentation targets. Updating the application data retargets these retained
properties. The [motion presence example](../examples/motion_presence) includes
show/hide, transforms, keyed removal/reentry and reduced motion.

Compiled VML components retain the same motion state as their retained nodes.
Removing a keyed list item starts its configured exits, removes it from the
active layout order, and keeps its last resolved frame while painting. Its
component unmount and cleanup hooks run after the last descendant exit
finishes. Reinserting the same key during exit reverses from its current
presentation and retains its state, nodes, editor text and selection.

[Overlays](overlays.md) use the same retained motion state. A dialog's backdrop
fades with the surface, and its focus scope ends as soon as closing starts.
An overlay's hidden state keeps its component mounted; structural removal
uses the ordinary delayed unmount and cleanup contract.

Exiting content becomes unavailable to keyboard focus, pointer capture and
editing immediately. Hidden changes animate the same retained node; completing
a hide does not dispose its component. Making it visible again starts entry.
Disposing an owner or closing its window cancels pending motion and releases
its scopes once. Removing the motion configuration applies the authored
presentation immediately and completes any pending structural exit.

Motion requests paint frames while a transition runs and returns the custom
scheduler to idle after completion. Pointer hit testing, tooltips, focus
geometry and painting use the same sampled transform. Native rendering rejects
motion and nondefault opacity with a diagnostic. On macOS and Windows, enable
custom rendering with `-d ui2_custom_rendering`.

## Reduced motion

Set `MotionConfig.reduced_motion` from the application's accessibility
preference. Enabling it finishes an active transition immediately; later
changes snap to their targets. Exits still perform unmount and cleanup exactly
once. Disabling reduced motion does not restart a completed transition.

## Controlled clocks

The default clock uses monotonic seconds. `MotionConfig.clock` accepts a
`fn () f64` returning finite, monotonically increasing seconds. Keep the same
clock for a mounted element's lifetime; changing it while mounted produces an
error. A test or guest host can advance its clock and request a presentation
frame without sleeping.

The independent `new_motion_controller()` API can also be driven directly:

```v
mut motion := ui2.new_motion_controller(ui2.MotionControllerConfig{
	initial: ui2.MotionStyle{ opacity: 0 }
	clock: clock
})!
motion.set_present_at(true, ui2.MotionStyle{}, ui2.MotionTransition{
	duration: 0.2
}, 1.0)!
halfway := motion.sample_at(1.1)!
assert halfway.phase == .entering
assert halfway.style.opacity > 0 && halfway.style.opacity < 1
```

Controller samples expose the phase (`absent`, `entering`, `present`, `exiting`),
the current style, progress and whether another frame is needed. Repeating the
same presence and target does not restart its timeline. A host that uses this
API owns attachment, removal and frame scheduling.
