@[has_globals]
module ui2

__global popup_test_events = []ElementEvent{}

fn capture_popup_test_event(event ElementEvent) {
	popup_test_events << event
}

fn test_popup_geometry_splits_title_separator_and_body() {
	geometry := popup_geometry(
		frame:            rect(0, 0, 500, 300)
		content_width:    320
		content_height:   200
		title_height:     48
		separator_height: 2
	) or { panic(err) }
	assert geometry.surface == rect(90, 50, 320, 200)
	assert geometry.title == rect(0, 0, 320, 48)
	assert geometry.separator == rect(0, 48, 320, 2)
	assert geometry.body == rect(0, 50, 320, 150)
}

fn test_popup_constructor_composes_modal_layers_and_body() {
	result := popup(
		id:               'editor'
		frame:            rect(0, 0, 500, 300)
		open:             true
		on_dismiss:       capture_popup_test_event
		content_width:    320
		content_height:   200
		title:            'Edit profile'
		title_height:     48
		separator_height: 2
		separator_box:    BoxStyle{ bg: 0xe2e8f0 }
		content:          view('form', rect(0, 0, 1, 1), BoxStyle{ transparent: true }, [])
	) or { panic(err) }
	assert !result.hidden
	popup_test_events = []ElementEvent{}
	backdrop := result.children[0]
	backdrop.on_event(ElementEvent{ kind: .tap, id: backdrop.id })
	assert popup_test_events.len == 1
	assert popup_test_events[0].id == backdrop.id
	assert popup_test_events[0].kind == .tap
	assert result.children[1].frame == rect(90, 50, 320, 200)
	surface_content := result.children[2]
	assert surface_content.frame == rect(90, 50, 320, 200)
	assert surface_content.children[0].text == 'Edit profile'
	assert surface_content.children[1].frame == rect(0, 48, 320, 2)
	assert surface_content.children[2].id == 'form'
	assert surface_content.children[2].frame == rect(0, 50, 320, 150)
}

fn test_popup_rejects_header_taller_than_surface() {
	if _ := popup_geometry(
		frame:          rect(0, 0, 300, 200)
		content_width:  200
		content_height: 40
		title_height:   48
	) {
		assert false, 'oversized popup header must fail'
	} else {
		assert err.msg().contains('exceed')
	}
}
