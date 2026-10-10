module main

import ui2

fn find_tabs_element(element ui2.Element, id string) ?ui2.Element {
	if element.id == id {
		return element
	}
	for child in element.children {
		if found := find_tabs_element(child, id) {
			return found
		}
	}
	return none
}

fn test_tabs_selects_existing_page_only() {
	mut app := initial_tabs()
	app.select_tab(3)
	assert app.active_tab == 3
	assert app.status == 'tab3 selected.'
	app.select_tab(99)
	assert app.active_tab == 3
}

fn test_tabs_vml_shows_only_active_page() {
	mut app := initial_tabs()
	app.select_tab(2)
	root := tabs_tree(mut app, ui2.rect(0, 0, tabs_width, tabs_height))
	ui2.validate_element_tree(root) or { panic(err) }
	bar := find_tabs_element(root, 'tab_bar') or { panic('missing tab bar') }
	assert bar.children[0].children.len == 3
	assert bar.children[0].children[0].native_style
	assert bar.children[0].children[1].text == '• tab2'
	stage := find_tabs_element(root, 'tab_stage') or { panic('missing tab stage') }
	assert stage.children[0].children.len == 3
	assert stage.children[0].children[0].hidden
	assert !stage.children[0].children[1].hidden
	assert stage.children[0].children[2].hidden
}
