// vtest build: macos && ui2_custom_rendering? && ui2_embedder? && !ui2_headless?
// vtest vflags: -d ui2_custom_rendering -d ui2_embedder
@[has_globals]
module ui2

$if macos && ui2_custom_rendering ? && ui2_embedder ? && !ui2_headless ? {
	import gg

	__global embedder_drag_events = []ElementEvent{}
	__global embedder_drag_keys = 0
	fn embedder_drag_record(event ElementEvent) { embedder_drag_events << event }
	fn embedder_drag_accept(_ DragOffer) DragOperation { return .move }
	fn embedder_drag_key(_ KeyEvent) { embedder_drag_keys++ }
	fn reset_embedder_drag() {
		g_gg_app = &GgApp{}
		g_touch = TouchState{}
		g_drag_registry = DragRegistry{}
		g_build_screen = unsafe { nil }
		g_focused_field = ''
		g_tooltip = TooltipState{}
		reset_scroll_frame()
		close_dropdown()
		embedder_drag_events = []ElementEvent{}
		embedder_drag_keys = 0
		g_key_event_handler = embedder_drag_key
		source := HitTarget{id: 'embedder-source', identity: 'source', x: 10, y: 20, w: 40, h: 40,
			on_event: embedder_drag_record, button_behavior: true, drag_generation: 1, drag_source: DragSource{}}
		target := HitTarget{id: 'embedder-target', identity: 'target', x: 100, y: 20, w: 60, h: 50,
			on_event: embedder_drag_record, drag_generation: 2, drop_target: DropTarget{accept: embedder_drag_accept}}
		g_hit_targets = [source, target]
		g_drag_registry = DragRegistry{owners: {'id:embedder-source': source, 'id:embedder-target': target}, generation: 2}
		g_active_custom_window_state = unsafe { nil }
	}
	fn test_escape_injected_into_actual_embedder_dispatch_cancels_active_and_pending_once() {
		for active in [false, true] {
			for skip in [false, true] {
				reset_embedder_drag()
				handle_touch_down(20, 30)
				if active { handle_touch_move(120, 30) }
				mut state := g_active_custom_window_state
				g_gg_app.window_state = state
				consumed := embedder_event(g_gg_app, &C.ui2_embedder_event{kind: 7,
					key_code: int(gg.KeyCode.escape), skip_dispatch: skip, text_input: skip})
				assert !g_touch.down && !g_touch.pointer_captured && !drag_active()
				assert consumed
				assert embedder_drag_keys == 0
				handle_touch_up(if active { 120.0 } else { 20.0 }, 30)
				kinds := embedder_drag_events.map(it.kind)
				assert kinds == if active { [.drag_start, .drag_enter, .drag_over, .drag_leave, .drag_cancel] } else { []ElementEventKind{} }
				if active { assert (embedder_drag_events.last().drag or { panic('missing') }).reason == .escape }
				println('EMBEDDER injected Escape active=${active} skip=${skip} PASS (physical OS input NOT_VERIFIED)')
			}
		}
	}
	fn test_escape_ordinary_on_event_dispatch_cancels_active_and_pending() {
		for active in [false, true] {
			reset_embedder_drag()
			handle_touch_down(20, 30)
			if active { handle_touch_move(120, 30) }
			on_event(&gg.Event{typ: .key_down, key_code: .escape}, g_gg_app)
			assert !g_touch.down && !g_touch.pointer_captured && !drag_active()
			handle_touch_up(20, 30)
			assert embedder_drag_events.filter(it.kind == .tap || it.kind == .drop).len == 0
			assert embedder_drag_events.filter(it.kind == .drag_cancel).len == if active { 1 } else { 0 }
			assert embedder_drag_keys == 0
		}
	}
	fn test_embedder_escape_preserves_unowned_keys_and_other_window_capture() {
		reset_embedder_drag()
		handle_touch_down(20, 30)
		handle_touch_move(120, 30)
		first_app := g_gg_app
		first := g_active_custom_window_state
		g_gg_app.window_state = first
		mut second := new_custom_window_state()
		second.key_event_handler = embedder_drag_key
		other_app := &GgApp{window_state: second}
		assert !embedder_event(other_app, &C.ui2_embedder_event{kind: 7, key_code: int(gg.KeyCode.escape)})
		assert g_gg_app == first_app && drag_active() && g_touch.pointer_captured
		assert embedder_drag_keys == 1
		assert embedder_event(first_app, &C.ui2_embedder_event{kind: 7, key_code: int(gg.KeyCode.escape)})
		assert !drag_active() && !g_touch.down
		assert embedder_drag_keys == 1
		assert !embedder_event(first_app, &C.ui2_embedder_event{kind: 7, key_code: int(gg.KeyCode.escape)})
		assert embedder_drag_keys == 2
	}
}
