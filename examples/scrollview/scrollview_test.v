module main

import ui2

fn find_scrollview_element(element ui2.Element, id string) ?ui2.Element {
	if element.id == id {
		return element
	}
	for child in element.children {
		if found := find_scrollview_element(child, id) {
			return found
		}
	}
	return none
}

fn test_scrollview_generates_one_hundred_lines() {
	app := initial_scrollview()
	lines := app.text.split_into_lines()
	assert lines.len == 100
	assert lines[0].starts_with('line 00')
	assert lines[99].starts_with('line 99')
}

fn test_scrollview_vml_builds_two_readonly_responsive_panes() {
	mut compiled_model_0 := initial_scrollview()
	root := scrollview_tree(mut compiled_model_0, ui2.rect(0, 0, scrollview_width, scrollview_height))
	ui2.validate_element_tree(root) or { panic(err) }

	info := find_scrollview_element(root, 'info') or { panic('missing information pane') }
	text := find_scrollview_element(root, 'text') or { panic('missing generated-text pane') }
	assert info.readonly
	assert text.readonly
	assert info.frame.width == 320
	assert text.frame.x == 352
	assert text.frame.height == 306
}
