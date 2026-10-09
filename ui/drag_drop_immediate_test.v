// vtest vflags: -d ui2_custom_rendering
@[has_globals]
module ui2

$if (android || linux || ((macos || windows) && ui2_custom_rendering ?)) && !ui2_headless ? {
	import gg

	struct Parcel {
		code int
	}
	fn (p Parcel) drag_type() string { return 'parcel' }

	__global drag_records = []ElementEvent{}
	__global drag_cancel_on_enter = false

	fn record_drag(event ElementEvent) {
		drag_records << event
		if event.kind == .drag_enter && drag_cancel_on_enter { cancel_drag() }
	}
	fn accept_parcel(offer DragOffer) DragOperation {
		if offer.payload is Parcel {
			if offer.payload.code == 42 { return .move }
		}
		return .none
	}
	fn reject_parcel(_ DragOffer) DragOperation { return .none }
	fn unoffered_operation(_ DragOffer) DragOperation { return .link }

	fn drag_fixture_target(id string, x f64, accept DragAccept) HitTarget {
		return HitTarget{id: id, identity: id, w: 60, h: 50, x: x, y: 20,
			on_event: record_drag, drag_generation: if id == 'target' { u64(2) } else { u64(3) },
			drop_target: DropTarget{accept: accept}}
	}
	fn reset_drag_fixture() {
		g_gg_app = &GgApp{}
		g_touch = TouchState{}
		g_tooltip = TooltipState{}
		reset_scroll_frame()
		close_dropdown()
		drag_records = []ElementEvent{}
		drag_cancel_on_enter = false
		source := HitTarget{id: 'source', identity: 'source', w: 40, h: 40, x: 10, y: 20,
			on_event: record_drag, button_behavior: true, drag_generation: 1,
			drag_source: DragSource{payload: Parcel{42}, allowed: [.copy, .move]}}
		target := drag_fixture_target('target', 100, accept_parcel)
		rejected := drag_fixture_target('rejected', 200, reject_parcel)
		g_hit_targets = [source, target, rejected]
		g_drag_registry = DragRegistry{owners: {'id:source': source, 'id:target': target, 'id:rejected': rejected}, generation: 3}
	}
	fn drag_kinds() []ElementEventKind {
		return drag_records.map(it.kind)
	}

	fn test_drag_capture_outside_source_and_exactly_one_drop_no_residual_tap() {
		reset_drag_fixture()
		handle_touch_down(20, 30)
		handle_touch_move(80, 30)
		assert drag_active() && g_touch.pointer_captured
		handle_touch_move(120, 30)
		handle_touch_up(120, 30)
		handle_touch_up(120, 30)
		handle_touch_move(20, 30)
		assert drag_kinds() == [.drag_start, .drag_enter, .drag_over, .drag_over, .drop, .drag_leave, .drag_end]
		assert !g_touch.down && !g_touch.pointer_captured && !drag_active()
		event := drag_records[4].drag or { panic('missing drag data') }
		assert event.operation == .move && event.reason == .none
		assert event.offer.source_id == 'source' && event.offer.target_id == 'target'
		assert event.offer.payload is Parcel
		if event.offer.payload is Parcel { assert event.offer.payload.code == 42 }
	}

	fn test_threshold_short_press_and_coalesced_release() {
		reset_drag_fixture()
		handle_touch_down(20, 30)
		handle_touch_move(26, 30) // boundary does not start a drag
		assert !drag_active()
		handle_touch_up(26, 30)
		assert drag_kinds() == [.tap]
		reset_drag_fixture()
		g_hit_targets[0] = HitTarget{...g_hit_targets[0], drag_source: DragSource{threshold: 20}}
		g_drag_registry.owners['id:source'] = g_hit_targets[0]
		handle_touch_down(20, 30)
		handle_touch_move(35, 30) // below source threshold, beyond raw tap threshold
		handle_touch_up(35, 30)
		assert drag_kinds() == [.tap]
		reset_drag_fixture()
		handle_touch_down(20, 30)
		handle_touch_up(120, 30) // no intermediate move from host
		assert drag_kinds() == [.drag_start, .drag_enter, .drag_over, .drop, .drag_leave, .drag_end]
	}

	fn test_invalid_target_enter_leave_and_operation_rejection_are_deterministic() {
		reset_drag_fixture()
		handle_touch_down(20, 30)
		handle_touch_move(120, 30)
		handle_touch_move(220, 30)
		handle_touch_up(220, 30)
		assert drag_kinds() == [.drag_start, .drag_enter, .drag_over, .drag_leave, .drag_enter, .drag_over, .drag_over, .drag_leave, .drag_cancel]
		assert (drag_records.last().drag or { panic('missing') }).reason == .invalid_target
		for event in drag_records {
			if event.id == 'rejected' { assert (event.drag or { panic('missing') }).operation == .none }
		}
		reset_drag_fixture()
		g_hit_targets[1] = drag_fixture_target('target', 100, unoffered_operation)
		g_drag_registry.owners['id:target'] = g_hit_targets[1]
		handle_touch_down(20, 30)
		handle_touch_up(120, 30)
		assert ElementEventKind.drop !in drag_kinds()
		assert drag_records.last().kind == .drag_cancel
	}

	fn test_captured_operations_do_not_expand_when_application_changes_its_array() {
		reset_drag_fixture()
		mut offered := [DragOperation.move]
		g_hit_targets[0] = HitTarget{...g_hit_targets[0],
			drag_source: DragSource{payload: Parcel{42}, allowed: offered}}
		g_drag_registry.owners['id:source'] = g_hit_targets[0]
		g_hit_targets[1] = drag_fixture_target('target', 100, unoffered_operation)
		g_drag_registry.owners['id:target'] = g_hit_targets[1]
		handle_touch_down(20, 30)
		offered[0] = .link
		g_drag_registry.owners['id:source'] = HitTarget{...g_hit_targets[0],
			drag_source: DragSource{payload: Parcel{42}, allowed: [.link]}}
		handle_touch_up(120, 30)
		assert ElementEventKind.drop !in drag_kinds(), 'link was not offered at pointer-down'
		assert (drag_records[0].drag or { panic('missing') }).offer.allowed == [DragOperation.move]
		assert drag_records.last().kind == .drag_cancel
	}

	fn test_escape_deactivation_cancel_and_reentrant_cancel_release_capture() {
		for reason in [DragCancelReason.escape, .focus_lost, .cancelled] {
			reset_drag_fixture()
			handle_touch_down(20, 30)
			handle_touch_move(120, 30)
			match reason {
				.escape { on_event(&gg.Event{typ: .key_down, key_code: .escape}, g_gg_app) }
				.focus_lost { on_event(&gg.Event{typ: .unfocused}, g_gg_app) }
				else { cancel_drag() }
			}
			handle_touch_up(120, 30)
			cancel_drag()
			assert drag_kinds() == [.drag_start, .drag_enter, .drag_over, .drag_leave, .drag_cancel]
			assert (drag_records.last().drag or { panic('missing') }).reason == reason
			assert !g_touch.down && !drag_active()
		}
		reset_drag_fixture()
		drag_cancel_on_enter = true
		handle_touch_down(20, 30)
		handle_touch_move(120, 30)
		handle_touch_up(120, 30)
		assert drag_kinds() == [.drag_start, .drag_enter, .drag_leave, .drag_cancel]
	}

	fn test_current_target_geometry_and_generation_control_drop_not_captured_bounds() {
		reset_drag_fixture()
		handle_touch_down(20, 30)
		handle_touch_move(120, 30)
		g_hit_targets[1] = HitTarget{...g_hit_targets[1], x: 300}
		sync_drag_session()
		assert drag_records.last().kind == .drag_leave
		handle_touch_up(120, 30)
		assert drag_records.last().kind == .drag_cancel
		assert ElementEventKind.drop !in drag_kinds()

		reset_drag_fixture()
		handle_touch_down(20, 30)
		handle_touch_move(120, 30)
		g_drag_registry.owners.delete('id:target')
		sync_drag_session()
		assert drag_records.last().kind == .drag_leave
		handle_touch_up(120, 30)
		assert ElementEventKind.drop !in drag_kinds()

	}

	fn test_source_unmount_generation_and_clipped_source_have_distinct_lifetimes() {
		reset_drag_fixture()
		handle_touch_down(20, 30)
		handle_touch_move(80, 30)
		g_hit_targets.delete(0) // source still mounted but culled by Scroll
		sync_drag_session()
		assert drag_active()
		handle_touch_up(120, 30)
		assert ElementEventKind.drop in drag_kinds()

		for replacement in [false, true] {
			reset_drag_fixture()
			handle_touch_down(20, 30)
			handle_touch_move(120, 30)
			if replacement {
				g_drag_registry.owners['id:source'] = HitTarget{...g_hit_targets[0], drag_generation: 99}
			} else { g_drag_registry.owners.delete('id:source') }
			sync_drag_session()
			handle_touch_up(120, 30)
			assert drag_records.last().kind == .drag_cancel
			assert (drag_records.last().drag or { panic('missing') }).reason == .source_removed
			assert ElementEventKind.drop !in drag_kinds()
		}
	}

	fn test_scaled_current_coordinates_preview_and_shared_clipping() {
		reset_drag_fixture()
		// Hand-derived composition mapping: window=(10+2*x,20+2*y).
		transform := ContentTransform{xx: 2, yy: 2, x: 10, y: 20}
		g_hit_targets[0] = HitTarget{...g_hit_targets[0], content_transform: transform}
		g_hit_targets[1] = HitTarget{...g_hit_targets[1], content_transform: ContentTransform{xx: 0.5, yy: 0.5, x: 100, y: 20}}
		handle_touch_down(20, 30)
		handle_touch_up(120, 30)
		drop := drag_records.filter(it.kind == .drop)[0]
		data := drop.drag or { panic('missing') }
		assert drop.x == 40 && drop.y == 20
		assert data.offer.source_x == 55 && data.offer.source_y == 5
		assert data.offer.window_x == 120 && data.offer.window_y == 30
		for dpi in [1.0, 1.25, 1.5, 2.0] {
			preview := drag_preview_transform(transform, 200, 80)
			assert presentation_rect(preview.project(rect(12, 12, 40, 20)), dpi) == rect(224, 104, 80, 40)
		}

		reset_drag_fixture()
		g_hit_targets = []HitTarget{}
		// Registration uses the existing shared clip/project helper. Only the
		// left half of target is visible; drops outside it cannot hit.
		add_hit_target(drag_fixture_target('target', 100, accept_parcel), rect(100, 20, 20, 50))
		assert drag_destination(110, 30).id == 'target'
		assert drag_destination(130, 30).id == ''
	}

	fn test_drag_wins_content_scroll_but_scrollbar_and_raw_draggable_keep_their_capture() {
		reset_drag_fixture()
		frame := rect(0, 0, 300, 100)
		register_scroll_view(named_scroll_state_id('pane'), frame, frame, 600, true, true, true, HitTarget{})
		handle_touch_down(20, 30)
		handle_touch_move(120, 60)
		assert scroll_offset('pane') == 0
		handle_touch_up(120, 60)
		assert ElementEventKind.drop in drag_kinds()
		reset_drag_fixture()
		register_scroll_view(named_scroll_state_id('pane'), frame, frame, 600, true, true, true, HitTarget{})
		bar := scrollbar_geometry(frame, 600, 0, true)
		handle_touch_down(bar.thumb.x + 1, bar.thumb.y + 1)
		assert g_touch.scrollbar_drag && !g_touch.drag.pending
		handle_touch_move(bar.thumb.x + 1, 60)
		handle_touch_up(bar.thumb.x + 1, 60)
		assert drag_records.len == 0
		assert scroll_offset('pane') > 0
	}

	fn test_drag_preserves_focus_utf8_selection_scroll_composition_and_returns_idle() {
		reset_drag_fixture()
		g_focused_field = 'editor'
		replace_text_editor('editor', TextEditor{text: 'niño café'.clone(), selection: TextSelection{anchor: 2, caret: 5}})
		replace_text_value('editor', 'niño café')
		g_gg_app.composition = TextComposition{field_id: 'editor', text: 'á', start: 2, end: 5, mark_length: 1, selection: TextSelection{anchor: 1, caret: 1}}
		composition := g_gg_app.composition
		g_scroll_offsets[named_scroll_state_id('pane')] = 42
		handle_touch_down(20, 30)
		handle_touch_up(120, 30)
		assert g_focused_field == 'editor'
		assert text('editor') == 'niño café'
		assert g_text_editors['editor'].selection == TextSelection{anchor: 2, caret: 5}
		assert g_gg_app.composition == composition
		assert scroll_offset('pane') == 42
		assert custom_visual_deadline() == -1
		work := g_gg_app.scheduler.begin_frame(0) or { panic('missing final paint') }
		g_gg_app.scheduler.set_deadline(custom_visual_deadline())
		g_gg_app.scheduler.finish_frame(work)
		if _ := g_gg_app.scheduler.begin_frame(30_000) { assert false, 'completed drag must have no recurring work' }
	}

	fn test_overlapping_targets_and_current_source_transform_are_authoritative() {
		reset_drag_fixture()
		// Last-painted destination owns overlap, even if it rejects the payload.
		upper := drag_fixture_target('upper', 100, reject_parcel)
		g_hit_targets << upper
		g_drag_registry.owners['id:upper'] = upper
		handle_touch_down(20, 30)
		handle_touch_up(120, 30)
		assert drag_records.filter(it.kind == .drag_enter)[0].id == 'upper'
		assert ElementEventKind.drop !in drag_kinds()

		reset_drag_fixture()
		handle_touch_down(20, 30)
		handle_touch_move(120, 30)
		// Reconciliation moves/scales the source while retaining its identity.
		g_hit_targets[0] = HitTarget{...g_hit_targets[0], x: 300,
			content_transform: ContentTransform{xx: 2, yy: 2, x: 100, y: 10}}
		sync_drag_session()
		handle_touch_up(120, 30)
		data := drag_records.filter(it.kind == .drop)[0].drag or { panic('missing') }
		assert data.offer.source_x == 10 && data.offer.source_y == 10
		assert drag_records.filter(it.kind == .drag_end).len == 1
	}

	fn test_window_snapshot_keeps_drag_capture_and_registry_isolated() {
		reset_drag_fixture()
		handle_touch_down(20, 30)
		handle_touch_move(120, 30)
		mut first := new_custom_window_state()
		first.capture()
		second := new_custom_window_state()
		second.restore()
		assert !drag_active() && g_drag_registry.owners.len == 0
		first.restore()
		assert drag_active() && g_touch.pointer_captured
		assert g_drag_registry.owners.len == 3
		handle_touch_up(120, 30)
		assert drag_records.filter(it.kind == .drop).len == 1
	}

	fn test_mounted_registry_survives_key_reorder_and_rejects_disabled_ancestor() {
		reset_drag_fixture()
		source := with_event(with_drag_source(view('source', rect(0, 0, 40, 40), BoxStyle{}, []), DragSource{}), record_drag)
		root := screen(0xffffff, [source])
		update_custom_focus_tree(root)
		generation := g_drag_registry.owners['id:source'].drag_generation
		update_custom_focus_tree(screen(0xffffff, [label('other', 'Other', rect(0, 0, 20, 20), TextStyle{}), source]))
		assert g_drag_registry.owners['id:source'].drag_generation == generation
		update_custom_focus_tree(Element{...root, enabled: false})
		assert g_drag_registry.owners.len == 0
		update_custom_focus_tree(root)
		assert g_drag_registry.owners['id:source'].drag_generation != generation
	}
}
