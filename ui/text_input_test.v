module ui2

fn test_text_area_preserves_multiline_content_and_events() {
	el := text_area(
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

fn test_text_input_defaults_to_single_line() {
	el := text_input(text: 'José', placeholder: 'Name') or { panic(err) }
	assert el.kind == .text_field
	assert el.text == 'José'
	assert el.placeholder == 'Name'
	assert el.enabled && el.autocorrect
	assert !el.secure && !el.readonly && !el.disable_scroll
	assert el.text_runs.len == 0
}

fn test_text_input_single_line_supports_submit_and_password() {
	el := text_input(
		id:           'password'
		frame:        rect(0, 0, 200, 36)
		text:         'secret'
		placeholder:  'Password'
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
		id:       'preview'
		frame:    rect(0, 0, 200, 36)
		readonly: true
		enabled:  false
	) or { panic(err) }
	assert el.kind == .text_field
	assert el.readonly
	assert !el.enabled
}

fn test_text_area_preserves_disabled_editing_and_keyboard_configuration() {
	el := text_area(
		readonly:     true
		enabled:      false
		autocorrect:  false
		keyboard:     2
		padding_left: 8
	) or { panic(err) }
	assert el.kind == .text_area
	assert el.readonly && !el.enabled && !el.autocorrect
	assert el.keyboard == 2 && el.padding_left == 8
	assert !el.secure
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

fn test_text_area_preserves_rich_runs_and_disables_scroll() {
	runs := [TextRun{ text: 'Hello', style: TextStyle{ weight: 700 } },
		TextRun{ text: ' world', style: TextStyle{ italic: true } }]
	input := text_area(
		id:             'body'
		text:           'Hello world'
		text_runs:      runs
		readonly:       true
		disable_scroll: true
		on_event:       fn (_ ElementEvent) {}
	)!
	assert input.kind == .text_area
	assert input.text_runs == runs
	assert input.readonly
	assert input.disable_scroll
	assert voidptr(input.on_event) != unsafe { nil }
}

fn test_compiled_text_input_text_area_and_scroll_keep_distinct_controls() {
	mut invoked := &[]string{}
	changed := fn [mut invoked] (event ElementEvent) { invoked << 'changed:${event.text}' }
	submit := fn [mut invoked] (event ElementEvent) { invoked << 'submit:${event.text}' }
	field := compiled_text_input_3(rect(0, 0, 180, 32), changed, submit)
	assert field.kind == .text_field
	assert field.placeholder == 'Name'
	assert voidptr(field.on_event) != unsafe { nil }
	field.on_event(ElementEvent{ kind: .change, text: 'José' })
	field.on_event(ElementEvent{ kind: .submit, text: 'José' })
	assert *invoked == ['changed:José', 'submit:José']
	area := compiled_text_input_2(rect(0, 0, 180, 100))
	assert area.kind == .text_area
	assert area.readonly
	assert area.disable_scroll
	viewport := compiled_text_input_1(rect(0, 0, 180, 100))
	assert viewport.kind == .scroll
}

pub struct InputRoutingItem {
pub:
	id int
}

pub struct InputRoutingModel {
pub mut:
	items    []InputRoutingItem
	selected int
}

pub fn (mut model InputRoutingModel) select(id int) {
	model.selected = id
}

fn test_text_input_repeated_actions_keep_identity_separate_from_routing() {
	mut app := InputRoutingModel{
		items: [InputRoutingItem{ id: 1 }, InputRoutingItem{ id: 2 }]
	}
	root := $vml('fixtures/text_input_routing.vml', rect(0, 0, 200, 100))
	assert root.children.len == 2
	assert root.children[0].key == '1'
	assert root.children[1].key == '2'
	assert root.children[0].key != root.children[1].key
	root.children[1].on_event(ElementEvent{ kind: .change })
	assert app.selected == 2
	root.children[0].on_event(ElementEvent{ kind: .change })
	assert app.selected == 1
}

fn test_vml_text_area_preserves_rich_runs_and_typography_inheritance() {
	input := compiled_text_input_0(rect(0, 0, 240, 100))
	assert input.kind == .text_area
	assert input.text == 'Hola ñ'
	assert input.text_runs.len == 2
	assert input.text_runs[0].style.weight == 700
	assert input.text_runs[1].style.italic
	assert input.text_runs[1].style.size == 18
	assert input.text_runs[1].style.color == u32(0x123456)
	assert input.readonly
	assert input.disable_scroll
}

fn compiled_text_input_0(frame Rect) Element {
	return $vml('fixtures/text_input_0.vml', frame)
}

fn compiled_text_input_1(frame Rect) Element {
	return $vml('fixtures/text_input_1.vml', frame)
}

fn compiled_text_input_2(frame Rect) Element {
	return $vml('fixtures/text_input_2.vml', frame)
}

fn compiled_text_input_3(frame Rect, callback_changed ElementCallback, callback_submit ElementCallback) Element {
	return $vml('fixtures/text_input_3.vml', frame)
}
