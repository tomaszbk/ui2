module main

import ui2

fn find_spinner_element(element ui2.Element, id string) ?ui2.Element {
	if element.id == id {
		return element
	}
	for child in element.children {
		if found := find_spinner_element(child, id) {
			return found
		}
	}
	return none
}

fn test_spinners_turn_a_ring_in_each_size() {
	mut app := SpinnerDemo{}
	root := spinner_tree(mut app, ui2.rect(0, 0, spinner_width, spinner_height))
	for id, side in {
		'small':  14.0
		'medium': 16.0
		'large':  24.0
	} {
		spinner := find_spinner_element(root, id) or { panic('missing ${id}') }
		assert spinner.is_vector_canvas
		assert spinner.frame.width == side && spinner.frame.height == side
		assert spinner.accessibility_role == 'progressbar'
		config := spinner.motion or { panic('the spinner does not turn') }
		assert config.timeline.repeat == ui2.motion_forever
	}
	assert (find_spinner_element(root, 'progress') or { panic('missing progress') }).hidden
}

fn test_saving_shows_the_loading_button_and_status() {
	mut app := SpinnerDemo{}
	root := spinner_tree(mut app, ui2.rect(0, 0, spinner_width, spinner_height))
	save := find_spinner_element(root, 'save') or { panic('missing save') }
	save.on_event(ui2.ElementEvent{ kind: .click, id: save.id })
	assert app.saving && app.status == 'Saving changes'
	saving := spinner_tree(mut app, ui2.rect(0, 0, spinner_width, spinner_height))
	button := find_spinner_element(saving, 'save') or { panic('missing save') }
	assert button.children[0].accessibility_role == 'progressbar'
	assert !(find_spinner_element(saving, 'progress') or { panic('missing progress') }).hidden
	app.finish()
	assert !app.saving && app.status == 'Saved'
}
