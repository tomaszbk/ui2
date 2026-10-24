module main

// vml: motion.vml

import ui2

pub struct MotionContractApp {
pub mut:
	alpha  f64 = 0.8
	offset f64
	hidden bool
	config ui2.MotionConfig = ui2.MotionConfig{ reduced_motion: true }
}

fn motion_contract(mut app MotionContractApp) ui2.Element {
	return motion_vml_framed(mut app, ui2.rect(0, 0, 160, 80))
}

fn test_motion_lowering_retains_bound_targets_and_component_state() ! {
	mut app := &MotionContractApp{}
	initial := motion_contract(mut app)
	mut root := initial.compiled_node
	root.mount()!
	mut owner := root.component
	body := root.element()
	assert body.motion != none
	assert body.opacity == 0.8 && body.translate_x == 0
	button := body.children[0]
	button.on_event(ui2.ElementEvent{ kind: .click })
	assert root.element().children[0].text == '1'
	app.alpha = 0.25
	app.offset = 42
	app.hidden = true
	owner.invalidate_app()!
	changed := root.element()
	assert changed.opacity == 0.25 && changed.translate_x == 42 && changed.hidden
	assert changed.children[0].compiled_node == button.compiled_node
	assert changed.children[0].text == '1'
	app.hidden = false
	owner.invalidate_app()!
	assert root.element().children[0].text == '1'
	root.dispose_document()!
	assert owner.runtime.stats() == ui2.SignalStats{}
}
