// vtest vflags: -d ui2_headless -gc boehm -d no_gc_thread_local_alloc
module ui2

fn test_overlay_idle_projection_reuses_layers_layout_and_geometry_without_allocating() ! {
	anchor := button('anchor', 'España ñ', rect(20, 20, 100, 30), BoxStyle{}, TextStyle{})
	surface := with_overlay(view('popover', rect(0, 0, 140, 80), BoxStyle{}, [
		Element{ kind: .text_field, id: 'draft', text: 'café', frame: rect(8, 8, 120, 28) },
	]), OverlayConfig{ open: true, anchor: 'anchor' })!
	root := Element{
		kind:     .screen
		id:       'root'
		frame:    rect(0, 0, 400, 300)
		children: [
			anchor,
			surface,
		]
	}
	viewport := rect(0, 0, 400, 300)
	offsets := map[string]f64{}
	mut tree := OverlayTree{}
	projected := tree.resolve(root, offsets, viewport, 0)!
	mut manager := FocusManager{}
	manager.update_mounted(projected, map[string]f64{}, viewport, ContentTransform{})
	registry := manager.nodes.data
	layers := tree.layers.data
	snapshot := tree.output.children.data
	layout := tree.layers[0].layout
	before := gc_allocation_snapshot()!
	for _ in 0 .. 1000 {
		stable := tree.resolve(root, offsets, viewport, 0)!
		manager.update_mounted(stable, offsets, viewport, ContentTransform{})
	}
	delta := gc_allocation_snapshot()!.delta_since(before)
	assert delta.allocated_bytes == 0
	assert delta.collections == 0
	assert tree.layers.data == layers && tree.output.children.data == snapshot
	assert tree.layers[0].layout == layout && manager.nodes.data == registry
}
