module main

import ui2

fn test_accordion_demo_opens_one_section_at_a_time() {
	mut app := AccordionDemo{}
	initial := accordion_widget_tree(mut app, ui2.rect(0, 0, accordion_width, accordion_height))
	preferences := initial.children[0].children[1]
	// A header before each section; only the bound one is shown.
	assert preferences.children.len == 6
	assert !preferences.children[1].hidden && preferences.children[3].hidden
	assert preferences.children[1].children[0].text == 'Update your public profile.'
	assert initial.children[0].children[2].text == 'Open: profile'

	security := preferences.children[4]
	security.on_event(ui2.ElementEvent{ kind: .click, id: security.id })
	assert app.section == 'security'
	rebuilt := accordion_widget_tree(mut app, ui2.rect(0, 0, accordion_width, accordion_height))
	sections := rebuilt.children[0].children[1]
	assert sections.children[1].hidden && !sections.children[5].hidden
	assert sections.children[4].accessibility_value == 'expanded'
}
