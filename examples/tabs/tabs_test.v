module main

import ui2

fn test_tabs_show_only_the_selected_page() {
	mut app := TabsDemo{}
	root := tabs_tree(mut app, ui2.rect(0, 0, tabs_width, tabs_height))
	settings := root.children[0].children[1]
	list := settings.children[0]
	assert list.accessibility_role == 'tablist' && list.children.len == 4
	assert list.children[0].accessibility_value == 'selected'
	assert !list.children[2].enabled
	pages := settings.children[1]
	assert pages.children.map(it.hidden) == [false, true, true, true]
	assert pages.children[0].children[0].text == 'Profile'

	password := list.children[1]
	password.on_event(ui2.ElementEvent{ kind: .click, id: password.id })
	assert app.tab == 'password'
	rebuilt := tabs_tree(mut app, ui2.rect(0, 0, tabs_width, tabs_height))
	page := rebuilt.children[0]
	assert page.children[1].children[1].children.map(it.hidden) == [true, false, true, true]
	// The segmented Tabs follows the same value.
	compact := page.children[2].children[0].children[0]
	assert compact.children[1].accessibility_value == 'selected'
	assert page.children[2].children[1].text == 'Showing password'
}
