// vtest vflags: -gc boehm -d no_gc_thread_local_alloc
module ui2

fn test_focus_refresh_preserves_static_subtree_and_updates_semantic_values() {
	static_group := view('static', rect(0, 20, 100, 80), BoxStyle{}, [
		button('action', 'Action', rect(0, 0, 40, 20), BoxStyle{}, TextStyle{}),
	])
	before := view('root', rect(0, 0, 100, 100), BoxStyle{}, [
		label('counter', '0', rect(0, 0, 20, 20), TextStyle{}),
		static_group,
	])
	mut manager := FocusManager{}
	manager.update(before, map[string]f64{})
	registry := manager.nodes.data
	assert manager.set_focus('action')
	after := Element{
		...before
		children: [
			Element{ ...before.children[0], text: '1' },
			static_group,
		]
	}
	manager.update(after, map[string]f64{})
	assert manager.nodes.data == registry
	assert manager.current == 'action'
	assert (manager.node('counter') or { panic('missing focus node') }).el.text == '1'
	assert (manager.node('action') or { panic('missing focus node') }).frame == rect(0, 20, 40, 20)
	// A same-size reorder must rebuild tree order, even though geometry and ids
	// independently survived the change.
	manager.update(Element{ ...after, children: [static_group, after.children[0]] }, map[string]f64{})
	assert manager.nodes[1].el.id == 'static'
	assert (manager.node('counter') or { panic('missing focus node') }).el.text == '1'
}

fn test_focus_refresh_reprojects_retained_children_after_scroll_or_disable() {
	pane := Element{
		...view('pane', rect(0, 0, 80, 80), BoxStyle{}, [
			button('action', 'Action', rect(0, 30, 40, 20), BoxStyle{}, TextStyle{}),
		])
		kind: .scroll
	}
	mut manager := FocusManager{}
	manager.update(pane, map[string]f64{})
	manager.update(pane, {
		'root': 10.0
	})
	assert (manager.node('action') or { panic('missing focus node') }).frame.y == 20
	manager.update(Element{ ...pane, enabled: false }, {
		'root': 10.0
	})
	assert !manager.can_focus('action')
	manager.update(pane, {
		'root': 20.0
	})
	assert manager.can_focus('action')
	assert (manager.node('action') or { panic('missing focus node') }).frame.y == 10
}

fn test_zero_size_scaled_subtree_keeps_later_focus_siblings_mounted() {
	composition := scaled_content('composition', rect(0, 0, 100, 80), 100, 80,
		BoxStyle{}, [button('inside', 'Inside', rect(0, 0, 30, 20), BoxStyle{}, TextStyle{})])
	later := button('later', 'Later', rect(120, 0, 50, 20), BoxStyle{}, TextStyle{})
	root := view('root', rect(0, 0, 200, 100), BoxStyle{}, [composition, later])
	mut manager := FocusManager{}
	manager.update(root, map[string]f64{})
	assert manager.set_focus('later')
	collapsed := Element{
		...root
		children: [
			Element{ ...composition, frame: rect(0, 0, 0, 80) },
			later,
		]
	}
	manager.update(collapsed, map[string]f64{})
	assert manager.current == 'later'
	assert manager.can_focus('later')
	assert manager.node('composition') != none
	assert manager.node('inside') == none
	manager.update(root, map[string]f64{})
	assert manager.current == 'later'
	assert manager.can_focus('inside')
}

fn test_focus_geometry_reuses_stable_scroll_offsets_without_allocating() ! {
	pane := scroll('pane', rect(0, 0, 80, 80), 0xffffff, [
		button('action', 'España', rect(0, 30, 40, 20), BoxStyle{}, TextStyle{}),
	])
	mut offsets := {
		'root':            10.0
		'not-yet-mounted': 20.0
	}
	mut manager := FocusManager{}
	manager.update(pane, offsets)
	serial := manager.geometry_serial
	registry := manager.nodes.data
	before := gc_allocation_snapshot()!
	for _ in 0 .. 100 {
		manager.update(pane, offsets)
	}
	delta := gc_allocation_snapshot()!.delta_since(before)
	assert delta.allocated_bytes == 0
	assert delta.collections == 0
	assert manager.geometry_serial == serial
	assert manager.nodes.data == registry
	assert (manager.node('action') or { panic('missing action') }).frame.y == 20
	// Equal-size key substitutions and values on unmounted paths still replace
	// the complete offsets snapshot, so future mounts see the current values.
	offsets.delete('not-yet-mounted')
	offsets['future'] = 25.0
	manager.update(pane, offsets)
	assert manager.geometry_serial == serial + 1
	assert 'not-yet-mounted' !in manager.scroll_offsets
	assert manager.scroll_offsets['future'] == 25
	offsets['root'] = 20.0
	manager.update(pane, offsets)
	assert (manager.node('action') or { panic('missing action') }).frame.y == 10
	stable_before := gc_allocation_snapshot()!
	for _ in 0 .. 100 { manager.update(pane, offsets) }
	stable_delta := gc_allocation_snapshot()!.delta_since(stable_before)
	assert stable_delta.allocated_bytes == 0
	assert stable_delta.collections == 0
}
