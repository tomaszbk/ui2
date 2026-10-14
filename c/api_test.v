module ui2_c

import ui2

struct Probe {
mut:
	invalid  bool
	builds   int
	events   []string
	payloads []ui2.ElementEvent
}

fn probe_build(data voidptr) &C.ui2_node {
	mut probe := unsafe { &Probe(data) }
	probe.builds++
	root := create(0, unsafe { nil }, 0, 0, 0, 0)
	text := create(2, c'label', 10, 20, 200, 30)
	mut buffer := [u8(`o`), `w`, `n`, `e`, `d`, 0]
	set_text(text, unsafe { &char(buffer.data) })
	buffer[0] = `X`
	set_events(text, probe_event, data)
	style := C.ui2_text_style{
		color:       0x123456
		size:        22
		font_family: c'Helvetica'
		bold:        1
		align:       2
		valign:      0
		lines:       3
	}
	set_text_style(text, &style)
	add(root, text)
	scroll := create(9, c'scroll', 0, 60, 300, 200)
	set_scroll_mode(scroll, 2)
	add(root, scroll)
	if probe.invalid { add(root, create(2, c'label', 0, 0, 1, 1)) }
	return root
}

fn probe_event(data voidptr, event &C.ui2_event) {
	mut probe := unsafe { &Probe(data) }
	probe.events << input(event.id)
	probe.payloads << ui2.ElementEvent{
		kind:    unsafe { ui2.ElementEventKind(event.kind) }
		id:      input(event.id)
		x:       event.x
		y:       event.y
		text:    input(event.text)
		value:   event.value
		checked: event.checked != 0
		target:  input(event.target)
	}
}

fn probe_key(data voidptr, key &char) {
	mut probe := unsafe { &Probe(data) }
	probe.events << input(key)
}

fn test_tree_copies_foreign_buffers_and_preserves_last_valid_build() {
	mut probe := &Probe{}
	config := C.ui2_config{
		build:     probe_build
		user_data: probe
		width:     640
		height:    480
	}
	assert configure(&config)
	defer { release_callbacks() }
	first := build_tree()
	assert first.children.len == 2
	label := first.children[0]
	assert label.text == 'owned'
	assert label.on_event != unsafe { nil }
	label.on_event(ui2.ElementEvent{ kind: .click, id: label.id })
	assert probe.events == ['label']
	assert probe.payloads[0].kind == ui2.ElementEventKind.click
	assert label.frame.x == 10
	assert label.text_style.color == 0x123456
	assert label.text_style.size == 22
	assert label.text_style.bold
	assert label.text_style.font_family == 'Helvetica'
	assert label.text_style.align == .right
	assert label.text_style.valign == .top
	assert label.text_style.lines == 3
	assert first.children[1].scroll_mode == .both
	assert !state().building
	assert state().nodes.len == 0
	mut width := 0.0
	mut height := 0.0
	bounds(&width, &height)
	assert width == 640
	assert height == 480
	probe.invalid = true
	rejected := build_tree()
	assert rejected == first
	assert state().last_error.contains('duplicate element id')
	probe.invalid = false
	recovered := build_tree()
	assert recovered.children[0].text == first.children[0].text
	assert recovered.children[0].frame == first.children[0].frame
	assert state().last_error == ''
	assert probe.builds == 3
}

fn test_event_handlers_and_flags_belong_to_each_declaration() {
	mut probe := &Probe{}
	config := C.ui2_config{ build: probe_build, user_data: probe }
	assert configure(&config)
	mut st := state()
	st.building = true
	st.generation++
	defer {
		st.building = false
		st.nodes = []&Node{}
		release_callbacks()
	}
	handle := create(1, c'pointer', 0, 0, 20, 20)
	set_flags(handle, 32 | 64 | 128 | 256)
	set_events(handle, probe_event, probe)
	n := node(handle) or { panic('missing node') }
	el := snapshot(n, 0) or { panic(err) }
	assert el.button_behavior && el.clickable && el.draggable && el.persistent_scrollbars
	el.on_event(ui2.ElementEvent{ kind: .pointer_drag, id: el.id, x: 12, y: 7 })
	assert probe.payloads.len == 1
	assert probe.payloads[0].kind == .pointer_drag
	assert probe.payloads[0].x == 12 && probe.payloads[0].y == 7
	set_events(handle, unsafe { nil }, unsafe { nil })
	detached := snapshot(n, 0) or { panic(err) }
	assert detached.on_event == unsafe { nil }
}

fn test_callbacks_forward_userdata_and_utf8_then_release_foreign_roots() {
	mut probe := &Probe{}
	config := C.ui2_config{
		build:     probe_build
		key:       probe_key
		user_data: probe
	}
	assert configure(&config)
	dispatch_element_event(probe_event, probe, ui2.ElementEvent{ kind: .change, id: 'save:世界', text: 'España', value: 12.5, checked: true, x: 4, y: 5, target: 'target' })
	dispatch_key('ctrl+s')
	dispatch_element_event(probe_event, probe, ui2.ElementEvent{ kind: .scroll, id: 'canvas', x: 42, y: 24, value: 24 })
	assert probe.payloads.len == 2
	assert probe.payloads[0].text == 'España'
	assert probe.payloads[0].kind == ui2.ElementEventKind.change
	assert probe.payloads[0].value == 12.5
	assert probe.payloads[0].checked
	assert probe.payloads[0].x == 4 && probe.payloads[0].y == 5
	assert probe.payloads[0].target == 'target'
	assert probe.payloads[1].x == 42
	assert probe.payloads[1].y == 24
	assert probe.events == ['save:世界', 'ctrl+s', 'canvas']
	release_callbacks()
	assert state().user_data == unsafe { nil }
	assert state().build == unsafe { nil }
	assert state().key == unsafe { nil }
}
