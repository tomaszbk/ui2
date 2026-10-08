module main

import ui2

fn test_modal_view_demo_opens_confirms_and_dismisses() {
	mut app := ui2.new_vml_app(modal_view_vml_source, ModalViewDemo{}) or { panic(err) }
	initial := app.build(ui2.rect(0, 0, modal_view_width, modal_view_height)) or { panic(err) }
	assert initial.children[0].children[3].hidden
	control_1 := initial.children[0].children[2]
	control_1.on_event(ui2.ElementEvent{ kind: .tap, id: control_1.id })
	assert app.state().confirming

	opened := app.build(ui2.rect(0, 0, modal_view_width, modal_view_height)) or { panic(err) }
	modal := opened.children[0].children[3]
	assert !modal.hidden
	assert modal.children[2].children[0].children[0].text == 'Confirm action'
	control_2 := modal.children[2].children[0].children[3]
	control_2.on_event(ui2.ElementEvent{ kind: .tap, id: control_2.id })
	assert !app.state().confirming
	assert app.state().status == 'Action confirmed.'

	control_3 := modal.children[2].children[0].children[2]
	control_3.on_event(ui2.ElementEvent{ kind: .tap, id: control_3.id })
	assert app.state().status == 'Action cancelled.'
}
