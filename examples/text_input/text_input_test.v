module main

import ui2

fn find_text_input_element(element ui2.Element, id string) ?ui2.Element {
	if element.id == id {
		return element
	}
	for child in element.children {
		if found := find_text_input_element(child, id) {
			return found
		}
	}
	return none
}

fn test_text_input_demo_builds_single_and_multiline_editors() {
	mut compiled_model_0 := TextInputDemo{}
	root := text_input_tree(mut compiled_model_0, ui2.rect(0, 0,
		text_input_width, text_input_height))
	title := find_text_input_element(root, 'title') or { panic('missing title input') }
	notes := find_text_input_element(root, 'notes') or { panic('missing notes input') }
	assert title.kind == .text_field
	assert voidptr(title.on_event) != unsafe { nil }
	assert notes.kind == .text_area
	assert voidptr(notes.on_event) != unsafe { nil }
}
