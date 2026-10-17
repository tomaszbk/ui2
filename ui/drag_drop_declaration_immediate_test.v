@[has_globals]
module ui2

$if macos && !ui2_headless ? {
	__global declaration_drag_events = []ElementEvent{}
	__global declaration_drag_case = ''
	__global declaration_drag_changed = false
	__global declaration_drag_anonymous = false
	__global declaration_drag_builds = 0
	__global declaration_drag_accepts = 0
	__global declaration_drag_armed = true
	__global declaration_drag_initial_flushes = u64(0)
	// The window under test, for the accept callback, which has no event.
	__global declaration_drag_window = &Window(unsafe { nil })

	fn declaration_drag_accept(_ DragOffer) DragOperation {
		mut w := declaration_drag_window
		declaration_drag_accepts++
		if declaration_drag_changed && declaration_drag_case == 'reject_target' { return .none }
		if declaration_drag_case in ['accept_withdraw', 'accept_refresh'] && declaration_drag_accepts == 3 {
			declaration_drag_changed = true
			w.request_refresh()
		}
		return .move
	}
	fn declaration_drag_reject(_ DragOffer) DragOperation { return .none }
	fn declaration_drag_record(event ElementEvent) {
		mut w := event.window
		declaration_drag_events << event
		if (declaration_drag_case == 'quit_on_start' && event.kind == .drag_start)
			|| (declaration_drag_case == 'quit_on_enter' && event.kind == .drag_enter) {
			w.quit()
			return
		}
		if event.kind != .drag_over || !declaration_drag_armed || declaration_drag_case in [
			'accept_withdraw',
			'accept_refresh',
		] {
			return
		}
		declaration_drag_armed = false
		declaration_drag_changed = true
		w.request_refresh()
		match declaration_drag_case {
			'cancel' { w.cancel_drag() }
			'restart' {
				w.cancel_drag()
				w.handle_touch_down(20, 30)
			}
			'quit' { w.quit() }
			'suspend' { w.scheduler.suspend() }
			'reentrant_release' { w.handle_touch_up(120, 30) }
			'scroll_target' { w.scroll_to_offset('release-pane', 50) }
			'menu_geometry' { w.set_menu_bar([Menu{ title: 'File' }]) }
			else {}
		}
	}
	fn declaration_drag_build(mut w Window) Element {
		declaration_drag_builds++
		if declaration_drag_changed {
			match declaration_drag_case {
				'build_cancel' { w.cancel_drag() }
				'build_quit' { w.quit() }
				'build_refresh' { w.request_refresh() }
				else {}
			}
		}
		id_source := if declaration_drag_anonymous { '' } else { 'declaration-source' }
		id_target := if declaration_drag_anonymous { '' } else { 'declaration-target' }
		mut source := with_event(with_drag_source(view(id_source, rect(10, 20, 40, 40), BoxStyle{}, []),
			DragSource{ allowed: [.move] }), declaration_drag_record)
		mut target := with_event(with_drop_target(view(id_target, rect(100, 20, 60, 50), BoxStyle{}, []),
			DropTarget{ accept: declaration_drag_accept }), declaration_drag_record)
		if declaration_drag_changed {
			match declaration_drag_case {
				'hide_target', 'accept_withdraw' { target = Element{ ...target, hidden: true } }
				'disable_target' { target = Element{ ...target, enabled: false } }
				'withdraw_target' { target = Element{ ...target, drop_target: none } }
				'hide_source' { source = Element{ ...source, hidden: true } }
				'disable_source' { source = Element{ ...source, enabled: false } }
				'withdraw_source' { source = Element{ ...source, drag_source: none } }
				'disallow_source' {
					source = Element{ ...source, drag_source: &DragSource{ allowed: [.copy] } }
				}
				'replace_accept' {
					target = Element{ ...target, drop_target: DropTarget{ accept: declaration_drag_reject } }
				}
				'move_target' { target = Element{ ...target, frame: rect(300, 20, 60, 50) } }
				'replace_source_kind' { source = Element{ ...source, kind: .image } }
				'replace_target_kind' { target = Element{ ...target, kind: .image } }
				else {}
			}
			if declaration_drag_case == 'remove_target' { return screen(0, [source]) }
			if declaration_drag_case == 'remove_source' { return screen(0, [target]) }
		}
		if declaration_drag_case == 'editable_blocker' {
			return screen(0, [source, target, Element{
				kind:   .text_field
				id:     'blocker'
				frame:  rect(100, 20, 60, 50)
				hidden: !declaration_drag_changed
			}])
		}
		if declaration_drag_case == 'scroll_target' {
			return screen(0, [source,
				scroll('release-pane', rect(0, 0, 300, 100), 0xffffff, [target,
					view('extent', rect(0, 600, 10, 10), BoxStyle{}, [])])])
		}
		return screen(0, [source, target])
	}
	fn reset_declaration_drag(case_name string, anonymous bool) &Window {
		mut w := &Window{
			build: declaration_drag_build
		}
		declaration_drag_window = w
		declaration_drag_case = case_name
		declaration_drag_changed = false
		declaration_drag_anonymous = anonymous
		declaration_drag_initial_flushes = 0
		declaration_drag_builds = 0
		declaration_drag_accepts = 0
		declaration_drag_armed = true
		declaration_drag_events = []ElementEvent{}
		root := declaration_drag_build(mut w)
		w.declared_root = root
		w.has_root = true
		w.update_custom_focus_tree(root)
		source_key := if anonymous { 'path:root/i:0' } else { 'id:declaration-source' }
		target_key := if anonymous { 'path:root/i:1' } else { 'id:declaration-target' }
		source := w.drag_registry.owners[source_key]
		target := w.drag_registry.owners[target_key]
		// Seed the initial rendered geometry only. All withdrawals below use
		// application state + the real build function + public w.request_refresh().
		w.hit_targets = [
			HitTarget{ ...source, x: 10, y: 20, w: 40, h: 40, button_behavior: true },
			HitTarget{ ...target, x: 100, y: 20, w: 60, h: 50 },
		]
		if case_name == 'scroll_target' {
			frame := rect(0, 0, 300, 100)
			w.register_scroll_view_in_parent(named_scroll_state_id('release-pane'), '', frame, frame, 600, true, true, true, HitTarget{})
		}
		return w
	}
	fn declaration_drag_assert_terminal(mut w Window, dropped bool) {
		kinds := declaration_drag_events.map(it.kind)
		assert kinds.filter(it == .drag_start).len == 1
		assert kinds.filter(it == .drag_enter).len == 1
		assert kinds.filter(it == .drag_leave).len == 1
		assert kinds.filter(it == .drop).len == if dropped { 1 } else { 0 }
		assert kinds.filter(it == .drag_end).len == if dropped { 1 } else { 0 }
		assert kinds.filter(it == .drag_cancel).len == if dropped { 0 } else { 1 }
		assert ElementEventKind.click !in kinds
		assert !w.touch.down && !w.touch.pointer_captured && !w.drag_active()
		assert w.scheduler.stats().draws == 0
		assert w.scheduler.stats().flushes == declaration_drag_initial_flushes
		w.handle_touch_up(120, 30)
		w.cancel_drag()
		assert declaration_drag_events.map(it.kind) == kinds
	}
	fn test_release_refresh_reconciles_target_withdrawal_before_next_frame() {
		for anonymous in [false, true] {
			for case_name in ['hide_target', 'disable_target', 'remove_target', 'withdraw_target',
				'move_target', 'replace_target_kind', 'editable_blocker', 'scroll_target',
				'menu_geometry'] {
				mut w := reset_declaration_drag(case_name, anonymous)
				w.handle_touch_down(20, 30)
				w.handle_touch_up(120, 30)
				assert declaration_drag_changed
				declaration_drag_assert_terminal(mut w, false)
				println('WITHDRAWAL target ${case_name} anonymous=${anonymous} PASS')
			}
		}
	}
	fn test_release_refresh_reconciles_source_withdrawal_before_next_frame() {
		for anonymous in [false, true] {
			for case_name in ['hide_source', 'disable_source', 'remove_source', 'withdraw_source',
				'replace_source_kind'] {
				mut w := reset_declaration_drag(case_name, anonymous)
				w.handle_touch_down(20, 30)
				w.handle_touch_up(120, 30)
				declaration_drag_assert_terminal(mut w, false)
				assert (declaration_drag_events.last().drag or { panic('missing cancel') }).reason == .source_removed
				println('WITHDRAWAL source ${case_name} anonymous=${anonymous} PASS')
			}
		}
	}
	fn test_release_refresh_revalidates_operations_and_current_accept_callback() {
		for case_name in ['disallow_source', 'reject_target', 'replace_accept', 'accept_withdraw'] {
			mut w := reset_declaration_drag(case_name, false)
			w.handle_touch_down(20, 30)
			w.handle_touch_up(120, 30)
			declaration_drag_assert_terminal(mut w, false)
		}
	}
	fn test_release_unchanged_refresh_still_drops_once_and_keeps_frame_pending() {
		for anonymous in [false, true] {
			mut w := reset_declaration_drag('unchanged', anonymous)
			w.handle_touch_down(20, 30)
			w.handle_touch_up(120, 30)
			declaration_drag_assert_terminal(mut w, true)
			assert declaration_drag_builds > 1
			assert w.scheduler.stats().pending
			println('UNCHANGED refresh anonymous=${anonymous} PASS')
		}
	}
	fn test_release_final_accept_unchanged_refresh_drops_once() {
		mut w := reset_declaration_drag('accept_refresh', false)
		w.handle_touch_down(20, 30)
		w.handle_touch_up(120, 30)
		assert declaration_drag_accepts == 3
		declaration_drag_assert_terminal(mut w, true)
	}

	fn test_reentrant_cancel_and_new_gesture_preserve_the_new_token() {
		mut w := reset_declaration_drag('restart', false)
		w.handle_touch_down(20, 30)
		token := w.touch.drag.token
		w.handle_touch_up(120, 30)
		assert w.touch.down && w.touch.pointer_captured && w.touch.drag.pending && !w.drag_active()
		assert w.touch.drag.token != token
		assert declaration_drag_events.map(it.kind) == [.drag_start, .drag_enter, .drag_over,
			.drag_leave, .drag_cancel]
		w.cancel_drag()
		w.handle_touch_up(120, 30)
		assert !w.touch.down && declaration_drag_events.len == 5
	}

	fn test_release_from_ui_dispatcher_task_reconciles_without_draining_another_loop() {
		mut w := reset_declaration_drag('unchanged', false)
		assert w.dispatcher().post(fn [mut w] () {
			w.handle_touch_down(20, 30)
			w.handle_touch_up(120, 30)
		})
		// The real task drain needs a drawing context, while this CPU fixture
		// exercises the same in-task state without any GPU or posted-loop work.
		w.draining_tasks = true
		for task in w.scheduler.take_tasks() { task() }
		w.draining_tasks = false
		declaration_drag_assert_terminal(mut w, true)
	}

	fn test_release_quit_on_start_or_enter_stops_further_nonterminal_callbacks() {
		for case_name in ['quit_on_start', 'quit_on_enter'] {
			mut w := reset_declaration_drag(case_name, false)
			w.handle_touch_down(20, 30)
			w.handle_touch_up(120, 30)
			assert declaration_drag_events.map(it.kind) == if case_name == 'quit_on_start' {
				[ElementEventKind.drag_start, .drag_cancel]
			} else {
				[ElementEventKind.drag_start, .drag_enter, .drag_leave, .drag_cancel]
			}
			assert !w.touch.down && !w.touch.pointer_captured && !w.drag_active()
		}
	}

	fn test_pruned_unmounted_scroll_state_does_not_invalidate_hit_geometry() {
		mut w := reset_declaration_drag('unchanged', false)
		w.scroll_offsets['unmounted'] = 40
		w.prune_unmounted_state()
		assert 'unmounted' !in w.scroll_offsets
		work := w.scheduler.begin_frame(0) or { panic('missing mount') }
		w.scheduler.finish_frame(work)
		declaration_drag_initial_flushes = w.scheduler.stats().flushes
		w.handle_touch_down(20, 30)
		w.handle_touch_up(120, 30)
		declaration_drag_assert_terminal(mut w, true)
	}

	fn test_release_cancel_quit_suspend_and_reentrant_builder_never_commit_drop() {
		for case_name in ['cancel', 'quit', 'suspend', 'build_cancel', 'build_quit', 'build_refresh'] {
			mut w := reset_declaration_drag(case_name, false)
			w.handle_touch_down(20, 30)
			w.handle_touch_up(120, 30)
			declaration_drag_assert_terminal(mut w, false)
		}
		mut w := reset_declaration_drag('reentrant_release', false)
		w.handle_touch_down(20, 30)
		w.handle_touch_up(120, 30)
		declaration_drag_assert_terminal(mut w, true)
	}
}
