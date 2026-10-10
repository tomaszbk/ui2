module main

import ui2

fn test_screen_manager_demo_navigates_between_named_screens() {
	mut app := ScreenManagerDemo{}
	initial := screen_manager_tree(mut app, ui2.rect(0, 0, screen_manager_width, screen_manager_height))
	manager := initial.children[0].children[1]
	assert manager.children[0].id == 'home'
	control := manager.children[0].children[0].children[2]
	control.on_event(ui2.ElementEvent{ kind: .tap, id: control.id })
	assert app.current == 'details'

	rebuilt := screen_manager_tree(mut app, ui2.rect(0, 0, screen_manager_width, screen_manager_height))
	assert rebuilt.children[0].children[1].children[0].id == 'details'
	assert rebuilt.children[0].children[1].children[0].children[0].children[0].text == 'Details'
}
