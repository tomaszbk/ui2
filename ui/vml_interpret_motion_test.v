// vtest vflags: -d vml_interpreter
module ui2

// Timeline and Keyframe parts read by the VML interpreter: keyframes without a
// target play on the element holding the Timeline, keyframes naming a
// descendant become its targets, and a Timeline takes no place in a layout.

@[heap]
pub struct InterpMotionApp {
pub mut:
	count int
}

fn interp_motion_find(el Element, id string) ?Element {
	if el.id == id { return el }
	for child in el.children {
		if found := interp_motion_find(child, id) { return found }
	}
	return none
}

fn interp_motion_build(source string) !(&CompiledVmlNode, Element) {
	mut app := &InterpMotionApp{}
	element := vml_interpret(source, app, frame: rect(0, 0, 300, 200))!
	mut root := element.compiled_node
	root.mount()!
	return root, root.element()
}

fn test_interpreted_timelines_animate_their_element_and_its_descendants() ! {
	mut root, built := interp_motion_build('View(id: "card", width: 200, height: 100) {
	View(id: "logo", width: 20, height: 20)
	Timeline(duration: 1.2, repeat: true) {
		Keyframe(target: "logo", at: 0.5, opacity: 0.4, scale: 1.1, easing: in_out_sine)
		Keyframe(target: "logo", at: 1, opacity: 1, scale: 1)
		Keyframe(at: 1, background: #FF0000)
	}
}')!
	card := interp_motion_find(built, 'card')?
	logo := interp_motion_find(built, 'logo')?
	assert card.children.len == 1
	assert logo.motion == none
	config := card.motion or { return error('the card has no motion') }
	assert config.timeline.duration == 1.2 && config.timeline.repeat == motion_forever
	assert config.timeline.keyframes == [
		MotionKeyframe{
			at:    1
			style: MotionStyle{
				background: 0xff0000
			}
		},
	]
	assert config.targets.len == 1
	assert config.targets[0].id == logo.id
	assert config.targets[0].timeline.keyframes == [
		MotionKeyframe{
			at:     0.5
			style:  MotionStyle{
				opacity: 0.4
				scale_x: 1.1
				scale_y: 1.1
			}
			easing: .in_out_sine
		},
		MotionKeyframe{
			at:    1
			style: MotionStyle{
				opacity: 1
				scale_x: 1
				scale_y: 1
			}
		},
	]
	config.validate()!
	root.dispose_document()!
}

fn test_interpreted_timelines_take_no_place_in_a_layout() ! {
	mut root, built := interp_motion_build('Column(id: "list") {
	Label(id: "first", text: "One")
	Timeline(duration: 0.5) {
		Keyframe(target: "second", at: 1, translate_x: 12)
	}
	Label(id: "second", text: "Two")
}')!
	list := interp_motion_find(built, 'list')?
	assert list.children.map(it.id) == ['first', 'second']
	config := list.motion or { return error('the column has no motion') }
	assert config.targets.map(it.id) == ['second']
	root.dispose_document()!
}

fn test_interpreted_keyframes_reject_invalid_values() {
	mut app := &InterpMotionApp{}
	vml_interpret('View(id: "card") {
	Timeline(duration: 1) {
		Keyframe(at: 1.5, opacity: 1)
	}
}', app, frame: rect(0, 0, 300, 200)) or {
		assert err.msg().contains('at'), err.msg()
		return
	}
	assert false, 'a keyframe past the end was accepted'
}
