module main

import ui2

fn test_popup_demo_opens_and_closes_editor() {
	mut app := PopupDemo{}
	initial := popup_tree(mut app, ui2.rect(0, 0, popup_width, popup_height))
	assert initial.children[0].children[2].hidden
	control_1 := initial.children[0].children[1]
	control_1.on_event(ui2.ElementEvent{ kind: .tap, id: control_1.id })
	assert app.editing

	opened := popup_tree(mut app, ui2.rect(0, 0, popup_width, popup_height))
	popup_element := opened.children[0].children[2]
	assert !popup_element.hidden
	assert popup_element.children[2].children[0].text == 'Edit profile'
	control_2 := popup_element.children[2].children[2].children[0].children[3]
	control_2.on_event(ui2.ElementEvent{ kind: .tap, id: control_2.id })
	assert !app.editing
}
