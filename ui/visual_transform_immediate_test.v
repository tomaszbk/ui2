// vtest vflags: -d ui2_custom_rendering
@[has_globals]
module ui2

$if ( linux || ( ( macos || windows ) && ui2_custom_rendering ?) ) && !ui2_headless ? {
	import gg
	import math
	__global transform_callback_events = []ElementEvent{}
	fn capture_transform_event(event ElementEvent) { transform_callback_events << event }
	fn transform_explicit_build_event(event ElementEvent) {
		transform_callback_events << event
		set_visual_transform('tile', VisualTransform{rotation: 30}) or { panic(err) }
		refresh()
	}
	fn transform_presentation_event(event ElementEvent) {
		transform_callback_events << event
		set_visual_transform('tile', VisualTransform{ rotation: 30 }) or { panic(err) }
	}
	fn test_actual_pointer_dispatch_does_not_rebuild_transform_callbacks() {
		previous := g_gg_app
		previous_touch := g_touch
		previous_tooltip := g_tooltip
		previous_focus := g_focus_navigation
		previous_events := transform_callback_events.clone()
		g_focus_navigation = &FocusManager{}
		transform_callback_events.clear()
		tile := Element{kind: .view, id: 'tile', frame: rect(0, 0, 100, 100),
			clickable: true, draggable: true, on_event: transform_presentation_event}
		g_gg_app = &GgApp{ ctx: &DrawContext{width: 320, height: 240}, has_root: true, declared_root: screen(0xffffff, [tile]) }
		defer {
			g_gg_app = previous
			g_touch = previous_touch
			g_tooltip = previous_tooltip
			g_focus_navigation = previous_focus
			transform_callback_events = previous_events.clone()
			g_hit_targets = []HitTarget{}
		}
		initial := g_gg_app.scheduler.begin_frame(0) or { panic('initial frame') }
		g_gg_app.scheduler.finish_frame(initial)
		// Presented targets route through the current mounted declaration.
		g_hit_targets = [HitTarget{ id: 'tile', kind: .view, on_event: tile.on_event, clickable: true, draggable: true, w: 100, h: 100 }]
		on_event(&gg.Event{ typ: .mouse_down, mouse_x: 20, mouse_y: 30 }, g_gg_app)
		on_event(&gg.Event{ typ: .mouse_move, mouse_x: 25, mouse_y: 32 }, g_gg_app)
		on_event(&gg.Event{ typ: .mouse_up, mouse_x: 25, mouse_y: 32 }, g_gg_app)
		assert transform_callback_events.map(it.kind) == [ElementEventKind.pointer_down, .pointer_drag, .pointer_up]
		work := g_gg_app.scheduler.begin_frame(1) or { panic('missing paint') }
		assert !work.build && work.draw && RenderReason.build !in work.reasons
		g_gg_app.scheduler.finish_frame(work)
		assert !g_gg_app.scheduler.stats().pending
		refresh_element('tile', Element{...tile, on_event: transform_explicit_build_event})
		on_event(&gg.Event{typ: .mouse_down, mouse_x: 20, mouse_y: 30}, g_gg_app)
		assert transform_callback_events.len == 4 && transform_callback_events.last().kind == .pointer_down
		explicit := g_gg_app.scheduler.begin_frame(2) or { panic('explicit build') }
		assert explicit.build && RenderReason.build in explicit.reasons
		g_gg_app.scheduler.finish_frame(explicit)
	}
	fn test_rotated_targets_tooltips_and_scroll_use_exact_same_clip() {
		previous := g_gg_app
		previous_tooltip := g_tooltip_targets.clone()
		g_gg_app = &GgApp{ ctx: &DrawContext{} }
		defer {
			g_gg_app = previous
			g_hit_targets = []HitTarget{}
			g_tooltip_targets = previous_tooltip.clone()
			reset_scroll_frame()
		}
		frame := rect(0, 0, 100, 100)
		t := VisualTransform{ rotation: 45, origin_x: 50, origin_y: 50 }.matrix(frame)!
		g_gg_app.ctx.content_transform = t
		add_hit_target(HitTarget{ id: 'diamond', x: 0, y: 0, w: 100, h: 100 }, frame)
		add_tooltip_target('diamond', 'tip', frame, frame)
		id := named_scroll_state_id('diamond')
		register_scroll_view(id, frame, frame, 300, true, true, false, HitTarget{})
		assert hit_test(-10, -10).id == ''
		assert tooltip_target_at(g_tooltip_targets, -10, -10).key == ''
		assert scroll_hit_test(-10, -10) == ''
		assert hit_test(50, 50).id == 'diamond'
		assert tooltip_target_at(g_tooltip_targets, 50, 50).key == 'diamond'
		assert scroll_hit_test(50, 50) == id
	}
	fn test_wheel_vectors_scroll_chain_and_scrollbar_capture_follow_local_axes() {
		previous := g_gg_app
		g_gg_app = &GgApp{ ctx: &DrawContext{ content_transform: ContentTransform{ xx: 0, xy: -2, yx: 2, yy: 0, x: 300, y: 10 } } }
		defer {
			g_gg_app = previous
			reset_scroll_frame()
			g_scroll_offsets.clear()
			g_touch = TouchState{}
		}
		id := named_scroll_state_id('rotated')
		register_scroll_view(id, rect(0, 0, 100, 100), rect(0, 0, 100, 100), 300, true, true, false, HitTarget{})
		// Window left 40 = local down 20. Window down contributes no local y.
		apply_scroll_vector([id], -40, 0)
		assert scroll_state_offset(id) == 20
		apply_scroll_vector([id], 0, 40)
		assert scroll_state_offset(id) == 20
		apply_scroll_vector([id], -1000, 0)
		assert scroll_state_offset(id) == 200
		set_scroll_offset(id, 0, 200)
		register_scroll_view(id, rect(0, 0, 100, 100), rect(0, 0, 100, 100), 300, true, true, false, HitTarget{})
		g_touch = TouchState{ scroll_id: id }
		// Track local x=93, thumb y=4..34.67. Grab local y=10.
		assert begin_scrollbar_drag(280, 196)
		drag_scrollbar_at(240, 196) // local y=30, +20 thumb travel
		assert math.abs(scroll_state_offset(id) - 65.21739130434783) < 1e-7
	}
	fn test_capture_uses_current_matrix_and_keeps_identity() {
		previous := g_gg_app
		g_gg_app = &GgApp{ ctx: &DrawContext{} }
		defer {
			g_gg_app = previous
			g_hit_targets = []HitTarget{}
			transform_callback_events = []ElementEvent{}
		}
		captured := HitTarget{ id: 'owner', on_event: capture_transform_event, draggable: true, w: 100, h: 100 }
		g_hit_targets = [HitTarget{ ...captured, content_transform: ContentTransform{ xx: 2, yy: 2, x: 10, y: 20 } }]
		fire_pointer_event(.pointer_drag, captured, 70, 80)
		assert transform_callback_events.last() == ElementEvent{ kind: .pointer_drag, id: 'owner', x: 30, y: 30 }
	}
	fn test_capture_retains_the_current_matrix_when_owner_leaves_its_clip() {
		previous := g_gg_app
		g_gg_app = &GgApp{ ctx: &DrawContext{ content_transform: ContentTransform{ x: 1000 }, clip_base: transformed_clip(rect(0, 0, 100, 100), ContentTransform{}) } }
		defer {
			g_gg_app = previous
			g_hit_targets = []HitTarget{}
			transform_callback_events = []ElementEvent{}
		}
		captured := HitTarget{ id: 'owner', on_event: capture_transform_event, draggable: true, w: 100, h: 100 }
		add_hit_target(captured, rect(0, 0, 100, 100))
		assert hit_test(1020, 30).id == ''
		assert current_pointer_target(captured) != none
		fire_pointer_event(.pointer_drag, captured, 1020, 30)
		assert transform_callback_events.last() == ElementEvent{ kind: .pointer_drag, id: 'owner', x: 20, y: 30 }
	}
	fn test_hover_and_hit_include_the_same_rotated_boundary() {
		previous := g_gg_app
		previous_tooltip := g_tooltip
		g_gg_app = &GgApp{ ctx: &DrawContext{} }
		defer {
			g_gg_app = previous
			g_tooltip = previous_tooltip
			g_hit_targets = []HitTarget{}
		}
		frame := rect(0, 0, 100, 100)
		t := VisualTransform{ rotation: 45, scale_x: 1.1, scale_y: 0.8, origin_x: 50, origin_y: 50 }.matrix(frame)!
		x := 50 - 95 / math.sqrt(2)
		y := 50 - 15 / math.sqrt(2)
		g_gg_app.ctx.content_transform = t
		g_tooltip = TooltipState{ pointer_in: true, pointer_x: x, pointer_y: y }
		el := with_interaction_style(button('edge', 'Edge', frame, BoxStyle{ bg: 0xff0000 }, TextStyle{}), InteractionStyle{ hover: BoxStylePatch{ bg: u32(0x00ff00) } })
		add_hit_target(HitTarget{ id: 'edge', w: 100, h: 100 }, frame)
		assert hit_test(x, y).id == 'edge'
		assert resolve_custom_visual_style(el, frame, frame, t).box.bg == 0x00ff00
	}
	fn test_presentation_setter_preserves_layout_editor_state_and_only_requests_paint() {
		previous := g_gg_app
		g_gg_app = &GgApp{ ctx: &DrawContext{}, has_root: true, declared_root: screen(0xffffff, [view('tile', rect(10.125, 20.375, 100.25, 50.75), BoxStyle{}, []Element{})]) }
		defer { g_gg_app = previous }
		initial := g_gg_app.scheduler.begin_frame(0) or { panic('initial surface') }
		g_gg_app.scheduler.finish_frame(initial)
		frame := g_gg_app.declared_root.children[0].frame
		set_visual_transform('tile', VisualTransform{ rotation: 30, translate_x: 5 })!
		assert g_gg_app.declared_root.children[0].frame == frame
		work := g_gg_app.scheduler.begin_frame(1) or { panic('paint was not requested') }
		assert !work.build && work.draw && work.reasons == [RenderReason.paint]
		g_gg_app.scheduler.finish_frame(work)
		assert !g_gg_app.scheduler.stats().pending
		assert g_gg_app.scheduler.begin_frame(2) == none
		if _ := set_visual_transform('tile', VisualTransform{ scale_x: 0 }) {
			assert false
		}
		assert g_gg_app.declared_root.children[0].rotation == 30
	}
}
