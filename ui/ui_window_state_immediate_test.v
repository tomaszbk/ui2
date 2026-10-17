@[has_globals]
module ui2

// Every window owns its input, text, focus, scroll, menu and timing state, so
// two windows that mount the same ids never see each other's state.

$if (android || ios || linux || macos || windows) && !ui2_headless ? {
	struct WindowStateEvent {
		window string
		event  ElementEvent
	}

	__global window_state_events = []WindowStateEvent{}

	fn first_window_state_event(event ElementEvent) {
		window_state_events << WindowStateEvent{ window: 'first', event: event }
	}

	fn second_window_state_event(event ElementEvent) {
		window_state_events << WindowStateEvent{ window: 'second', event: event }
	}

	fn window_state_mount_editor(mut w Window, on_event ElementCallback) {
		// Scroll's 16-unit bottom inset keeps the original 500-unit range.
		root := screen(0xffffff, [
			Element{ kind: .text_area, id: 'editor', on_event: on_event },
			Element{
				kind:     .scroll
				id:       'pane'
				frame:    rect(0, 0, 100, 80)
				children: [
					Element{ kind: .view, frame: rect(0, 0, 100, 484) },
				]
			},
		])
		w.update_custom_focus_tree(root)
		w.sync_mounted_focus_controls(root, 'root')
	}
}

fn test_custom_windows_same_ids_keep_independent_edits_focus_scroll_and_menus() {
	$if (android || ios || linux || macos || windows) && !ui2_headless ? {
		previous_events := window_state_events.clone()
		mut first := &Window{}
		mut second := &Window{}
		defer {
			first.forget_text_state('editor')
			second.forget_text_state('editor')
			window_state_events = previous_events.clone()
		}
		window_state_events = []WindowStateEvent{}
		first.set_menu_bar([Menu{ title: 'First menu', items: [MenuItem{ ...menu_item('command', 'First command'), on_select: first_window_state_event }] }])
		window_state_mount_editor(mut first, first_window_state_event)
		first.set_text('editor', 'first draft')
		first.focus('editor')
		first.text_area_set_selection('editor', 0, 5)
		clear := first.scheduler.begin_frame(0) or { panic('first window did not mount') }
		first.scheduler.finish_frame(clear)
		first.scroll_to_offset('pane', 70)
		first.handle_char_input(u32(`A`))
		assert first.text('editor') == 'A draft'
		assert first.text_area_caret('editor') == 1
		assert first.text_area_selection_length('editor') == 0
		assert window_state_events == [WindowStateEvent{ window: 'first', event: ElementEvent{ window: first, kind: .change, id: 'editor', text: 'A draft' } }]

		assert second.text('editor') == ''
		assert second.focused_id() == ''
		assert second.scroll_offset('pane') == 0
		assert second.menu_bar().len == 0
		second.set_menu_bar([Menu{ title: 'Second menu', items: [MenuItem{ ...menu_item('command', 'Second command'), on_select: second_window_state_event }] }])
		window_state_mount_editor(mut second, second_window_state_event)
		second.set_text('editor', 'second draft')
		second.focus('editor')
		second.text_area_set_selection('editor', 7, 5)
		second.scroll_to_offset('pane', 180)
		second.handle_char_input(u32(`B`))
		assert second.text('editor') == 'second B'
		assert second.text_area_caret('editor') == 8
		second.emit_menu_callback(second.menu_bar()[0].items[0].on_select, 'command')

		assert first.text('editor') == 'A draft'
		assert first.focused_id() == 'editor'
		assert first.text_area_caret('editor') == 1
		assert first.scroll_offset('pane') == 70
		assert first.menu_bar()[0].title == 'First menu'
		first.emit_menu_callback(first.menu_bar()[0].items[0].on_select, 'command')
		first.dismiss_keyboard()
		assert first.focused_id() == ''

		assert second.text('editor') == 'second B'
		assert second.focused_id() == 'editor'
		assert second.text_area_caret('editor') == 8
		assert second.scroll_offset('pane') == 180
		assert second.menu_bar()[0].title == 'Second menu'
		assert window_state_events == [
			WindowStateEvent{ window: 'first', event: ElementEvent{ window: first, kind: .change, id: 'editor', text: 'A draft' } },
			WindowStateEvent{ window: 'second', event: ElementEvent{ window: second, kind: .change, id: 'editor', text: 'second B' } },
			WindowStateEvent{ window: 'second', event: ElementEvent{ window: second, kind: .click, id: 'command' } },
			WindowStateEvent{ window: 'first', event: ElementEvent{ window: first, kind: .click, id: 'command' } },
		]
	}
}

fn test_custom_windows_keep_focus_and_pending_scroll_requests_apart() {
	$if (android || ios || linux || macos || windows) && !ui2_headless ? {
		mut first := &Window{}
		mut second := &Window{}
		first.focused_field = 'first focus'
		// A pane that has not mounted yet keeps the request for its window.
		first.scroll_to_offset('later', 90)
		assert first.pending_scroll[named_scroll_state_id('later')] == 90
		assert second.pending_scroll.len == 0
		second.focused_field = 'second focus'
		assert first.focused_id() == 'first focus'
		assert second.focused_id() == 'second focus'
	}
}

// Motion is retained by each window's own motion tree; visual deadlines are
// window state too.
fn test_custom_windows_isolate_visual_deadlines() {
	$if (android || ios || linux || macos || windows) && !ui2_headless ? {
		mut first := &Window{}
		mut second := &Window{}
		assert voidptr(first.motion_tree) != voidptr(second.motion_tree)
		first.tooltip = TooltipState{ pointer_in: true, key: 'help', rest_since: 1_000 }
		first.scheduler.set_deadline(first.custom_visual_deadline())
		assert first.scheduler.stats().next_deadline == 1_500

		assert second.custom_visual_deadline() == -1
		second.scheduler.set_deadline(second.custom_visual_deadline())
		assert second.scheduler.stats().next_deadline == -1

		assert first.custom_visual_deadline() == 1_500
		on_cleanup(mut first)
		assert first.scheduler.is_closed()
		assert first.custom_visual_deadline() == -1
		assert !second.scheduler.is_closed()
		assert second.scheduler.stats().next_deadline == -1
	}
}

fn test_custom_windows_keep_scroll_callback_declarations_independent() {
	$if (android || ios || linux || macos || windows) && !ui2_headless ? {
		mut first := &Window{}
		mut second := &Window{}
		mut first_events := &[]ElementEvent{}
		mut second_events := &[]ElementEvent{}
		first_callback := fn [mut first_events] (event ElementEvent) { first_events << event }
		second_callback := fn [mut second_events] (event ElementEvent) { second_events << event }
		frame := rect(0, 0, 100, 100)
		first.register_scroll_view_in_parent(named_scroll_state_id('pane'), '', frame, frame, 500, true, true, false,
			HitTarget{ id: 'pane', on_event: first_callback })
		first.scroll_to_offset('pane', 12.25)
		second.register_scroll_view_in_parent(named_scroll_state_id('pane'), '', frame, frame, 500, true, true, false,
			HitTarget{ id: 'pane', on_event: second_callback })
		second.scroll_to_offset('pane', 42.5)
		first.scroll_to_offset('pane', 60.75)
		assert first_events.len == 2
		assert second_events.len == 1
		assert first_events.map(it.kind) == [.scroll, .scroll]
		assert first_events.map(it.id) == ['pane', 'pane']
		assert first_events.map(it.value) == [12.25, 60.75]
		assert first_events.all(voidptr(it.window) == voidptr(first))
		assert (*second_events)[0].kind == .scroll
		assert (*second_events)[0].id == 'pane'
		assert (*second_events)[0].value == 42.5
		assert voidptr((*second_events)[0].window) == voidptr(second)
	}
}
