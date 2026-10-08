@[has_globals]
module ui2

__global spinner_test_events = []ElementEvent{}

fn capture_spinner_test_event(event ElementEvent) {
	spinner_test_events << event
}

fn test_spinner_autoselects_first_value_when_requested() {
	assert spinner_selected_text('', ['Home', 'Work'], true) == 'Home'
	assert spinner_selected_text('Work', ['Home', 'Work'], true) == 'Home'
	assert spinner_selected_text('', ['Home', 'Work'], false) == ''
	assert spinner_selected_text('', []string{}, true) == ''
}

fn test_spinner_reuses_dropdown_behavior_with_accessibility_defaults() {
	el := spinner(
		id:              'location'
		on_event:        capture_spinner_test_event
		frame:           rect(10, 20, 160, 42)
		values:          ['Home', 'Work', 'Other']
		text_autoupdate: true
		box:             BoxStyle{
			bg:     0xdbeafe
			radius: 7
		}
	)
	assert el.kind == .dropdown
	assert el.id == 'location'
	spinner_test_events = []ElementEvent{}
	el.on_event(ElementEvent{ kind: .change, id: el.id, text: el.text })
	assert spinner_test_events.len == 1
	assert spinner_test_events[0].id == el.id
	assert spinner_test_events[0].kind == .change
	assert spinner_test_events[0].text == 'Home'
	assert el.text == 'Home'
	assert el.menu.len == 3
	assert el.menu[2].title == 'Other'
	assert el.accessibility_role == 'combobox'
	assert el.accessibility_value == 'Home'
}
