module main

// vml: motion_helpers.vml

import ui2

// Motion helper values and Timeline parts in compiled VML: `motion: [...]`
// lowers to `ui2.motion_compose(ui2.motion_<f>(...), ...)`, and a single call
// is composed the same way. ui/vml_interpret_test.v interprets the same
// document, and vml_conformance_motion_test.v compares the two.

@[heap]
pub struct MotionHelpersApp {
pub mut:
	duration f64 = 0.4
	ready    bool
	entering ui2.MotionStyle = ui2.MotionStyle{
		translate_x: -24
	}
}

fn motion_helpers_tree(mut app MotionHelpersApp, frame ui2.Rect) ui2.Element {
	return motion_helpers_vml_framed(mut app, frame)
}

fn motion_helpers_find(el ui2.Element, id string) ?ui2.Element {
	if el.id == id { return el }
	for child in el.children {
		if found := motion_helpers_find(child, id) { return found }
	}
	return none
}

fn motion_helpers_config(root &ui2.CompiledVmlNode, id string) ?ui2.MotionConfig {
	return motion_helpers_find(root.element(), id)?.motion
}

fn test_motion_helper_lists_compose_like_compose_motion() ! {
	mut app := &MotionHelpersApp{}
	initial := motion_helpers_tree(mut app, ui2.rect(0, 0, 300, 200))
	mut root := initial.compiled_node
	root.mount()!
	card := motion_helpers_config(root, 'card')?
	expected := ui2.compose_motion([ui2.motion_fade(0.2), ui2.motion_slide_y(8),
		ui2.motion_easing(.out_cubic), ui2.motion_spring(170, 26), ui2.motion_duration(0.4)])
	assert card.enter == expected.enter && card.exit == expected.exit
	assert card.enter_transition == expected.enter_transition
	assert card.transition == expected.transition
	assert card.transition.duration == 0.4 && card.transition.easing == .out_cubic
	single := motion_helpers_config(root, 'single')?
	assert single.enter == ui2.compose_motion([ui2.motion_fade(0.3)]).enter
	assert single.enter_transition.duration == 0.3
	entering := motion_helpers_config(root, 'entering')?
	assert entering.enter.translate_x? == -24 && entering.layout == .box
	app.duration = 0.6
	app.ready = true
	root.component.invalidate_app()!
	assert motion_helpers_config(root, 'card')?.transition.duration == 0.6
	assert motion_helpers_config(root, 'entering')?.layout == .position
	root.dispose_document()!
}

fn test_timeline_parts_play_on_their_element() ! {
	mut app := &MotionHelpersApp{}
	initial := motion_helpers_tree(mut app, ui2.rect(0, 0, 300, 200))
	mut root := initial.compiled_node
	root.mount()!
	timeline := motion_helpers_config(root, 'pulse')?.timeline
	assert timeline.duration == 1.2 && timeline.repeat == ui2.motion_forever
	assert timeline.keyframes.len == 2
	assert timeline.keyframes[0].at == 0.5 && timeline.keyframes[0].style.opacity? == 0.4
	assert timeline.keyframes[0].style.scale_x? == 1.1 && timeline.keyframes[0].easing == .in_out_sine
	assert timeline.keyframes[1].style.opacity? == 1
	root.dispose_document()!
}
