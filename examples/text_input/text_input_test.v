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
	root := text_input_test_tree(text_input_vml_source, TextInputDemo{}, ui2.rect(0, 0,
		text_input_width, text_input_height)) or { panic(err) }
	title := find_text_input_element(root, 'title') or { panic('missing title input') }
	notes := find_text_input_element(root, 'notes') or { panic('missing notes input') }
	assert title.kind == .text_field
	assert voidptr(title.on_event) != unsafe { nil }
	assert notes.kind == .text_area
	assert voidptr(notes.on_event) != unsafe { nil }
}

fn text_input_test_tree[T](source string, model T, frame ui2.Rect) !ui2.Element {
	mut app := ui2.new_vml_app(source, model)!
	return app.build(frame)!
}
