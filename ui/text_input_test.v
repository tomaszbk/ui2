module ui2

fn test_text_input_defaults_to_multiline_editor() {
	el := text_input(
		id:          'notes'
		frame:       rect(0, 0, 240, 120)
		text:        'One\nTwo'
		placeholder: 'Notes'
		on_event:    fn (_ ElementEvent) {}
	) or { panic(err) }
	assert el.kind == .text_area
	assert el.text == 'One\nTwo'
	assert el.placeholder == 'Notes'
	assert voidptr(el.on_event) != unsafe { nil }
}

fn test_text_input_single_line_supports_submit_and_password() {
	el := text_input(
		id:           'password'
		frame:        rect(0, 0, 200, 36)
		text:         'secret'
		placeholder:  'Password'
		multiline:    false
		password:     true
		on_event:     fn (_ ElementEvent) {}
		autocorrect:  false
		padding_left: 8
	) or { panic(err) }
	assert el.kind == .text_field
	assert el.secure
	assert voidptr(el.on_event) != unsafe { nil }
	assert !el.autocorrect
	assert el.padding_left == 8
}

fn test_text_input_preserves_readonly_and_disabled_state() {
	el := text_input(
		id:        'preview'
		frame:     rect(0, 0, 200, 36)
		multiline: false
		readonly:  true
		enabled:   false
	) or { panic(err) }
	assert el.kind == .text_field
	assert el.readonly
	assert !el.enabled
}

fn test_text_input_rejects_multiline_password_mode() {
	if _ := text_input(TextInputConfig{ password: true }) {
		assert false, 'multiline secure entry must fail explicitly'
	} else {
		assert err.msg().contains('single-line')
	}
}

fn test_single_line_content_viewport_respects_padding_and_parent_clip() {
	content := text_field_content_rect(rect(20, 30, 100, 36), 12)
	assert content == rect(32, 32, 80, 32)
	assert intersect_rect(content, rect(40, 40, 200, 100)) == rect(40, 40, 72, 24)
	assert intersect_rect(content, rect(0, 0, 10, 10)).width == 0
	assert text_field_content_rect(rect(20, 30, 100, 36), -5) == rect(20, 32, 92, 32)
}

fn test_single_line_content_viewport_clamps_empty_and_tiny_controls() {
	for frame in [rect(0, 0, 0, 0), rect(0, 0, 10, 3), rect(0, 0, -10, -10)] {
		content := text_field_content_rect(frame, 12)
		assert content.width == 0
		assert content.height == 0
	}
	assert text_field_content_rect(rect(0, 0, 20, 36), 30).width == 0
}

fn test_text_input_rich_multiline_preserves_runs_and_disables_scroll() {
	runs := [TextRun{ text: 'Hello', style: TextStyle{ weight: 700 } },
		TextRun{ text: ' world', style: TextStyle{ italic: true } }]
	input := text_input(
		id:             'body'
		text:           'Hello world'
		text_runs:      runs
		multiline:      true
		readonly:       true
		disable_scroll: true
		on_event:       fn (_ ElementEvent) {}
	)!
	assert input.kind == .text_area
	assert input.text_runs == runs
	assert input.readonly
	assert input.disable_scroll
	assert voidptr(input.on_event) != unsafe { nil }
	if _ := text_input(text_runs: runs, multiline: false) {
		assert false
	}
}

fn test_text_input_and_scroll_are_the_only_input_and_scroll_vml_names() {
	for tag in ['TextField', 'TextArea', 'ScrollView'] {
		if _ := parse_vml('${tag} {}') {
			assert false, 'removed tag must be rejected'
		}
	}
	for property in ['hint_text: "Name"', 'on_text: changed', 'on_text_validate: submit',
		'editable: false', 'emit_change: true'] {
		if _ := parse_vml('TextInput { ${property} }') {
			assert false, 'removed property must be rejected'
		}
	}
	field := element_from_vml_with_callbacks('TextInput { id: name multiline: false placeholder: "Name" on_change: changed on_submit: submit }', rect(0, 0, 180, 32), {
		'changed': fn (_ ElementEvent) {}
		'submit':  fn (_ ElementEvent) {}
	})!
	assert field.kind == .text_field
	assert field.placeholder == 'Name'
	assert voidptr(field.on_event) != unsafe { nil }
	assert voidptr(field.on_event) != unsafe { nil }
	area := element_from_vml('TextInput { multiline: true readonly: true disable_scroll: true }', rect(0, 0, 180, 100))!
	assert area.kind == .text_area
	assert area.readonly
	assert area.disable_scroll
	viewport := element_from_vml('Scroll { id: pane }', rect(0, 0, 180, 100))!
	assert viewport.kind == .scroll
}

struct InputRoutingItem {
pub:
	id int
}

struct InputRoutingModel {
pub mut:
	items    []InputRoutingItem
	selected int
}

pub fn (mut model InputRoutingModel) select(id int) {
	model.selected = id
}

fn test_text_input_repeated_actions_keep_identity_separate_from_routing() {
	source := 'Column { Repeater { model: app.items key: item.id
		TextInput { multiline: false width: 100 height: 32 on_change: app.select(item.id) }
	} }'
	mut app := new_vml_app(source, InputRoutingModel{
		items: [InputRoutingItem{ id: 1 }, InputRoutingItem{ id: 2 }]
	})!
	root := app.build(rect(0, 0, 200, 100))!
	assert root.children.len == 2
	assert root.children[0].key == '1'
	assert root.children[1].key == '2'
	assert root.children[0].key != root.children[1].key
	root.children[1].on_event(ElementEvent{ kind: .change })
	assert app.state().selected == 2
	root.children[0].on_event(ElementEvent{ kind: .change })
	assert app.state().selected == 1
}

fn test_vml_text_input_preserves_rich_runs_and_typography_inheritance() {
	input := element_from_vml('TextInput { id: rich readonly: true disable_scroll: true
		font_size: 18 color: #123456
		Run { text: "Hola " weight: 700 }
		Run { text: "ñ" italic: true }
	}', rect(0, 0, 240, 100))!
	assert input.kind == .text_area
	assert input.text == 'Hola ñ'
	assert input.text_runs.len == 2
	assert input.text_runs[0].style.weight == 700
	assert input.text_runs[1].style.italic
	assert input.text_runs[1].style.size == 18
	assert input.text_runs[1].style.color == u32(0x123456)
	assert input.readonly
	assert input.disable_scroll
	if _ := element_from_vml('TextInput { multiline: false Run { text: "Rich" } }', rect(0, 0, 240, 32)) {
		assert false, 'rich input requires multiline'
	}
}
