module main

import ui2

fn find_message_element(element ui2.Element, id string) ?ui2.Element {
	if element.id == id {
		return element
	}
	for child in element.children {
		if found := find_message_element(child, id) {
			return found
		}
	}
	return none
}

fn test_message_demo_opens_and_closes() {
	mut app := MessageDemo{}
	assert !app.visible
	app.show_message()
	assert app.visible
	app.close_message()
	assert !app.visible
}

fn test_message_vml_offers_native_and_drawn_dialogs() {
	mut compiled_model_0 := MessageDemo{}
	root := message_tree(mut compiled_model_0, ui2.rect(0, 0, message_width, message_height))
	ui2.validate_element_tree(root) or { panic(err) }

	assert (find_message_element(root, 'show_native_message') or { panic('missing native button') }).native_style
	assert (find_message_element(root, 'ask_native_question') or { panic('missing question button') }).native_style
	assert (find_message_element(root, 'show_message') or { panic('missing show button') }).native_style

	overlay := find_message_element(root, 'overlay') or { panic('missing overlay') }
	assert overlay.hidden
	assert (find_message_element(root, 'overlay_title') or { panic('missing title') }).text == 'Hello World'
	close := find_message_element(root, 'close_message') or { panic('missing close button') }
	assert close.native_style
	assert close.text == 'OK'

	mut opened := MessageDemo{}
	opened.show_message()
	opened_root := message_tree(mut opened, ui2.rect(0, 0, message_width, message_height))
	assert !(find_message_element(opened_root, 'overlay') or { panic('missing open overlay') }).hidden
}
