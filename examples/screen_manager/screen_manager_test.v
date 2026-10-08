module main

import ui2

fn test_screen_manager_demo_navigates_between_named_screens() {
	mut app := ui2.new_vml_app(screen_manager_vml_source, ScreenManagerDemo{}) or {
		panic(err)
	}
	initial := app.build(ui2.rect(0, 0, screen_manager_width, screen_manager_height)) or {
		panic(err)
	}
	manager := initial.children[0].children[1]
	assert manager.children[0].id == 'home'
	control := manager.children[0].children[0].children[2]
	control.on_event(ui2.ElementEvent{ kind: .tap, id: control.id })
	assert app.state().current == 'details'

	rebuilt := app.build(ui2.rect(0, 0, screen_manager_width, screen_manager_height)) or {
		panic(err)
	}
	assert rebuilt.children[0].children[1].children[0].id == 'details'
	assert rebuilt.children[0].children[1].children[0].children[0].children[0].text == 'Details'
}
