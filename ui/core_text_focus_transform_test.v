// vtest vflags: -d ui2_custom_rendering
// vfmt off
@[has_globals]
module ui2

$if macos && ui2_custom_rendering ? && !ui2_headless ? {
	import gg
	import math

	__global core20_events = []string{}
	__global core20_cancel_scroll bool
	fn core20_scroll_a(event ElementEvent) {
		if event.kind != .scroll { return }
		core20_events << 'A:${event.value}'
		scroll_to_offset('other', 10_000)
		if core20_cancel_scroll {
			previous := activate_custom_window_state(new_custom_window_state())
			activate_custom_window_state(previous)
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
		previous_app := g_gg_app
		previous := activate_custom_window_state(new_custom_window_state())
		defer { activate_custom_window_state(previous); g_gg_app = previous_app }
		g_gg_app = &GgApp{ctx: &DrawContext{inner: &gg.Context{width: 1600, height: 500}, width: 1600, height: 500}, has_root: true}
		grid_el := grid(GridConfig{id: 'grid', frame: rect(400, 0, 64, 0), columns: 2,
			children: [label('caption', 'aa', Rect{}, TextStyle{}), label('cell', 'bb', Rect{}, TextStyle{})]})!
		composite := modal_view(id: 'composite', frame: rect(400, 0, 64, 60), open: true, size_hint_x: 1, content: grid_el)!
		composite_el := Element{...composite, children: composite.children.map(if it.kind == .button { Element{...it, focus_policy: .unfocusable} } else { it })}
		target := Element{kind: .button, id: 'target', text: 'Target', frame: rect(5, 100, 20, 10), on_event: core20_pointer}
		g_gg_app.declared_root = screen(0xffffff, [
			button('anchor', 'Anchor', rect(0, 0, 20, 20), BoxStyle{}, TextStyle{}),
			Element{kind: .scroll, id: 'outer', frame: rect(20, 30, 160, 100), children: [
				Element{kind: .scroll, key: 'anonymous', frame: rect(10, 150, 100, 60), children: [target]},
			 ]}, composite_el,
		])
		mut app := g_gg_app
		first := app.scheduler.begin_frame(0) or { panic('initial frame') }
		root := resolve_custom_layout(mut app, first, core20_measure, take_custom_layout_patches(mut app))!
		app.scheduler.finish_frame(first)
		update_custom_focus_tree(root)
		// Intrinsic Grid content inside a composite remains in its assigned slot.
		caption := g_focus_navigation.node('caption') or { panic('caption') }
		assert caption.el.frame.width == 32
		refresh_element('caption', Element{...caption.el, text: 'año café largo'})
		patch := app.scheduler.begin_frame(1) or { panic('patch') }
		patched := resolve_custom_layout(mut app, patch, core20_measure, take_custom_layout_patches(mut app))!
		app.scheduler.finish_frame(patch)
		update_custom_focus_tree(patched)
		assert (g_focus_navigation.node('caption') or { panic('caption') }).el.frame.width == 32
		assert (g_focus_navigation.node('cell') or { panic('cell') }).el.frame.x == 32
		assert app.layout_tree.stats().builds == 1
		before := app.layout_tree.stats()
		identity := app.layout_tree.identity('outer') or { panic('identity') }
		presented := VisualGeometry{frame: rect(20, 30, 160, 100)}
		app.visual_geometries['outer'] = presented
		set_visual_transform('outer', VisualTransform{rotation: 45, scale_x: 2, translate_x: 1000})!
		assert app.layout_tree.stats() == before
		assert app.layout_tree.identity('outer') or { panic('identity') } == identity
		assert visual_geometry('outer')! == presented
		// Hand-derived: outer pivot (20,30), target local (35,280), width20 height10.
		// (2*15-250,2*15+250)/sqrt(2), and extent (40+10)/sqrt(2).
		r := math.sqrt(2)
		core20_rect((semantic_node('target') or { panic('target') }).frame,
			rect(1020 - 230/r, 30 + 280/r, 50/r, 50/r))
		assert g_focus_navigation.order() == ['anchor', 'target']
		node := g_focus_navigation.node('target') or { panic('target') }
		assert mounted_geometry('target')!.transform == node.transform
		assert node.scrolls.len == 2 && node.clip.bounds().width == 0 // fully clipped, still eligible
		reveals := g_focus_navigation.reveals('target')
		assert reveals.len == 2 && reveals[0].id == '' && reveals[1].id == 'outer'
		core20_rect(reveals[0].rect, rect(5, 100, 20, 10))
		core20_rect(reveals[1].rect, rect(15, 200, 20, 10))
		// Capture queries also use current mounted affine geometry before a draw.
		g_hit_targets = []HitTarget{}
		current := current_pointer_target(HitTarget{id: 'target', kind: .button, on_event: core20_pointer}) or { panic('mounted capture') }
		assert current.content_transform == node.transform && current.local_frame == node.local_frame
		focus('anchor')
		assert focus_direction(.right) && focused_id() == 'target'
		assert math.abs(scroll_offset('outer') - 110) < 1e-6
		inner := g_focus_navigation.path_node(node.scrolls[1]) or { panic('anonymous pane') }
		assert math.abs(scroll_state_offset(scroll_view_state_id(inner.el, inner.path)) - 50) < 1e-6
		assert focus_previous() && focused_id() == 'anchor'
		assert focus_next() && focused_id() == 'target'
		assert app.layout_tree.stats() == before
		paint := app.scheduler.begin_frame(2) or { panic('paint') }
		assert !paint.build && paint.reasons == [.paint]
		_ = resolve_custom_layout(mut app, paint, core20_measure, take_custom_layout_patches(mut app))!
		app.scheduler.finish_frame(paint)
		assert app.layout_tree.stats().measure_visits == before.measure_visits
		assert app.layout_tree.stats().layout_visits == before.layout_visits
		assert (app.layout_tree.find_id('outer') or { panic('retained') }).declaration.rotation == 45
	}

	fn test_affine_scroll_reentry_uses_current_offscreen_handlers_and_stops_after_generation_change() {
		previous_app := g_gg_app
		previous := activate_custom_window_state(new_custom_window_state())
		defer { activate_custom_window_state(previous); g_gg_app = previous_app }
		g_gg_app = &GgApp{ctx: &DrawContext{}, has_root: true}
		root := screen(0xffffff, [
			Element{kind: .scroll, id: 'a', frame: rect(0, 0, 100, 100), rotation: 90, scale_x: 2, scale_y: 2, on_event: core20_scroll_a,
				children: [Element{kind: .label, frame: rect(0, 280, 30, 20)}]},
			Element{kind: .scroll, id: 'other', frame: rect(0, 1000, 100, 80), on_event: core20_scroll_b,
				children: [Element{kind: .label, frame: rect(0, 180, 30, 20)}]},
		])
		update_custom_focus_tree(root)
		a := named_scroll_state_id('a')
		b := named_scroll_state_id('other')
		g_scroll_areas[a] = rect(-200, 0, 200, 200)
		g_scroll_areas[b] = rect(0, 1000, 100, 80)
		core20_events.clear()
		core20_cancel_scroll = false
		apply_scroll_vector([a], -40, 0)
		assert scroll_offset('a') == 20 && scroll_offset('other') == 136
		assert core20_events == ['A:20.0', 'B:136.0']
		// The current callback reenters B, then switches away and back. Even
		// returning to the same window invalidates the outer captured generation.
		g_scroll_offsets[b] = 0
		core20_events.clear()
		core20_cancel_scroll = true
		apply_scroll_vector([a, b], -40, 100)
		assert scroll_offset('a') == 40 && scroll_offset('other') == 136
		assert core20_events == ['A:40.0', 'B:136.0']
	}
	fn test_mounted_non_screen_root_uses_current_window_clip_before_paint() {
		previous_app := g_gg_app
		previous := activate_custom_window_state(new_custom_window_state())
		mut menus := menu_state()
		previous_menus := menus.menus
		menus.menus = []Menu{}
		defer { activate_custom_window_state(previous); g_gg_app = previous_app; menus.menus = previous_menus }
		// Publish a logical viewport without consulting Sokol's process-wide
		// window size; this fixture has no physical host or GPU surface.
		g_gg_app = &GgApp{ctx: &DrawContext{owns_surface: true, width: 50, height: 50, scale: 1}}
		update_custom_focus_tree(view('root-view', rect(0, 0, 100, 100), BoxStyle{}, []Element{}))
		geometry := mounted_geometry('root-view')!
		assert geometry.contains(25, 25)
		assert !geometry.contains(75, 25)
		core20_rect(geometry.clip.bounds(), rect(0, 0, 50, 50))
		// Window clipping leaves the resolved logical frame intact.
		assert geometry.frame == rect(0, 0, 100, 100)
	}

}
