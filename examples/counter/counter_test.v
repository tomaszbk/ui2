module main

import ui2

fn counter_panels(root ui2.Element) []ui2.Element {
	return root.children[0].children[0].children
}

fn counter_value(panel ui2.Element) string { return panel.children[1].text }

fn counter_double(panel ui2.Element) string { return panel.children[2].text }

fn counter_add(panel ui2.Element) ui2.Element { return panel.children[3].children[0] }

fn counter_reset(panel ui2.Element) ui2.Element { return panel.children[3].children[1] }

fn test_counter_instances_keep_state_computed_events_and_lifecycle_independent() {
	mut app := CounterApp{}
	root := counter_tree(mut app, ui2.rect(0, 0, counter_width, counter_height))
	ui2.validate_element_tree(root) or { panic(err) }
	mut retained := root.compiled_node
	assert retained != unsafe { nil }
	retained.mount() or { panic(err) }
	retained.mount() or { panic(err) }
	assert app.mounted == 2
	initial := counter_panels(retained.element())
	assert initial.len == 2
	assert initial[0].id != initial[1].id
	assert initial[0].children[0].text == 'First'
	assert initial[1].children[0].text == 'Second'
	assert counter_value(initial[0]) == '0'
	assert counter_value(initial[1]) == '0'
	creation := retained.component.runtime.stats()
	left_add := counter_add(initial[0])
	assert left_add.native_style
	left_add.on_event(ui2.ElementEvent{ kind: .tap, id: left_add.id })
	left_add.on_event(ui2.ElementEvent{ kind: .tap, id: left_add.id })
	after_left := counter_panels(retained.element())
	assert counter_value(after_left[0]) == '2'
	assert counter_double(after_left[0]) == '4'
	assert counter_value(after_left[1]) == '0'
	assert app.events == 2
	assert app.last_value == 2
	assert retained.element().children[0].children[1].text == 'First counter emitted 2 events; its latest value is 2.'
	assert app.mounted == 2
	// The second instance has no changed handler; emitting is a valid no-op.
	right_add := counter_add(after_left[1])
	right_add.on_event(ui2.ElementEvent{ kind: .tap, id: right_add.id })
	after_right := counter_panels(retained.element())
	assert counter_value(after_right[0]) == '2'
	assert counter_value(after_right[1]) == '1'
	assert counter_double(after_right[1]) == '2'
	assert app.events == 2
	reset := counter_reset(after_right[0])
	reset.on_event(ui2.ElementEvent{ kind: .tap, id: reset.id })
	after_reset := counter_panels(retained.element())
	assert counter_value(after_reset[0]) == '0'
	assert counter_double(after_reset[0]) == '0'
	assert counter_value(after_reset[1]) == '1'
	assert app.events == 3
	assert app.last_value == 0
	assert retained.element().children[0].children[1].text == 'First counter emitted 3 events; its latest value is 0.'
	assert after_reset[0].id == initial[0].id
	assert after_reset[1].id == initial[1].id
	after_actions := retained.component.runtime.stats()
	assert after_actions.signals == creation.signals
	assert after_actions.memos == creation.memos
	assert after_actions.effects == creation.effects
	assert after_actions.scopes == creation.scopes
	mut owner := retained.component
	owner.dispose() or { panic(err) }
	owner.dispose() or { panic(err) }
	assert app.cleaned == 2
	assert app.unmounted == 2
	left_add.on_event(ui2.ElementEvent{ kind: .tap, id: left_add.id })
	assert app.events == 3
}
