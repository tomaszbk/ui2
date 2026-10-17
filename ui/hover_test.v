module ui2

fn hover_test_targets(ids []string) []HoverTarget {
	return ids.map(HoverTarget{
		identity: 'root/' + it
		id:       it
	})
}

fn test_hover_transitions_follow_dom_order() {
	mut left, mut entered := hover_transitions([]HoverTarget{}, hover_test_targets([
		'list',
		'row:2',
	]))
	assert left.len == 0
	assert entered.map(it.id) == ['list', 'row:2']
	left, entered = hover_transitions(hover_test_targets(['list', 'row:2']), hover_test_targets([
		'list',
		'row:3',
	]))
	assert left.map(it.id) == ['row:2']
	assert entered.map(it.id) == ['row:3']
	left, entered = hover_transitions(hover_test_targets(['list', 'row:3', 'button']), []HoverTarget{})
	assert left.map(it.id) == ['button', 'row:3', 'list']
	assert entered.len == 0
	left, entered = hover_transitions(hover_test_targets(['a', 'b']), hover_test_targets([
		'a',
		'b',
	]))
	assert left.len == 0 && entered.len == 0
}

fn test_hover_identity_survives_rebuilds_and_tells_equal_ids_apart() {
	// The same element rebuilt with a fresh callback is still hovered.
	before := [HoverTarget{
		identity: 'root/0'
		id:       'row'
	}]
	after_rebuild := [HoverTarget{
		identity: 'root/0'
		id:       'row'
		on_event: fn (_ ElementEvent) {}
	}]
	mut left, mut entered := hover_transitions(before, after_rebuild)
	assert left.len == 0 && entered.len == 0
	// Two elements at different places are different even with one id.
	moved := [HoverTarget{
		identity: 'root/1'
		id:       'row'
	}]
	left, entered = hover_transitions(before, moved)
	assert left.len == 1 && entered.len == 1
}

@[heap]
struct HoverTestLog {
mut:
	events []string
}

fn test_hover_events_reach_the_callbacks_leaves_first() {
	mut log := &HoverTestLog{}
	callback := fn [mut log] (event ElementEvent) {
		log.events << '${event.kind}:${event.id}:${event.x}:${event.y}'
	}
	row := Element{
		...with_hover(view('row', rect(0, 0, 10, 10), BoxStyle{}, []Element{}))
		on_event: callback
	}
	target := hover_target('root/0', row) or { panic('row is hoverable') }
	assert target.id == 'row'
	// Only hoverable, shown elements with a callback take part.
	assert hover_target('root/0', Element{ ...row, hoverable: false }) == none
	assert hover_target('root/0', Element{ ...row, hidden: true }) == none
	assert hover_target('root/0', Element{ ...row, on_event: unsafe { nil } }) == none
	other := HoverTarget{
		identity: 'root/1'
		id:       'cell'
		on_event: callback
	}
	w := &Window{}
	for pending in hover_events([other], [target], 3, 4) {
		pending.fire(w)
	}
	assert log.events == ['pointer_leave:cell:3.0:4.0', 'pointer_enter:row:3.0:4.0']
	// A target without a callback is skipped.
	PendingHoverEvent{}.fire(w)
	assert log.events.len == 2
}

fn test_with_hover_marks_only_hover() {
	el := with_hover(label('l', 'text', rect(0, 0, 10, 10), TextStyle{}))
	assert el.hoverable
	assert el.kind == .label
	assert el.text == 'text'
}
