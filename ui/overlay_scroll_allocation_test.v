// vtest vflags: -gc boehm -d no_gc_thread_local_alloc -d ui2_headless
module ui2

fn overlay_scroll_measure(_text string, _style TextStyle, _width f64) !LayoutSize {
	return LayoutSize{ width: 80, height: 24 }
}

fn test_mounted_anchored_overlay_scroll_projection_allocates_nothing_after_warmup() ! {
	viewport := rect(0, 0, 400, 300)
	popover := with_overlay(view('popover', rect(0, 0, 140, 80), BoxStyle{}, [
		button('choice', 'Choice', rect(8, 8, 120, 28), BoxStyle{}, TextStyle{}),
	]), OverlayConfig{ anchor: 'anchor', open: true })!
	pane := Element{
		kind:     .scroll
		id:       'pane'
		frame:    rect(20, 20, 200, 140)
		children: [
			button('anchor', 'Open', rect(10, 70, 80, 24), BoxStyle{}, TextStyle{}),
			popover,
		]
	}
	mut layout := LayoutTree{}
	layout.replace(view('root', viewport, BoxStyle{}, [pane]))!
	source := layout.resolve(LayoutConstraints{}, overlay_scroll_measure, LayoutEnvironment{})!
	mut geometry := FocusManager{}
	mut offsets := map[string]f64{}
	geometry.update_mounted(source, offsets, viewport, ContentTransform{})
	path := (geometry.node('pane') or { panic('missing pane') }).path
	offsets[path] = 0
	mut portals := OverlayTree{ measure: overlay_scroll_measure }
	mut presented := FocusManager{}
	for offset in [0.0, 10.0, 0.0, 10.0] {
		offsets[path] = offset
		presented.update_mounted(portals.resolve(source, offsets, viewport, 0)!, offsets, viewport, ContentTransform{})
	}
	measure_before := portals.layers[0].layout.stats().measure_visits
	before := gc_allocation_snapshot()!
	for i in 0 .. 1000 {
		offsets[path] = if i % 2 == 0 { 0.0 } else { 10.0 }
		presented.update_mounted(portals.resolve(source, offsets, viewport, 0)!, offsets, viewport, ContentTransform{})
		assert portals.layers[0].frame == rect(30, if i % 2 == 0 { 120.0 } else { 110.0 }, 140, 80)
		assert portals.layers[0].active
	}
	delta := gc_allocation_snapshot()!.delta_since(before)
	assert portals.layers[0].layout.stats().measure_visits == measure_before
	assert delta.allocated_bytes == 0
	assert delta.collections == 0
}

fn test_overlay_motion_and_viewport_projection_reuses_dialog_backdrop_and_focus_slots() ! {
	mut motion := &ElementMotionState{ mounted: true, current: MotionSample{ phase: .present } }
	dialog := with_overlay(Element{
		...view('dialog', rect(0, 0, 140, 80), BoxStyle{}, [
			button('inside', 'Inside', rect(8, 8, 100, 24), BoxStyle{}, TextStyle{}),
		])
		runtime: &ElementRuntime{ motion_state: motion }
	}, OverlayConfig{ kind: .dialog, open: true, backdrop_opacity: 0.4 })!
	viewport := rect(0, 0, 400, 300)
	mut layout := LayoutTree{}
	layout.replace(view('root', viewport, BoxStyle{}, [dialog]))!
	source := layout.resolve(LayoutConstraints{}, overlay_scroll_measure, LayoutEnvironment{})!
	offsets := map[string]f64{}
	mut portals := OverlayTree{ measure: overlay_scroll_measure }
	mut focus := FocusManager{}
	for i in 0 .. 4 {
		frame := rect(0, 0, if i % 2 == 0 { 400.0 } else { 410.0 }, 300)
		focus.update_mounted(portals.resolve(source, offsets, frame, u64(i + 1))!, offsets, frame, ContentTransform{})
	}
	measure_before := portals.layers[0].layout.stats().measure_visits
	registry := focus.nodes.data
	before := gc_allocation_snapshot()!
	for i in 0 .. 1000 {
		frame := rect(0, 0, if i % 2 == 0 { 400.0 } else { 410.0 }, 300)
		opacity := if i % 2 == 0 { 0.5 } else { 1.0 }
		motion.current = MotionSample{ phase: .present, values: MotionValues{ opacity: opacity } }
		projected := portals.resolve(source, offsets, frame, u64(i + 5))!
		focus.update_mounted(projected, offsets, frame, ContentTransform{})
		assert projected.children[1].id == 'dialog__backdrop'
		assert projected.children[1].frame == frame
		assert projected.children[1].opacity == 0.4 * opacity
		assert portals.layers[0].frame == rect((frame.width - 140) / 2, 110, 140, 80)
		assert (focus.node('dialog') or { panic('missing dialog') }).frame == portals.layers[0].frame
	}
	delta := gc_allocation_snapshot()!.delta_since(before)
	assert portals.layers[0].layout.stats().measure_visits == measure_before
	assert focus.nodes.data == registry
	assert delta.allocated_bytes == 0
	assert delta.collections == 0
}

fn test_geometry_only_clipped_dialog_releases_modal_gate_and_reuses_registry() ! {
	viewport := rect(0, 0, 400, 300)
	dialog := with_overlay(view('dialog', rect(0, 0, 140, 80), BoxStyle{}, [
		button('inside', 'Inside', rect(8, 8, 100, 24), BoxStyle{}, TextStyle{}),
	]), OverlayConfig{ kind: .dialog, open: true, anchor: 'anchor' })!
	pane := Element{
		kind:     .scroll
		id:       'pane'
		frame:    rect(20, 20, 200, 140)
		children: [
			button('anchor', 'Anchor', rect(10, 70, 80, 24), BoxStyle{}, TextStyle{}),
		]
	}
	mut layout := LayoutTree{}
	layout.replace(view('root', viewport, BoxStyle{}, [pane, dialog,
		button('outside', 'Outside', rect(250, 20, 100, 24), BoxStyle{}, TextStyle{})]))!
	source := layout.resolve(LayoutConstraints{}, overlay_scroll_measure, LayoutEnvironment{})!
	mut offsets := map[string]f64{}
	mut portals := OverlayTree{ measure: overlay_scroll_measure }
	mut focus := FocusManager{}
	focus.update_mounted(source, offsets, viewport, ContentTransform{})
	path := (focus.node('pane') or { panic('missing pane') }).path
	for i in 0 .. 4 {
		offsets[path] = if i % 2 == 0 { 0.0 } else { 120.0 }
		focus.update_mounted(portals.resolve(source, offsets, viewport, 0)!, offsets, viewport, ContentTransform{})
	}
	registry := focus.nodes.data
	before := gc_allocation_snapshot()!
	for i in 0 .. 1000 {
		offsets[path] = if i % 2 == 0 { 0.0 } else { 120.0 }
		focus.update_mounted(portals.resolve(source, offsets, viewport, 0)!, offsets, viewport, ContentTransform{})
		available := i % 2 == 0
		assert portals.layers[0].available == available
		assert portals.modal == if available { 'dialog' } else { '' }
		assert focus.can_focus('outside') == !available
		assert focus.can_focus('inside') == available
		assert (focus.node('dialog__backdrop') or { panic('missing backdrop') }).hidden == !available
	}
	delta := gc_allocation_snapshot()!.delta_since(before)
	assert focus.nodes.data == registry
	assert delta.allocated_bytes == 0
	assert delta.collections == 0
}

fn test_retained_focus_offsets_copy_values_and_remove_replaced_keys() {
	mut destination := map[string]f64{}
	mut keys := []string{}
	mut source := {
		'first':  1.0
		'second': 2.0
	}
	retain_focus_offsets(mut destination, mut keys, source)
	source['first'] = 3
	assert destination['first'] == 1
	retain_focus_offsets(mut destination, mut keys, source)
	assert destination == source
	source.delete('second')
	source['third'] = 4
	retain_focus_offsets(mut destination, mut keys, source)
	assert destination == source && 'second' !in destination
	source.clear()
	retain_focus_offsets(mut destination, mut keys, source)
	assert destination.len == 0 && keys.len == 0
}

fn test_geometry_cache_reflows_shrunk_surface_and_restores_authored_size() ! {
	body := stack(StackConfig{
		id:       'dialog'
		frame:    rect(0, 0, 360, 180)
		children: [
			StackChild{ element: view('fill', rect(0, 0, 20, 20), BoxStyle{}, []), align_x: .stretch, align_y: .stretch },
		]
	})!
	dialog := with_overlay(body, OverlayConfig{ kind: .dialog, open: true })!
	mut raw := LayoutTree{}
	raw.replace(view('root', rect(0, 0, 400, 300), BoxStyle{}, [dialog]))!
	source := raw.resolve(LayoutConstraints{}, overlay_scroll_measure, LayoutEnvironment{})!
	mut portals := OverlayTree{ measure: overlay_scroll_measure }
	offsets := map[string]f64{}
	mut focus := FocusManager{}
	mut generation := u64(0)
	for index, viewport in [rect(0, 0, 400, 300), rect(0, 0, 220, 160), rect(0, 0, 400, 300)] {
		focus.update_mounted(portals.resolve(source, offsets, viewport, 0)!, offsets, viewport, ContentTransform{})
		expected := if index == 1 { rect(8, 8, 204, 144) } else { rect(20, 60, 360, 180) }
		assert (focus.node('dialog') or { panic('missing dialog') }).frame == expected
		assert (focus.node('fill') or { panic('missing fill') }).frame == expected
		identity := portals.layers[0].layout.identity('fill') or { panic('missing fill identity') }
		if index == 0 {
			generation = identity.generation
		} else {
			assert identity.generation == generation
		}
	}
	assert portals.source_revision == 1
	assert body.frame == rect(0, 0, 360, 180)
}

fn test_compiled_overlay_without_geometry_effects_reuses_projection_after_mount() ! {
	mut owner := new_vml_document('compiled projection')!
	owner.publish = fn (_ string, _ Element) {}
	mut surface := owner.element(with_overlay(view('dialog', rect(0, 0, 140, 80), BoxStyle{}, []),
		OverlayConfig{ kind: .dialog, open: true })!)!
	mut root := owner.element(view('root', rect(0, 0, 400, 300), BoxStyle{}, []))!
	root.set_children([surface])!
	root.mount()!
	defer { owner.dispose() or { panic(err) } }
	mut raw := LayoutTree{}
	raw.replace(root.element())!
	source := raw.resolve(LayoutConstraints{}, overlay_scroll_measure, LayoutEnvironment{})!
	offsets := map[string]f64{}
	mut portals := OverlayTree{ measure: overlay_scroll_measure }
	for i in 0 .. 4 {
		_ = portals.resolve(source, offsets, rect(0, 0, if i % 2 == 0 { 400.0 } else { 410.0 }, 300), 0)!
	}
	before := gc_allocation_snapshot()!
	for i in 0 .. 1000 {
		viewport := rect(0, 0, if i % 2 == 0 { 400.0 } else { 410.0 }, 300)
		_ = portals.resolve(source, offsets, viewport, 0)!
		assert surface.frame()! == rect((viewport.width - 140) / 2, 110, 140, 80)
	}
	delta := gc_allocation_snapshot()!.delta_since(before)
	assert delta.allocated_bytes == 0
	assert delta.collections == 0
}
