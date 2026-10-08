@[has_globals]
module ui2

__global toggle_button_test_events = []ElementEvent{}

fn capture_toggle_button_test_event(event ElementEvent) {
	toggle_button_test_events << event
}

fn test_toggle_button_constructor_keeps_both_visual_states() {
	el := toggle_button(
		id:                 'bold'
		on_event:           capture_toggle_button_test_event
		title:              'Bold'
		frame:              rect(10, 20, 100, 40)
		pressed:            true
		group:              'format'
		allow_no_selection: false
		box:                BoxStyle{ bg: 0xe2e8f0, radius: 6 }
		down_box:           BoxStyle{ bg: 0x1d4ed8, radius: 6 }
		text_style:         TextStyle{ color: 0x1e293b }
		down_text_style:    TextStyle{ color: 0xffffff, bold: true }
	)
	assert el.kind == .toggle_button
	toggle_button_test_events = []ElementEvent{}
	el.on_event(ElementEvent{ kind: .change, id: el.id, checked: el.checked })
	assert toggle_button_test_events.len == 1
	assert toggle_button_test_events[0].id == el.id
	assert toggle_button_test_events[0].kind == .change
	assert toggle_button_test_events[0].checked
	assert el.checked
	assert el.toggle_group == 'format'
	assert !el.toggle_allow_no_selection
	assert el.box.bg == u32(0xe2e8f0)
	assert el.toggle_down_box.bg == u32(0x1d4ed8)
	assert el.toggle_down_text_style.bold
	assert el.accessibility_role == 'button'
	assert el.accessibility_label == 'Bold'
	assert el.accessibility_value == 'pressed'
}
