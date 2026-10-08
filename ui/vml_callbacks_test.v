module ui2

struct CallbackApp {
pub mut:
	count   int
	name    string
	level   f64
	checked bool
}

pub fn (mut app CallbackApp) increment() { app.count++ }

pub fn (mut app CallbackApp) select(value int) { app.count = value }

fn test_app_element_callback_mutates_live_model() {
	mut app := new_vml_app('Button { on_tap: app.increment() }', CallbackApp{}) or { panic(err) }
	root := app.build(rect(0, 0, 100, 40)) or { panic(err) }
	root.on_event(ElementEvent{ kind: .tap })
	assert app.state().count == 1
}

fn test_static_callbacks_are_explicit_and_receive_pointer_payloads() {
	mut seen := &[]ElementEvent{}
	callback := fn [mut seen] (event ElementEvent) { seen << event }
	root := element_from_vml_with_callbacks('Absolute {
		View { id: same on_tap: move draggable: true }
		View { id: inert }
	}', rect(0, 0, 100, 100), {
		'move': callback
	}) or { panic(err) }
	root.children[0].on_event(ElementEvent{ kind: .pointer_drag, id: 'same', x: 12.5, y: 9.25 })
	assert seen.len == 1
	assert (*seen)[0].kind == .pointer_drag
	assert (*seen)[0].id == 'same'
	assert (*seen)[0].x == 12.5
	assert (*seen)[0].y == 9.25
	assert voidptr(root.children[1].on_event) == unsafe { nil }
}

fn test_binding_payload_is_applied_before_actions_and_submit_is_separate() {
	mut app := new_vml_app('TextInput { id: input multiline: false bind.text: app.name
		on_change: app.count = app.name.len on_submit: app.increment()
	}', CallbackApp{}) or { panic(err) }
	root := app.build(rect(0, 0, 100, 32)) or { panic(err) }
	root.on_event(ElementEvent{ kind: .change, text: 'ñandú' })
	assert app.state().name == 'ñandú'
	assert app.state().count == 5
	root.on_event(ElementEvent{ kind: .submit, text: 'ñandú' })
	assert app.state().count == 6
}

struct CallbackItem {
pub:
	id    int
	value int
}

struct CallbackListApp {
pub mut:
	items    []CallbackItem
	selected int
}

pub fn (mut app CallbackListApp) select(value int) { app.selected = value }

fn test_retained_callback_captures_rendered_repeater_record_after_rebuild() {
	mut app := new_vml_app('Column { Repeater { model: app.items key: item.id
		Button { text: item.id on_tap: app.select(item.value) }
	} }', CallbackListApp{ items: [CallbackItem{ id: 1, value: 11 }, CallbackItem{ id: 2, value: 22 }] }) or { panic(err) }
	first := app.build(rect(0, 0, 100, 100)) or { panic(err) }
	old_callback := first.children[1].on_event
	app.model.items = [CallbackItem{ id: 2, value: 222 }, CallbackItem{ id: 1, value: 111 }]
	second := app.build(rect(0, 0, 100, 100)) or { panic(err) }
	assert second.children[0].key == first.children[1].key
	old_callback(ElementEvent{ kind: .tap })
	assert app.state().selected == 22
	second.children[0].on_event(ElementEvent{ kind: .tap })
	assert app.state().selected == 222
}

fn test_same_element_id_never_selects_a_callback() {
	mut events := &[]string{}
	callback := fn [mut events] (event ElementEvent) { events << event.id }
	root := element_from_vml_with_callbacks('Button { id: save }', rect(0, 0, 100, 40), {
		'save': callback
	}) or { panic(err) }
	assert voidptr(root.on_event) == unsafe { nil }
	assert events.len == 0
}

fn test_model_tap_actions_do_not_run_for_undeclared_gestures() {
	mut app := new_vml_app('View { on_tap: app.increment() draggable: true }', CallbackApp{}) or { panic(err) }
	root := app.build(rect(0, 0, 100, 100)) or { panic(err) }
	root.on_event(ElementEvent{ kind: .pointer_drag })
	assert app.state().count == 0
	root.on_event(ElementEvent{ kind: .tap })
	assert app.state().count == 1
}

fn test_window_builder_reuses_the_live_embeddable_app_callbacks() {
	mut app := new_vml_app('Button { on_tap: app.increment() }', CallbackApp{}) or { panic(err) }
	mut runtime := vml_runtime()
	previous := runtime.controller
	runtime.controller = voidptr(app)
	defer { runtime.controller = previous }
	root := vml_controller_build[CallbackApp]()
	root.on_event(ElementEvent{ kind: .tap })
	assert app.state().count == 1
}

fn loop_named_callbacks(mut names []string) map[string]ElementCallback {
	mut callbacks := map[string]ElementCallback{}
	for name in ['first', 'second'] {
		callbacks[name] = fn [name, mut names] (event ElementEvent) {
			names << '${name}/${event.id}'
		}
	}
	return callbacks
}

fn test_named_callbacks_returned_from_a_loop_keep_their_capture_values() {
	mut names := []string{}
	root := element_from_vml_with_callbacks('Column {
		Button { id: one on_tap: first }
		Button { id: two on_tap: second }
	}', rect(0, 0, 100, 100), loop_named_callbacks(mut names)) or { panic(err) }
	root.children[0].on_event(ElementEvent{ kind: .tap, id: 'one' })
	root.children[1].on_event(ElementEvent{ kind: .tap, id: 'two' })
	assert names == ['first/one', 'second/two']
}

@[heap]
struct CallbackLifetimeRecord {
mut:
	names  []string
	events []ElementEvent
}

struct CallbackLifetimeModel {
pub:
	value int
}

fn callback_allocation_tree(value int) Element {
	mut source := 'Column {'
	for i in 0 .. 500 {
		source += 'Button { id: allocated_${i} text: app.value } '
	}
	source += '}'
	return element_from_vml_model(source, CallbackLifetimeModel{ value: value },
		rect(0, 0, 400, 10000)) or { panic(err) }
}

fn test_compound_named_and_model_callbacks_survive_tree_allocations_and_gc() {
	mut record := &CallbackLifetimeRecord{}
	mut callbacks := map[string]ElementCallback{}
	for name in ['primary', 'drag', 'change', 'submit'] {
		callbacks[name] = fn [name, mut record] (event ElementEvent) {
			record.names << name
			record.events << event
		}
	}
	direct := callbacks['primary'] or { panic('missing callback') }
	button := element_from_vml_with_callbacks('Button { id: button on_tap: primary }',
		rect(0, 0, 100, 40), callbacks) or { panic(err) }
	surface := element_from_vml_with_callbacks('View {
		id: surface on_tap: primary on_pointer_drag: drag
	}', rect(0, 0, 100, 100), callbacks) or { panic(err) }
	input := element_from_vml_with_callbacks('TextInput {
		id: input multiline: false on_change: change on_submit: submit
	}', rect(0, 0, 100, 40), callbacks) or { panic(err) }
	mut app := new_vml_app('Button { on_tap: app.increment() }', CallbackApp{}) or { panic(err) }
	model_button := app.build(rect(0, 0, 100, 40)) or { panic(err) }
	mut allocation_tree := callback_allocation_tree(0)
	for value in 1 .. 8 {
		allocation_tree = callback_allocation_tree(value)
	}
	assert allocation_tree.children.len == 500
	gc_collect()
	direct(ElementEvent{ kind: .tap, id: 'direct' })
	button.on_event(ElementEvent{ kind: .tap, id: button.id })
	surface.on_event(ElementEvent{ kind: .tap, id: surface.id })
	surface.on_event(ElementEvent{ kind: .pointer_drag, id: surface.id, x: 24.5, y: 31.75 })
	input.on_event(ElementEvent{ kind: .change, id: input.id, text: 'ñandú' })
	input.on_event(ElementEvent{ kind: .submit, id: input.id, text: 'ñandú' })
	model_button.on_event(ElementEvent{ kind: .tap })
	assert app.state().count == 1
	assert record.names == ['primary', 'primary', 'primary', 'drag', 'change', 'submit']
	assert record.events.map(it.id) == ['direct', 'button', 'surface', 'surface', 'input', 'input']
	assert record.events[3].kind == .pointer_drag
	assert record.events[3].x == 24.5
	assert record.events[3].y == 31.75
	assert record.events[4].kind == .change
	assert record.events[4].text == 'ñandú'
	assert record.events[5].kind == .submit
	assert record.events[5].text == 'ñandú'
}

struct BoundControlActionApp {
pub mut:
	checked  bool
	observed bool
	calls    int
}

pub fn (mut app BoundControlActionApp) changed() {
	app.calls++
	app.observed = app.checked
}

pub fn (mut app BoundControlActionApp) duplicate() {
	app.calls += 100
}

struct BoundControlCase {
	tag        string
	binding    string
	properties []string
}

fn test_boolean_binding_aliases_write_before_the_selected_action() {
	cases := [
		BoundControlCase{ tag: 'Checkbox', binding: 'checked', properties: ['on_tap', 'on_change'] },
		BoundControlCase{
			tag:        'Switch'
			binding:    'active'
			properties: ['on_active', 'on_change', 'on_tap']
		},
		BoundControlCase{
			tag:        'ToggleButton'
			binding:    'pressed'
			properties: ['on_state', 'on_change', 'on_tap']
		},
	]
	for fixture in cases {
		for property in fixture.properties {
			source := '${fixture.tag} { bind.${fixture.binding}: app.checked ${property}: app.changed() }'
			mut app := new_vml_app(source, BoundControlActionApp{}) or { panic(err) }
			root := app.build(rect(0, 0, 100, 40)) or { panic(err) }
			root.on_event(ElementEvent{ kind: .change, checked: true })
			assert app.state().checked, source
			assert app.state().observed, source
			assert app.state().calls == 1, source
			root.on_event(ElementEvent{ kind: .change, checked: false })
			assert !app.state().checked, source
			assert !app.state().observed, source
			assert app.state().calls == 2, source
		}
	}
}

fn test_boolean_binding_selects_one_action_when_aliases_are_declared_together() {
	for source in [
		'Checkbox { bind.checked: app.checked on_change: app.changed() on_tap: app.duplicate() }',
		'Switch { bind.active: app.checked on_active: app.changed() on_change: app.duplicate() }',
		'ToggleButton { bind.pressed: app.checked on_state: app.changed() on_tap: app.duplicate() }',
	] {
		mut app := new_vml_app(source, BoundControlActionApp{}) or { panic(err) }
		root := app.build(rect(0, 0, 100, 40)) or { panic(err) }
		root.on_event(ElementEvent{ kind: .change, checked: true })
		assert app.state().checked, source
		assert app.state().observed, source
		assert app.state().calls == 1, source
	}
}

fn test_checkbox_change_assignment_reads_the_written_binding() {
	mut app := new_vml_app('Checkbox { bind.checked: app.checked
		on_change: app.calls = app.checked ? 1 : 0
	}', BoundControlActionApp{}) or { panic(err) }
	root := app.build(rect(0, 0, 100, 40)) or { panic(err) }
	root.on_event(ElementEvent{ kind: .change, checked: true })
	assert app.state().checked
	assert app.state().calls == 1
}

fn test_named_scroll_callback_receives_identity_and_logical_offset_without_tap_fallback() {
	mut events := &[]ElementEvent{}
	mut tap_events := &[]ElementEvent{}
	root := element_from_vml_with_callbacks('Scroll {
		id: pane on_scroll: scroll_changed on_tap: tapped
	}', rect(0, 0, 100, 100), {
		'scroll_changed': fn [mut events] (event ElementEvent) { events << event }
		'tapped':         fn [mut tap_events] (event ElementEvent) { tap_events << event }
	}) or { panic(err) }
	root.on_event(ElementEvent{ kind: .scroll, id: root.id, value: 72.25 })
	assert events.len == 1
	assert (*events)[0].kind == .scroll
	assert (*events)[0].id == 'pane'
	assert (*events)[0].value == 72.25
	assert tap_events.len == 0
	inert := element_from_vml_with_callbacks('Scroll { id: pane on_tap: tapped }',
		rect(0, 0, 100, 100), {
			'tapped': fn [mut tap_events] (event ElementEvent) { tap_events << event }
		}) or { panic(err) }
	inert.on_event(ElementEvent{ kind: .scroll, id: inert.id, value: 72.25 })
	assert tap_events.len == 0
}

fn test_model_scroll_action_is_distinct_from_tap() {
	mut app := new_vml_app('Scroll {
		id: pane on_scroll: app.increment() on_tap: app.select(100)
	}', CallbackApp{}) or { panic(err) }
	root := app.build(rect(0, 0, 100, 100)) or { panic(err) }
	root.on_event(ElementEvent{ kind: .scroll, id: root.id, value: 72.25 })
	assert app.state().count == 1
	root.on_event(ElementEvent{ kind: .tap, id: root.id })
	assert app.state().count == 100
}

pub fn (mut app BoundControlActionApp) toggle() {
	app.checked = !app.checked
	app.calls++
}

fn test_unbound_boolean_control_default_actions_receive_semantic_changes() {
	for source in [
		'Checkbox { checked: app.checked on_tap: app.toggle() }',
		'Switch { active: app.checked on_tap: app.toggle() }',
		'ToggleButton { pressed: app.checked on_tap: app.toggle() }',
	] {
		mut app := new_vml_app(source, BoundControlActionApp{}) or { panic(err) }
		root := app.build(rect(0, 0, 100, 40)) or { panic(err) }
		root.on_event(ElementEvent{ kind: .change, checked: true })
		assert app.state().checked, source
		assert app.state().calls == 1, source
		root.on_event(ElementEvent{ kind: .change, checked: false })
		assert !app.state().checked, source
		assert app.state().calls == 2, source
		root.on_event(ElementEvent{ kind: .pointer_drag })
		assert app.state().calls == 2, source
	}
}
