module main

import ui2

fn test_accordion_demo_switches_active_content() {
	mut app := ui2.new_vml_app(accordion_vml_source, AccordionDemo{}) or { panic(err) }
	initial := app.build(ui2.rect(0, 0, accordion_width, accordion_height)) or { panic(err) }
	preferences := initial.children[0].children[1]
	assert preferences.children[0].children[0].children[0].text == 'Update your public profile.'

	security := preferences.children[3]
	control := security
	control.on_event(ui2.ElementEvent{ kind: .tap, id: control.id })
	assert app.state().current == 2
	rebuilt := app.build(ui2.rect(0, 0, accordion_width, accordion_height)) or { panic(err) }
	assert rebuilt.children[0].children[1].children[0].children[0].children[0].text == 'Review passwords and active sessions.'
}
