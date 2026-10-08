// vtest vflags: -d ui2_custom_rendering
@[has_globals]
module ui2

$if macos && ui2_custom_rendering ? && !ui2_headless ? {
	__global declaration_drag_events = []ElementEvent{}
	__global declaration_drag_case = ''
	__global declaration_drag_changed = false
	__global declaration_drag_anonymous = false
	__global declaration_drag_builds = 0
	__global declaration_drag_accepts = 0
	__global declaration_drag_armed = true
	__global declaration_drag_initial_flushes = u64(0)

	fn declaration_drag_accept(_ DragOffer) DragOperation {
		declaration_drag_accepts++
		if declaration_drag_changed && declaration_drag_case == 'reject_target' { return .none }
		if declaration_drag_case in ['accept_withdraw', 'accept_refresh'] && declaration_drag_accepts == 3 {
			declaration_drag_changed = true
			refresh()
		}
		return .move
	}
	fn declaration_drag_reject(_ DragOffer) DragOperation { return .none }
	fn declaration_drag_record(event ElementEvent) {
		declaration_drag_events << event
		if (declaration_drag_case == 'quit_on_start' && event.kind == .drag_start)
			|| (declaration_drag_case == 'quit_on_enter' && event.kind == .drag_enter) { quit(); return }
		if event.kind != .drag_over || !declaration_drag_armed || declaration_drag_case in ['accept_withdraw', 'accept_refresh'] { return }
		declaration_drag_armed = false
		declaration_drag_changed = true
		refresh()
		match declaration_drag_case {
			'cancel' { cancel_drag() }
			'restart' { cancel_drag(); handle_touch_down(20, 30) }
			'quit' { quit() }
			'suspend' { g_gg_app.scheduler.suspend() }
			'reentrant_release' { handle_touch_up(120, 30) }
			'scroll_target' { scroll_to_offset('release-pane', 40) }
			'menu_geometry' { set_menu_bar([Menu{title: 'File'}]) }
			else {}
		}
	}
	fn declaration_drag_build() Element {
		declaration_drag_builds++
		if declaration_drag_changed {
			match declaration_drag_case {
				'build_cancel' { cancel_drag() }
				'build_quit' { quit() }
				'build_refresh' { refresh() }
				else {}
			}
		}
		id_source := if declaration_drag_anonymous { '' } else { 'declaration-source' }
		id_target := if declaration_drag_anonymous { '' } else { 'declaration-target' }
		mut source := with_event(with_drag_source(view(id_source, rect(10, 20, 40, 40), BoxStyle{}, []),
			DragSource{allowed: [.move]}), declaration_drag_record)
		mut target := with_event(with_drop_target(view(id_target, rect(100, 20, 60, 50), BoxStyle{}, []),
			DropTarget{accept: declaration_drag_accept}), declaration_drag_record)
		if declaration_drag_changed {
			match declaration_drag_case {
				'hide_target', 'accept_withdraw' { target = Element{...target, hidden: true} }
				'disable_target' { target = Element{...target, enabled: false} }
				'withdraw_target' { target = Element{...target, drop_target: none} }
				'hide_source' { source = Element{...source, hidden: true} }
				'disable_source' { source = Element{...source, enabled: false} }
				'withdraw_source' { source = Element{...source, drag_source: none} }
				'disallow_source' { source = Element{...source, drag_source: DragSource{allowed: [.copy]}} }
				'replace_accept' { target = Element{...target, drop_target: DropTarget{accept: declaration_drag_reject}} }
				'move_target' { target = Element{...target, frame: rect(300, 20, 60, 50)} }
				'replace_source_kind' { source = Element{...source, kind: .image} }
				'replace_target_kind' { target = Element{...target, kind: .image} }
				else {}
			}
			if declaration_drag_case == 'remove_target' { return screen(0, [source]) }
			if declaration_drag_case == 'remove_source' { return screen(0, [target]) }
		}
		if declaration_drag_case == 'editable_blocker' {
			return screen(0, [source, target, Element{kind: .text_field, id: 'blocker',
				frame: rect(100, 20, 60, 50), readonly: !declaration_drag_changed}])
		}
		return screen(0, [source, target])
	}
	fn reset_declaration_drag(case_name string, anonymous bool) {
		g_gg_app = &GgApp{}
		g_touch = TouchState{}
		g_drag_registry = DragRegistry{}
		g_tooltip = TooltipState{}
		g_scroll_offsets = map[string]f64{}
		g_active_scrolls = map[string]bool{}
		set_menu_bar([]Menu{})
		reset_scroll_frame()
		close_dropdown()
		g_build_screen = declaration_drag_build
		declaration_drag_case = case_name
		declaration_drag_changed = false
		declaration_drag_anonymous = anonymous
		declaration_drag_initial_flushes = 0
		declaration_drag_builds = 0
		declaration_drag_accepts = 0
		declaration_drag_armed = true
		declaration_drag_events = []ElementEvent{}
		root := declaration_drag_build()
		g_gg_app.declared_root = root
		g_gg_app.has_root = true
		refresh_drag_owners(root)
		source_key := if anonymous { 'path:root/i:0' } else { 'id:declaration-source' }
		target_key := if anonymous { 'path:root/i:1' } else { 'id:declaration-target' }
		source := g_drag_registry.owners[source_key]
		target := g_drag_registry.owners[target_key]
		// Seed the initial rendered geometry only. All withdrawals below use
		// application state + the real build function + public refresh().
		g_hit_targets = [HitTarget{...source, x: 10, y: 20, w: 40, h: 40, button_behavior: true},
			HitTarget{...target, x: 100, y: 20, w: 60, h: 50}]
		if case_name == 'scroll_target' {
			frame := rect(0, 0, 300, 100)
			register_scroll_view(named_scroll_state_id('release-pane'), frame, frame, 600, true, true, true, HitTarget{})
		}
	}
	fn declaration_drag_assert_terminal(dropped bool) {
		kinds := declaration_drag_events.map(it.kind)
		assert kinds.filter(it == .drag_start).len == 1
		assert kinds.filter(it == .drag_enter).len == 1
		assert kinds.filter(it == .drag_leave).len == 1
		assert kinds.filter(it == .drop).len == if dropped { 1 } else { 0 }
		assert kinds.filter(it == .drag_end).len == if dropped { 1 } else { 0 }
		assert kinds.filter(it == .drag_cancel).len == if dropped { 0 } else { 1 }
		assert ElementEventKind.tap !in kinds
		assert !g_touch.down && !g_touch.pointer_captured && !drag_active()
		assert g_gg_app.scheduler.stats().draws == 0
		assert g_gg_app.scheduler.stats().flushes == declaration_drag_initial_flushes
		handle_touch_up(120, 30)
		cancel_drag()
		assert declaration_drag_events.map(it.kind) == kinds
	}
	fn test_release_refresh_reconciles_target_withdrawal_before_next_frame() {
		for anonymous in [false, true] {
			for case_name in ['hide_target', 'disable_target', 'remove_target', 'withdraw_target', 'move_target', 'replace_target_kind', 'editable_blocker', 'scroll_target', 'menu_geometry'] {
				reset_declaration_drag(case_name, anonymous)
				handle_touch_down(20, 30)
				handle_touch_up(120, 30)
				assert declaration_drag_changed
				declaration_drag_assert_terminal(false)
				println('WITHDRAWAL target ${case_name} anonymous=${anonymous} PASS')
			}
		}
	}
	fn test_release_refresh_reconciles_source_withdrawal_before_next_frame() {
		for anonymous in [false, true] {
			for case_name in ['hide_source', 'disable_source', 'remove_source', 'withdraw_source', 'replace_source_kind'] {
				reset_declaration_drag(case_name, anonymous)
				handle_touch_down(20, 30)
				handle_touch_up(120, 30)
				declaration_drag_assert_terminal(false)
				assert (declaration_drag_events.last().drag or { panic('missing cancel') }).reason == .source_removed
				println('WITHDRAWAL source ${case_name} anonymous=${anonymous} PASS')
			}
		}
	}
	fn test_release_refresh_revalidates_operations_and_current_accept_callback() {
		for case_name in ['disallow_source', 'reject_target', 'replace_accept', 'accept_withdraw'] {
			reset_declaration_drag(case_name, false)
			handle_touch_down(20, 30)
			handle_touch_up(120, 30)
			declaration_drag_assert_terminal(false)
		}
	}
	fn test_release_unchanged_refresh_still_drops_once_and_keeps_frame_pending() {
		for anonymous in [false, true] {
			reset_declaration_drag('unchanged', anonymous)
			handle_touch_down(20, 30)
			handle_touch_up(120, 30)
			declaration_drag_assert_terminal(true)
			assert declaration_drag_builds > 1
			assert g_gg_app.scheduler.stats().pending
			println('UNCHANGED refresh anonymous=${anonymous} PASS')
		}
	}
	fn test_release_final_accept_unchanged_refresh_drops_once() {
		reset_declaration_drag('accept_refresh', false)
		handle_touch_down(20, 30)
		handle_touch_up(120, 30)
		assert declaration_drag_accepts == 3
		declaration_drag_assert_terminal(true)
	}

	fn test_reentrant_cancel_and_new_gesture_preserve_the_new_token() {
		reset_declaration_drag('restart', false)
		handle_touch_down(20, 30)
		token := g_touch.drag.token
		handle_touch_up(120, 30)
		assert g_touch.down && g_touch.pointer_captured && g_touch.drag.pending && !drag_active()
		assert g_touch.drag.token != token
		assert declaration_drag_events.map(it.kind) == [.drag_start, .drag_enter, .drag_over, .drag_leave, .drag_cancel]
		cancel_drag()
		handle_touch_up(120, 30)
		assert !g_touch.down && declaration_drag_events.len == 5
	}

	fn test_release_from_ui_dispatcher_task_reconciles_without_draining_another_loop() {
		reset_declaration_drag('unchanged', false)
		assert ui_dispatcher().post(fn () {
			handle_touch_down(20, 30)
			handle_touch_up(120, 30)
		})
		// The real task drain needs a drawing context, while this CPU fixture
		// exercises the same in-task state without any GPU or posted-loop work.
		g_gg_app.draining_tasks = true
		for task in g_gg_app.scheduler.take_tasks() { task() }
		g_gg_app.draining_tasks = false
		declaration_drag_assert_terminal(true)
	}

	fn test_release_quit_on_start_or_enter_stops_further_nonterminal_callbacks() {
		for case_name in ['quit_on_start', 'quit_on_enter'] {
			reset_declaration_drag(case_name, false)
			handle_touch_down(20, 30)
			handle_touch_up(120, 30)
			assert declaration_drag_events.map(it.kind) == if case_name == 'quit_on_start' {
				[ElementEventKind.drag_start, .drag_cancel]
			} else { [ElementEventKind.drag_start, .drag_enter, .drag_leave, .drag_cancel] }
			assert !g_touch.down && !g_touch.pointer_captured && !drag_active()
		}
	}

	fn test_pruned_unmounted_scroll_state_does_not_invalidate_hit_geometry() {
		reset_declaration_drag('unchanged', false)
		g_scroll_offsets['unmounted'] = 40
		assert drag_hit_scroll_offsets().len == 0
		g_gg_app.hit_declaration = g_gg_app.declared_root
		g_gg_app.hit_scroll_offsets = drag_hit_scroll_offsets()
		g_gg_app.has_hit_declaration = true
		prune_unmounted_state()
		assert 'unmounted' !in g_scroll_offsets
		work := g_gg_app.scheduler.begin_frame(0) or { panic('missing mount') }
		g_gg_app.scheduler.finish_frame(work)
		declaration_drag_initial_flushes = g_gg_app.scheduler.stats().flushes
		handle_touch_down(20, 30)
		handle_touch_up(120, 30)
		declaration_drag_assert_terminal(true)
	}

	fn test_release_cancel_quit_suspend_and_reentrant_builder_never_commit_drop() {
		for case_name in ['cancel', 'quit', 'suspend', 'build_cancel', 'build_quit', 'build_refresh'] {
			reset_declaration_drag(case_name, false)
			handle_touch_down(20, 30)
			handle_touch_up(120, 30)
			declaration_drag_assert_terminal(false)
		}
		reset_declaration_drag('reentrant_release', false)
		handle_touch_down(20, 30)
		handle_touch_up(120, 30)
		declaration_drag_assert_terminal(true)
	}
}
