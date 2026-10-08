module main

import ui2

fn find_counter_element(element ui2.Element, id string) ?ui2.Element {
	if element.id == id {
		return element
	}
	for child in element.children {
		if found := find_counter_element(child, id) {
			return found
		}
	}
	return none
}

fn test_counter_increments() {
	mut app := CounterApp{}
	app.increment()
	app.increment()
	assert app.count == 2
}

fn test_counter_vml_builds_valid_ui() {
	app := CounterApp{
		count: 7
	}
	root := counter_test_tree(counter_vml_source, app, ui2.rect(0, 0, counter_width, counter_height)) or { panic(err) }
	assert (find_counter_element(root, 'count') or { panic('missing count') }).text == '7'
	button := find_counter_element(root, 'increment') or { panic('missing Count button') }
	assert button.text == 'Count'
	assert voidptr(button.on_event) != unsafe { nil }
	assert button.native_style
}

fn counter_test_tree[T](source string, model T, frame ui2.Rect) !ui2.Element {
	mut app := ui2.new_vml_app(source, model)!
	return app.build(frame)!
}
