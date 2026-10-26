// vtest vflags: -d ui2_custom_rendering
@[has_globals]
module ui2

$if (android || linux || ((ios || macos || windows) && ui2_custom_rendering ?)) && !ui2_headless ? {
	import gg

	struct Parcel {
		code int
	}
	fn (p Parcel) drag_type() string { return 'parcel' }

	__global drag_records = []ElementEvent{}
	__global drag_cancel_on_enter = false

	fn record_drag(event ElementEvent) {
		mut w := event.window
		drag_records << event
		if event.kind == .drag_enter && drag_cancel_on_enter { w.cancel_drag() }
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
		return HitTarget{
			id:              id
			identity:        id
			w:               60
			h:               50
			x:               x
			y:               20
			on_event:        record_drag
			drag_generation: if id == 'target' { u64(2) } else { u64(3) }
			drop_target:     DropTarget{ accept: accept }
		}
	}
	fn new_drag_fixture() &Window {
		mut w := &Window{}
		w.touch = TouchState{}
		w.tooltip = TooltipState{}
		w.reset_scroll_frame()
		w.close_dropdown()
		drag_records = []ElementEvent{}
		drag_cancel_on_enter = false
		source := HitTarget{
			id:              'source'
			identity:        'source'
			w:               40
			h:               40
			x:               10
			y:               20
			on_event:        record_drag
			button_behavior: true
			drag_generation: 1
			drag_source:     &DragSource{ payload: Parcel{42}, allowed: [.copy, .move] }
		}
		target := drag_fixture_target('target', 100, accept_parcel)
		rejected := drag_fixture_target('rejected', 200, reject_parcel)
		w.hit_targets = [source, target, rejected]
		w.drag_registry = DragRegistry{ owners: {
			'id:source':   source
			'id:target':   target
			'id:rejected': rejected
		}, generation: 3 }
		return w
	}
	fn drag_kinds() []ElementEventKind {
		return drag_records.map(it.kind)
	}

	fn test_drag_capture_outside_source_and_exactly_one_drop_no_residual_tap() {
		mut w := new_drag_fixture()
		w.handle_touch_down(20, 30)
		w.handle_touch_move(80, 30)
		assert w.drag_active() && w.touch.pointer_captured
		w.handle_touch_move(120, 30)
		w.handle_touch_up(120, 30)
		w.handle_touch_up(120, 30)
		w.handle_touch_move(20, 30)
		assert drag_kinds() == [.drag_start, .drag_enter, .drag_over, .drag_over, .drop, .drag_leave,
			.drag_end]
		assert !w.touch.down && !w.touch.pointer_captured && !w.drag_active()
		event := drag_records[4].drag or { panic('missing drag data') }
		assert event.operation == .move && event.reason == .none
		assert event.offer.source_id == 'source' && event.offer.target_id == 'target'
		assert event.offer.payload is Parcel
		if event.offer.payload is Parcel {
			assert event.offer.payload.code == 42
		}
	}

	fn test_threshold_short_press_and_coalesced_release() {
		mut w := new_drag_fixture()
		w.handle_touch_down(20, 30)
		w.handle_touch_move(26, 30) // boundary does not start a drag
		assert !w.drag_active()
		w.handle_touch_up(26, 30)
		assert drag_kinds() == [.click]
		w = new_drag_fixture()
		w.hit_targets[0] = HitTarget{ ...w.hit_targets[0], drag_source: &DragSource{ threshold: 20 } }
		w.drag_registry.owners['id:source'] = w.hit_targets[0]
		w.handle_touch_down(20, 30)
		w.handle_touch_move(35, 30) // below source threshold, beyond raw tap threshold
		w.handle_touch_up(35, 30)
		assert drag_kinds() == [.click]
		w = new_drag_fixture()
		w.handle_touch_down(20, 30)
		w.handle_touch_up(120, 30) // no intermediate move from host
		assert drag_kinds() == [.drag_start, .drag_enter, .drag_over, .drop, .drag_leave, .drag_end]
	}

	fn test_invalid_target_enter_leave_and_operation_rejection_are_deterministic() {
		mut w := new_drag_fixture()
		w.handle_touch_down(20, 30)
		w.handle_touch_move(120, 30)
		w.handle_touch_move(220, 30)
		w.handle_touch_up(220, 30)
		assert drag_kinds() == [.drag_start, .drag_enter, .drag_over, .drag_leave, .drag_enter,
			.drag_over, .drag_over, .drag_leave, .drag_cancel]
		assert (drag_records.last().drag or { panic('missing') }).reason == .invalid_target
		for event in drag_records {
			if event.id == 'rejected' {
				assert (event.drag or { panic('missing') }).operation == .none
			}
		}
		w = new_drag_fixture()
		w.hit_targets[1] = drag_fixture_target('target', 100, unoffered_operation)
		w.drag_registry.owners['id:target'] = w.hit_targets[1]
		w.handle_touch_down(20, 30)
		w.handle_touch_up(120, 30)
		assert ElementEventKind.drop !in drag_kinds()
		assert drag_records.last().kind == .drag_cancel
	}

	fn test_captured_operations_do_not_expand_when_application_changes_its_array() {
		mut w := new_drag_fixture()
		mut offered := [DragOperation.move]
		w.hit_targets[0] = HitTarget{
			...w.hit_targets[0]
			drag_source: &DragSource{ payload: Parcel{42}, allowed: offered }
		}
		w.drag_registry.owners['id:source'] = w.hit_targets[0]
		w.hit_targets[1] = drag_fixture_target('target', 100, unoffered_operation)
		w.drag_registry.owners['id:target'] = w.hit_targets[1]
		w.handle_touch_down(20, 30)
		offered[0] = .link
		w.drag_registry.owners['id:source'] = HitTarget{
			...w.hit_targets[0]
			drag_source: &DragSource{ payload: Parcel{42}, allowed: [.link] }
		}
		w.handle_touch_up(120, 30)
		assert ElementEventKind.drop !in drag_kinds(), 'link was not offered at pointer-down'
		assert (drag_records[0].drag or { panic('missing') }).offer.allowed == [DragOperation.move]
		assert drag_records.last().kind == .drag_cancel
	}

	fn test_escape_deactivation_cancel_and_reentrant_cancel_release_capture() {
		mut w := &Window{}
		for reason in [DragCancelReason.escape, .focus_lost, .cancelled] {
			w = new_drag_fixture()
			w.handle_touch_down(20, 30)
			w.handle_touch_move(120, 30)
			match reason {
				.escape { on_event(&gg.Event{ typ: .key_down, key_code: .escape }, mut w) }
				.focus_lost { on_event(&gg.Event{ typ: .unfocused }, mut w) }
				else { w.cancel_drag() }
			}
			w.handle_touch_up(120, 30)
			w.cancel_drag()
			assert drag_kinds() == [.drag_start, .drag_enter, .drag_over, .drag_leave, .drag_cancel]
			assert (drag_records.last().drag or { panic('missing') }).reason == reason
			assert !w.touch.down && !w.drag_active()
		}
		w = new_drag_fixture()
		drag_cancel_on_enter = true
		w.handle_touch_down(20, 30)
		w.handle_touch_move(120, 30)
		w.handle_touch_up(120, 30)
		assert drag_kinds() == [.drag_start, .drag_enter, .drag_leave, .drag_cancel]
	}

	fn test_current_target_geometry_and_generation_control_drop_not_captured_bounds() {
		mut w := new_drag_fixture()
		w.handle_touch_down(20, 30)
		w.handle_touch_move(120, 30)
		w.hit_targets[1] = HitTarget{ ...w.hit_targets[1], x: 300 }
		w.sync_drag_session()
		assert drag_records.last().kind == .drag_leave
		w.handle_touch_up(120, 30)
		assert drag_records.last().kind == .drag_cancel
		assert ElementEventKind.drop !in drag_kinds()

		w = new_drag_fixture()
		w.handle_touch_down(20, 30)
		w.handle_touch_move(120, 30)
		w.drag_registry.owners.delete('id:target')
		w.sync_drag_session()
		assert drag_records.last().kind == .drag_leave
		w.handle_touch_up(120, 30)
		assert ElementEventKind.drop !in drag_kinds()
	}

	fn test_source_unmount_generation_and_clipped_source_have_distinct_lifetimes() {
		mut w := new_drag_fixture()
		w.handle_touch_down(20, 30)
		w.handle_touch_move(80, 30)
		w.hit_targets.delete(0) // source still mounted but culled by Scroll
		w.sync_drag_session()
		assert w.drag_active()
		w.handle_touch_up(120, 30)
		assert ElementEventKind.drop in drag_kinds()

		for replacement in [false, true] {
			w = new_drag_fixture()
			w.handle_touch_down(20, 30)
			w.handle_touch_move(120, 30)
			if replacement {
				w.drag_registry.owners['id:source'] = HitTarget{ ...w.hit_targets[0], drag_generation: 99 }
			} else {
				w.drag_registry.owners.delete('id:source')
			}
			w.sync_drag_session()
			w.handle_touch_up(120, 30)
			assert drag_records.last().kind == .drag_cancel
			assert (drag_records.last().drag or { panic('missing') }).reason == .source_removed
			assert ElementEventKind.drop !in drag_kinds()
		}
	}

	fn test_scaled_current_coordinates_preview_and_shared_clipping() {
		mut w := new_drag_fixture()
		// Hand-derived composition mapping: window=(10+2*x,20+2*y).
		transform := ContentTransform{ xx: 2, yy: 2, x: 10, y: 20 }
		w.hit_targets[0] = HitTarget{ ...w.hit_targets[0], content_transform: transform }
		w.hit_targets[1] = HitTarget{ ...w.hit_targets[1], content_transform: ContentTransform{ xx: 0.5, yy: 0.5, x: 100, y: 20 } }
		w.handle_touch_down(20, 30)
		w.handle_touch_up(120, 30)
		drop := drag_records.filter(it.kind == .drop)[0]
		data := drop.drag or { panic('missing') }
		assert drop.x == 40 && drop.y == 20
		assert data.offer.source_x == 55 && data.offer.source_y == 5
		assert data.offer.window_x == 120 && data.offer.window_y == 30
		for dpi in [1.0, 1.25, 1.5, 2.0] {
			preview := drag_preview_transform(transform, 200, 80)
			assert presentation_rect(preview.project(rect(12, 12, 40, 20)), dpi) == rect(224, 104, 80, 40)
		}

		w = new_drag_fixture()
		w.hit_targets = []HitTarget{}
		// Registration uses the existing shared clip/project helper. Only the
		// left half of target is visible; drops outside it cannot hit.
		w.add_hit_target(drag_fixture_target('target', 100, accept_parcel), rect(100, 20, 20, 50))
		assert w.drag_destination(110, 30).id == 'target'
		assert w.drag_destination(130, 30).id == ''
	}

	fn test_drag_wins_content_scroll_but_scrollbar_and_raw_draggable_keep_their_capture() {
		mut w := new_drag_fixture()
		frame := rect(0, 0, 300, 100)
		w.register_scroll_view_in_parent(named_scroll_state_id('pane'), '', frame, frame, 600, true, true, true, HitTarget{})
		w.handle_touch_down(20, 30)
		w.handle_touch_move(120, 60)
		assert w.scroll_offset('pane') == 0
		w.handle_touch_up(120, 60)
		assert ElementEventKind.drop in drag_kinds()
		w = new_drag_fixture()
		w.register_scroll_view_in_parent(named_scroll_state_id('pane'), '', frame, frame, 600, true, true, true, HitTarget{})
		bar := scrollbar_geometry(frame, 600, 0, true)
		w.handle_touch_down(bar.thumb.x + 1, bar.thumb.y + 1)
		assert w.touch.scrollbar_drag && !w.touch.drag.pending
		w.handle_touch_move(bar.thumb.x + 1, 60)
		w.handle_touch_up(bar.thumb.x + 1, 60)
		assert drag_records.len == 0
		assert w.scroll_offset('pane') > 0
	}

	fn test_drag_preserves_focus_utf8_selection_scroll_composition_and_returns_idle() {
		mut w := new_drag_fixture()
		w.focused_field = 'editor'
		w.replace_text_editor('editor', TextEditor{ text: 'niño café'.clone(), selection: TextSelection{ anchor: 2, caret: 5 } })
		w.replace_text_value('editor', 'niño café')
		w.composition = TextComposition{ field_id: 'editor', text: 'á', start: 2, end: 5, mark_length: 1, selection: TextSelection{ anchor: 1, caret: 1 } }
		composition := w.composition
		w.scroll_offsets[named_scroll_state_id('pane')] = 42
		w.handle_touch_down(20, 30)
		w.handle_touch_up(120, 30)
		assert w.focused_field == 'editor'
		assert w.text('editor') == 'niño café'
		assert w.text_editors['editor'].selection == TextSelection{ anchor: 2, caret: 5 }
		assert w.composition == composition
		assert w.scroll_offset('pane') == 42
		assert w.custom_visual_deadline() == -1
		work := w.scheduler.begin_frame(0) or { panic('missing final paint') }
		w.scheduler.set_deadline(w.custom_visual_deadline())
		w.scheduler.finish_frame(work)
		if _ := w.scheduler.begin_frame(30_000) {
			assert false, 'completed drag must have no recurring work'
		}
	}

	fn test_overlapping_targets_and_current_source_transform_are_authoritative() {
		mut w := new_drag_fixture()
		// Last-painted destination owns overlap, even if it rejects the payload.
		upper := drag_fixture_target('upper', 100, reject_parcel)
		w.hit_targets << upper
		w.drag_registry.owners['id:upper'] = upper
		w.handle_touch_down(20, 30)
		w.handle_touch_up(120, 30)
		assert drag_records.filter(it.kind == .drag_enter)[0].id == 'upper'
		assert ElementEventKind.drop !in drag_kinds()

		w = new_drag_fixture()
		w.handle_touch_down(20, 30)
		w.handle_touch_move(120, 30)
		// Reconciliation moves/scales the source while retaining its identity.
		w.hit_targets[0] = HitTarget{
			...w.hit_targets[0]
			x:                 300
			content_transform: ContentTransform{ xx: 2, yy: 2, x: 100, y: 10 }
		}
		w.sync_drag_session()
		w.handle_touch_up(120, 30)
		data := drag_records.filter(it.kind == .drop)[0].drag or { panic('missing') }
		assert data.offer.source_x == 10 && data.offer.source_y == 10
		assert drag_records.filter(it.kind == .drag_end).len == 1
	}

	fn test_windows_keep_drag_capture_and_registry_isolated() {
		mut w := new_drag_fixture()
		w.handle_touch_down(20, 30)
		w.handle_touch_move(120, 30)
		mut other := &Window{}
		assert !other.drag_active() && other.drag_registry.owners.len == 0
		assert w.drag_active() && w.touch.pointer_captured
		assert w.drag_registry.owners.len == 3
		w.handle_touch_up(120, 30)
		assert drag_records.filter(it.kind == .drop).len == 1
	}

	fn test_mounted_registry_survives_key_reorder_and_rejects_disabled_ancestor() {
		mut w := new_drag_fixture()
		source := with_event(with_drag_source(view('source', rect(0, 0, 40, 40), BoxStyle{}, []), DragSource{}), record_drag)
		root := screen(0xffffff, [source])
		w.update_custom_focus_tree(root)
		generation := w.drag_registry.owners['id:source'].drag_generation
		w.update_custom_focus_tree(screen(0xffffff, [
			label('other', 'Other', rect(0, 0, 20, 20), TextStyle{}),
			source,
		]))
		assert w.drag_registry.owners['id:source'].drag_generation == generation
		w.update_custom_focus_tree(Element{ ...root, enabled: false })
		assert w.drag_registry.owners.len == 0
		w.update_custom_focus_tree(root)
		assert w.drag_registry.owners['id:source'].drag_generation != generation
	}
}
