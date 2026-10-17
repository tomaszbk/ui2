// vfmt off
@[has_globals]
module ui2

$if macos && !ui2_headless ? {
	import gg
	import math

	__global core20_events = []string{}
	__global core20_cancel_scroll bool
	fn core20_scroll_a(event ElementEvent) {
		mut w := event.window
		if event.kind != .scroll { return }
		core20_events << 'A:${event.value}'
		w.scroll_to_offset('other', 10_000)
		if core20_cancel_scroll {
		}
	}
	fn core20_scroll_b(event ElementEvent) {
		if event.kind == .scroll { core20_events << 'B:${event.value}' }
	}
	fn core20_pointer(_event ElementEvent) {}
	fn core20_measure(text string, _style TextStyle, width f64) !LayoutSize {
		natural := f64(text.runes().len * 8)
		available := if width > 0 { width } else { natural }
		return LayoutSize{width: math.min(natural, available), height: 20 * math.max(1, math.ceil(natural / math.max(1, available)))}
	}
	fn core20_rect(actual Rect, expected Rect) {
		assert math.abs(actual.x - expected.x) < 1e-6, '${actual} != ${expected}'
		assert math.abs(actual.y - expected.y) < 1e-6, '${actual} != ${expected}'
		assert math.abs(actual.width - expected.width) < 1e-6, '${actual} != ${expected}'
		assert math.abs(actual.height - expected.height) < 1e-6, '${actual} != ${expected}'
	}

	fn test_actual_retained_grid_patch_affine_mounted_focus_reveal_and_capture_before_paint() {
		mut w := &Window{ctx: &DrawContext{inner: &gg.Context{width: 1600, height: 500}, width: 1600, height: 500}, has_root: true}
		grid_el := grid(GridConfig{id: 'grid', frame: rect(400, 0, 64, 0), columns: 2,
			children: [label('caption', 'aa', Rect{}, TextStyle{}), label('cell', 'bb', Rect{}, TextStyle{})]})!
		composite_el := view('composite', rect(400, 0, 64, 60), BoxStyle{}, [grid_el.with_layout_frame(rect(0, 0, 64, 60))])
		target := Element{kind: .button, id: 'target', text: 'Target', frame: rect(5, 100, 20, 10), on_event: core20_pointer}
		w.declared_root = screen(0xffffff, [
			button('anchor', 'Anchor', rect(0, 0, 20, 20), BoxStyle{}, TextStyle{}),
			Element{kind: .scroll, id: 'outer', frame: rect(20, 30, 160, 100), children: [
				Element{kind: .scroll, key: 'anonymous', frame: rect(10, 150, 100, 60), children: [target]},
			 ]}, composite_el,
		])
		first := w.scheduler.begin_frame(0) or { panic('initial frame') }
		root := w.resolve_custom_layout(first, core20_measure, w.take_custom_layout_patches())!
		w.scheduler.finish_frame(first)
		w.update_custom_focus_tree(root)
		// Intrinsic Grid content inside a composite remains in its assigned slot.
		caption := w.navigation.node('caption') or { panic('caption') }
		assert caption.el.frame.width == 32
		w.refresh_element('caption', Element{...caption.el, text: 'año café largo'})
		patch := w.scheduler.begin_frame(1) or { panic('patch') }
		patched := w.resolve_custom_layout(patch, core20_measure, w.take_custom_layout_patches())!
		w.scheduler.finish_frame(patch)
		w.update_custom_focus_tree(patched)
		assert (w.navigation.node('caption') or { panic('caption') }).el.frame.width == 32
		assert (w.navigation.node('cell') or { panic('cell') }).el.frame.x == 32
		assert w.layout_tree.stats().builds == 1
		before := w.layout_tree.stats()
		identity := w.layout_tree.identity('outer') or { panic('identity') }
		presented := VisualGeometry{frame: rect(20, 30, 160, 100)}
		w.visual_geometries['outer'] = presented
		w.set_visual_transform('outer', VisualTransform{rotation: 45, scale_x: 2, translate_x: 1000})!
		assert w.layout_tree.stats() == before
		assert w.layout_tree.identity('outer') or { panic('identity') } == identity
		assert w.visual_geometry('outer')! == presented
		// Hand-derived: outer pivot (20,30), target local (35,280), width20 height10.
		// (2*15-250,2*15+250)/sqrt(2), and extent (40+10)/sqrt(2).
		r := math.sqrt(2)
		core20_rect((w.semantic_node('target') or { panic('target') }).frame,
			rect(1020 - 230/r, 30 + 280/r, 50/r, 50/r))
		assert w.navigation.order() == ['anchor', 'target']
		node := w.navigation.node('target') or { panic('target') }
		assert w.mounted_geometry('target')!.transform == node.transform
		assert node.scrolls.len == 2 && node.clip.bounds().width == 0 // fully clipped, still eligible
		reveals := w.navigation.reveals('target')
		assert reveals.len == 2 && reveals[0].id == '' && reveals[1].id == 'outer'
		core20_rect(reveals[0].rect, rect(5, 100, 20, 10))
		core20_rect(reveals[1].rect, rect(15, 200, 20, 10))
		// Capture queries also use current mounted affine geometry before a draw.
		w.hit_targets = []HitTarget{}
		current := w.current_pointer_target(HitTarget{id: 'target', kind: .button, on_event: core20_pointer}) or { panic('mounted capture') }
		assert current.content_transform == node.transform && current.local_frame == node.local_frame
		w.focus('anchor')
		assert w.focus_direction(.right) && w.focused_id() == 'target'
		assert math.abs(w.scroll_offset('outer') - 110) < 1e-6
		inner := w.navigation.path_node(node.scrolls[1]) or { panic('anonymous pane') }
		assert math.abs(w.scroll_state_offset(scroll_view_state_id(inner.el, inner.path)) - 50) < 1e-6
		assert w.focus_previous() && w.focused_id() == 'anchor'
		assert w.focus_next() && w.focused_id() == 'target'
		assert w.layout_tree.stats() == before
		paint := w.scheduler.begin_frame(2) or { panic('paint') }
		assert !paint.build && paint.reasons == RenderReason.paint
		_ = w.resolve_custom_layout(paint, core20_measure, w.take_custom_layout_patches())!
		w.scheduler.finish_frame(paint)
		assert w.layout_tree.stats().measure_visits == before.measure_visits
		assert w.layout_tree.stats().layout_visits == before.layout_visits
		assert (w.layout_tree.find_id('outer') or { panic('retained') }).declaration.rotation == 45
	}

	fn test_affine_scroll_reentry_uses_current_offscreen_handlers_and_stops_after_generation_change() {
		mut w := &Window{ctx: &DrawContext{}, has_root: true}
		root := screen(0xffffff, [
			Element{kind: .scroll, id: 'a', frame: rect(0, 0, 100, 100), rotation: 90, scale_x: 2, scale_y: 2, on_event: core20_scroll_a,
				children: [Element{kind: .label, frame: rect(0, 280, 30, 20)}]},
			Element{kind: .scroll, id: 'other', frame: rect(0, 1000, 100, 80), on_event: core20_scroll_b,
				children: [Element{kind: .label, frame: rect(0, 180, 30, 20)}]},
		])
		w.update_custom_focus_tree(root)
		a := named_scroll_state_id('a')
		b := named_scroll_state_id('other')
		w.scroll_areas[a] = rect(-200, 0, 200, 200)
		w.scroll_areas[b] = rect(0, 1000, 100, 80)
		core20_events.clear()
		core20_cancel_scroll = false
		w.apply_scroll_vector([a], -40, 0)
		assert w.scroll_offset('a') == 20 && w.scroll_offset('other') == 136
		assert core20_events == ['A:20.0', 'B:136.0']
		// The current callback reenters B, then switches away and back. Even
		// returning to the same window invalidates the outer captured generation.
		w.scroll_offsets[b] = 0
		core20_events.clear()
		core20_cancel_scroll = true
		w.apply_scroll_vector([a, b], -40, 100)
		assert w.scroll_offset('a') == 40 && w.scroll_offset('other') == 136
		assert core20_events == ['A:40.0', 'B:136.0']
	}
	fn test_mounted_non_screen_root_uses_current_window_clip_before_paint() {
		// Publish a logical viewport without consulting Sokol's process-wide
		// window size; this fixture has no physical host or GPU surface.
		mut w := &Window{ctx: &DrawContext{owns_surface: true, width: 50, height: 50, scale: 1}}
		w.update_custom_focus_tree(view('root-view', rect(0, 0, 100, 100), BoxStyle{}, []Element{}))
		geometry := w.mounted_geometry('root-view')!
		assert geometry.contains(25, 25)
		assert !geometry.contains(75, 25)
		core20_rect(geometry.clip.bounds(), rect(0, 0, 50, 50))
		// Window clipping leaves the resolved logical frame intact.
		assert geometry.frame == rect(0, 0, 100, 100)
	}

}
