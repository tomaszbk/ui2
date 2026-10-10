module main

import ui2

fn find_group_element(element ui2.Element, id string) ?ui2.Element {
	if element.id == id {
		return element
	}
	for child in element.children {
		if found := find_group_element(child, id) {
			return found
		}
	}
	return none
}

fn test_group_submit_validates_and_confirms_names() {
	mut app := GroupDemo{}
	app.submit()
	assert app.message == 'Both names are required.'
	app.first_name = ' Ada '
	app.last_name = ' Lovelace '
	app.submit()
	assert app.message == 'Added Ada Lovelace.'
}

fn test_group_vml_contains_bound_controls_and_native_button() {
	mut app := GroupDemo{}
	root := group_tree(mut app, ui2.rect(0, 0, group_width, group_height))
	ui2.validate_element_tree(root) or { panic(err) }

	assert (find_group_element(root, 'registration1') or { panic('missing checkbox') }).checked
	assert (find_group_element(root, 'registration3') or { panic('missing checkbox') }).checked
	button := find_group_element(root, 'add_user') or { panic('missing Add user button') }
	assert button.native_style
	assert voidptr(button.on_event) != unsafe { nil }
}
