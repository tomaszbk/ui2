// vtest vflags: -gc boehm -d no_gc_thread_local_alloc
module ui2

fn test_horizontal_scroll_updates_retained_focus_and_reveals_both_axes() ! {
	pane := scroll_with_mode('pane', rect(10, 20, 100, 80), 0xffffff, .both, [
		button('action', 'Acción', rect(150, 110, 40, 20), BoxStyle{}, TextStyle{}),
	])
	mut manager := FocusManager{}
	mut offsets := {'root': 30.0}
	mut offsets_x := {'root': 50.0}
	manager.update_mounted_axes(pane, offsets, offsets_x, rect(0, 0, 400, 300), ContentTransform{})
	assert (manager.node('action') or { panic('missing action') }).frame == rect(110, 100, 40, 20)
	assert manager.set_focus('action')
	requests := manager.reveals('action')
	assert requests.len == 1
	assert requests[0].rect == rect(150, 110, 40, 20)
	registry := manager.nodes.data
	serial := manager.geometry_serial
	before := gc_allocation_snapshot()!
	for _ in 0 .. 100 {
		manager.update_mounted_axes(pane, offsets, offsets_x, rect(0, 0, 400, 300), ContentTransform{})
	}
	delta := gc_allocation_snapshot()!.delta_since(before)
	assert delta.allocated_bytes == 0
	assert delta.collections == 0
	assert manager.geometry_serial == serial
	assert manager.nodes.data == registry
	offsets_x['root'] = 90
	offsets['root'] = 50
	manager.update_mounted_axes(pane, offsets, offsets_x, rect(0, 0, 400, 300), ContentTransform{})
	assert manager.current == 'action'
	assert manager.nodes.data == registry
	assert (manager.node('action') or { panic('missing action') }).frame == rect(70, 80, 40, 20)
}

fn test_horizontal_nested_reveals_preserve_outer_two_axis_content_coordinates() {
	inner := scroll_with_mode('inner', rect(220, 140, 100, 80), 0xffffff, .both, [
		button('action', 'Action', rect(150, 110, 40, 20), BoxStyle{}, TextStyle{}),
	])
	outer := scroll_with_mode('outer', rect(10, 20, 180, 120), 0xffffff, .both, [inner])
	mut manager := FocusManager{}
	manager.update_mounted_axes(outer, {'root': 40.0, 'root/i:0': 30.0},
		{'root': 50.0, 'root/i:0': 50.0}, rect(0, 0, 500, 400), ContentTransform{})
	requests := manager.reveals('action')
	assert requests.len == 2
	assert requests[0].id == 'inner'
	assert requests[0].rect == rect(150, 110, 40, 20)
	assert requests[1].id == 'outer'
	assert requests[1].rect == rect(280, 200, 40, 20)
}
