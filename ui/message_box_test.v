@[has_globals]
module ui2

__global message_box_test_events = []ElementEvent{}
__global message_box_test_callbacks = []string{}

fn capture_message_box_test_event(event ElementEvent) {
	message_box_test_events << event
}

fn test_every_button_set_maps_titles_onto_results() {
	sets := [MessageBoxButtons.ok, .ok_cancel, .yes_no, .yes_no_cancel, .retry_cancel]
	for buttons in sets {
		titles := message_box_button_titles(buttons)
		results := message_box_results(buttons)
		assert titles.len == results.len
		assert titles.len > 0
		// A dismissed dialog has to answer like the last, least destructive
		// button, which is what every backend falls back to.
		assert message_box_default_result(buttons) == results[results.len - 1]
		for index, result in results {
			assert message_box_result_at(buttons, index) == result
		}
	}
}

fn test_out_of_range_button_index_falls_back_to_dismissal() {
	assert message_box_result_at(.yes_no_cancel, -1) == .cancel
	assert message_box_result_at(.yes_no_cancel, 3) == .cancel
	assert message_box_result_at(.yes_no, 1) == .no
	assert message_box_result_at(.ok, 0) == .ok
}

fn test_custom_message_box_centres_the_card_and_stacks_buttons_from_the_right() {
	overlay := custom_message_box(
		id:      'confirm'
		frame:   rect(0, 0, 400, 300)
		title:   'Delete file?'
		text:    'This cannot be undone.'
		actions: [
			MessageBoxAction{
				id:       'confirm_delete'
				on_event: fn (event ElementEvent) {
					message_box_test_callbacks << 'confirm'
					message_box_test_events << event
				}
				title:    'Delete'
			},
			MessageBoxAction{
				id:       'confirm_keep'
				on_event: fn (event ElementEvent) {
					message_box_test_callbacks << 'dismiss'
					message_box_test_events << event
				}
				title:    'Cancel'
			},
		]
	)
	validate_element_tree(overlay) or { panic(err) }

	assert overlay.id == 'confirm'
	assert !overlay.hidden
	assert overlay.frame == rect(0, 0, 400, 300)

	dialog := overlay.children[0]
	assert dialog.id == 'confirm_dialog'
	assert dialog.frame == rect(50, 75, 300, 150)
	assert dialog.box.radius == 12

	assert dialog.children[0].text == 'Delete file?'
	assert dialog.children[0].text_style.bold
	assert dialog.children[1].text == 'This cannot be undone.'

	delete_button := dialog.children[2]
	cancel_button := dialog.children[3]
	assert delete_button.id == 'confirm_delete'
	assert delete_button.native_style
	message_box_test_events = []ElementEvent{}
	message_box_test_callbacks = []string{}
	delete_button.on_event(ElementEvent{ kind: .tap, id: delete_button.id })
	assert delete_button.frame == rect(200, 98, 80, 32)
	assert cancel_button.id == 'confirm_keep'
	cancel_button.on_event(ElementEvent{ kind: .tap, id: cancel_button.id })
	assert message_box_test_callbacks == ['confirm', 'dismiss']
	assert message_box_test_events[0].id == 'confirm_delete'
	assert message_box_test_events[1].id == 'confirm_keep'
	assert cancel_button.frame == rect(108, 98, 80, 32)
}

fn test_custom_message_box_names_unlabelled_actions_after_the_overlay() {
	overlay := custom_message_box(
		frame:   rect(0, 0, 200, 200)
		hidden:  true
		actions: [MessageBoxAction{
			title: 'OK'
		}]
	)
	assert overlay.id == 'message_box'
	assert overlay.hidden
	assert overlay.children[0].children[2].id == 'message_box_action_0'
}

fn test_vml_message_box_turns_button_children_into_dialog_actions() {
	root := compiled_message_box_0(rect(0, 0, 400, 300), ElementCallback(capture_message_box_test_event))
	validate_element_tree(root) or { panic(err) }

	overlay := root.children[0]
	assert overlay.id == 'overlay'
	assert overlay.frame == rect(0, 0, 400, 300)

	dialog := overlay.children[0]
	assert dialog.frame == rect(70, 80, 260, 140)
	assert dialog.children[0].text == 'Hello'
	assert dialog.children[1].text == 'World'
	// The Button child becomes an action, not a free-standing view.
	assert dialog.children.len == 3
	assert dialog.children[2].id == 'close'
	assert dialog.children[2].on_event != unsafe { nil }
	assert dialog.children[2].native_style
	message_box_test_events = []ElementEvent{}
	action := dialog.children[2]
	action.on_event(ElementEvent{ kind: .tap, id: action.id })
	assert message_box_test_events.len == 1
	assert message_box_test_events[0].kind == .tap
	assert message_box_test_events[0].id == 'close'
}

fn compiled_message_box_0(frame Rect, callback_dismiss ElementCallback) Element {
	return $vml('fixtures/message_box_0.vml', frame)
}
