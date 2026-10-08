@[has_globals]
module ui2

$if ( android || linux || ( ( macos || windows ) && ui2_custom_rendering ?) ) && !ui2_headless ? {
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

	fn window_state_mount_editor(on_event ElementCallback) {
		g_active_fields['editor'] = true
		g_text_kinds['editor'] = .text_area
		g_hit_targets = [HitTarget{ id: 'editor', on_event: on_event, text_area: true }]
		register_scroll_view(named_scroll_state_id('pane'), rect(0, 0, 100, 80), rect(0, 0, 100, 80), 500,
			true, true, false, HitTarget{})
	}
}

fn test_custom_windows_same_ids_keep_independent_edits_focus_scroll_and_menus() {
	$if ( android || linux || ( ( macos || windows ) && ui2_custom_rendering ?) ) && !ui2_headless ? {
		previous_app := g_gg_app
		previous_events := window_state_events.clone()
		first := new_custom_window_state()
		second := new_custom_window_state()
		previous := activate_custom_window_state(first)
		defer {
			activate_custom_window_state(first)
			forget_text_state('editor')
			activate_custom_window_state(second)
			forget_text_state('editor')
			activate_custom_window_state(previous)
			g_gg_app = previous_app
			window_state_events = previous_events.clone()
		}
		first_app := &GgApp{ scheduler: new_frame_coordinator() }
		second_app := &GgApp{ scheduler: new_frame_coordinator() }
		g_gg_app = first_app
		window_state_events = []WindowStateEvent{}
		publish_menu_context('First', unsafe { nil })
		set_menu_bar([Menu{ title: 'First menu', items: [MenuItem{ ...menu_item('command', 'First command'), on_select: first_window_state_event }] }])
		window_state_mount_editor(first_window_state_event)
		set_text('editor', 'first draft')
		focus('editor')
		text_area_set_selection('editor', 0, 5)
		clear := first_app.scheduler.begin_frame(0) or { panic('first window did not mount') }
		first_app.scheduler.finish_frame(clear)
		scroll_to_offset('pane', 70)
		handle_char_input(u32(`A`))
		assert text('editor') == 'A draft'
		assert text_area_caret('editor') == 1
		assert text_area_selection_length('editor') == 0
		assert window_state_events == [WindowStateEvent{ window: 'first', event: ElementEvent{ kind: .change, id: 'editor', text: 'A draft' } }]

		activate_custom_window_state(second)
		g_gg_app = second_app
		assert text('editor') == ''
		assert focused_id() == ''
		assert scroll_offset('pane') == 0
		assert menu_bar().len == 0
		publish_menu_context('Second', unsafe { nil })
		set_menu_bar([Menu{ title: 'Second menu', items: [MenuItem{ ...menu_item('command', 'Second command'), on_select: second_window_state_event }] }])
		window_state_mount_editor(second_window_state_event)
		set_text('editor', 'second draft')
		focus('editor')
		text_area_set_selection('editor', 7, 5)
		scroll_to_offset('pane', 180)
		handle_char_input(u32(`B`))
		assert text('editor') == 'second B'
		assert text_area_caret('editor') == 8
		emit_menu_callback(menu_bar()[0].items[0].on_select, 'command')

		activate_custom_window_state(first)
		g_gg_app = first_app
		assert text('editor') == 'A draft'
		assert focused_id() == 'editor'
		assert text_area_caret('editor') == 1
		assert scroll_offset('pane') == 70
		assert menu_app_name() == 'First'
		assert menu_bar()[0].title == 'First menu'
		emit_menu_callback(menu_bar()[0].items[0].on_select, 'command')
		dismiss_keyboard()
		assert focused_id() == ''

		activate_custom_window_state(second)
		g_gg_app = second_app
		assert text('editor') == 'second B'
		assert focused_id() == 'editor'
		assert text_area_caret('editor') == 8
		assert scroll_offset('pane') == 180
		assert menu_app_name() == 'Second'
		assert menu_bar()[0].title == 'Second menu'
		assert window_state_events == [
			WindowStateEvent{ window: 'first', event: ElementEvent{ kind: .change, id: 'editor', text: 'A draft' } },
			WindowStateEvent{ window: 'second', event: ElementEvent{ kind: .change, id: 'editor', text: 'second B' } },
			WindowStateEvent{ window: 'second', event: ElementEvent{ kind: .tap, id: 'command' } },
			WindowStateEvent{ window: 'first', event: ElementEvent{ kind: .tap, id: 'command' } },
		]
	}
}

fn test_custom_window_activation_is_reentrant_and_restores_pending_scroll_requests() {
	$if ( android || linux || ( ( macos || windows ) && ui2_custom_rendering ?) ) && !ui2_headless ? {
		previous_app := g_gg_app
		first := new_custom_window_state()
		second := new_custom_window_state()
		previous := activate_custom_window_state(first)
		defer {
			activate_custom_window_state(previous)
			g_gg_app = previous_app
		}
		g_gg_app = &GgApp{ scheduler: new_frame_coordinator() }
		g_focused_field = 'outer focus'
		scroll_to_offset('later', 90)
		outer := activate_custom_window_state(second)
		assert g_pending_scroll.len == 0
		g_focused_field = 'inner focus'
		inner := activate_custom_window_state(second)
		assert inner == second
		assert focused_id() == 'inner focus'
		g_focused_field = 'nested focus'
		activate_custom_window_state(inner)
		assert focused_id() == 'nested focus'
		activate_custom_window_state(outer)
		assert focused_id() == 'outer focus'
		assert g_pending_scroll[named_scroll_state_id('later')] == 90
		activate_custom_window_state(second)
		assert focused_id() == 'nested focus'
		assert g_pending_scroll.len == 0
	}
}

fn test_custom_windows_isolate_animation_runs_and_visual_deadlines() {
	$if ( android || linux || ( ( macos || windows ) && ui2_custom_rendering ?) ) && !ui2_headless ? {
		previous_app := g_gg_app
		first := new_custom_window_state()
		second := new_custom_window_state()
		previous := activate_custom_window_state(first)
		defer {
			activate_custom_window_state(previous)
			g_gg_app = previous_app
		}
		first_app := &GgApp{ scheduler: new_frame_coordinator() }
		second_app := &GgApp{ scheduler: new_frame_coordinator() }
		g_gg_app = first_app
		root := screen(0xffffff, [view('same', rect(0, 0, 20, 20), BoxStyle{}, [])])
		start_widget_animation_at('same', animation(AnimationConfig{ duration: 1, x: 100 }),
			1_000, false)
		animated := apply_custom_widget_animations_at(root, 1_500)
		assert animated.children[0].frame.x == 50
		g_tooltip = TooltipState{ pointer_in: true, key: 'help', rest_since: 1_000 }
		first_app.scheduler.set_deadline(custom_visual_deadline())
		assert first_app.scheduler.stats().next_deadline == 1_500

		activate_custom_window_state(second)
		g_gg_app = second_app
		assert !has_animated_properties('same')
		assert custom_visual_deadline() == -1
		start_widget_animation_at('same', animation(AnimationConfig{ duration: 2, x: 400 }),
			1_000, false)
		other_animated := apply_custom_widget_animations_at(root, 1_500)
		assert other_animated.children[0].frame.x == 100
		second_app.scheduler.set_deadline(custom_visual_deadline())
		assert second_app.scheduler.stats().next_deadline == -1

		activate_custom_window_state(first)
		g_gg_app = first_app
		assert animation_info('same').progress == 0.5
		assert custom_visual_deadline() == 1_500
		first_app.scheduler.close()
		discard_custom_window_state(first)
		assert !has_animated_properties('same')
		assert custom_visual_deadline() == -1

		activate_custom_window_state(second)
		g_gg_app = second_app
		assert animation_info('same').progress == 0.25
		assert !second_app.scheduler.is_closed()
		assert second_app.scheduler.stats().next_deadline == -1
		assert custom_animations_need_frame(root)
	}
}

fn test_custom_windows_keep_scroll_callback_declarations_independent() {
	$if ( android || linux || ( ( macos || windows ) && ui2_custom_rendering ?) ) && !ui2_headless ? {
		first := new_custom_window_state()
		second := new_custom_window_state()
		previous := activate_custom_window_state(first)
		defer { activate_custom_window_state(previous) }
		mut first_events := &[]ElementEvent{}
		mut second_events := &[]ElementEvent{}
		first_callback := fn [mut first_events] (event ElementEvent) { first_events << event }
		second_callback := fn [mut second_events] (event ElementEvent) { second_events << event }
		frame := rect(0, 0, 100, 100)
		register_scroll_view(named_scroll_state_id('pane'), frame, frame, 500, true, true, false,
			HitTarget{ id: 'pane', on_event: first_callback })
		scroll_to_offset('pane', 12.25)
		activate_custom_window_state(second)
		register_scroll_view(named_scroll_state_id('pane'), frame, frame, 500, true, true, false,
			HitTarget{ id: 'pane', on_event: second_callback })
		scroll_to_offset('pane', 42.5)
		activate_custom_window_state(first)
		scroll_to_offset('pane', 60.75)
		assert first_events.len == 2
		assert second_events.len == 1
		assert first_events.map(it.kind) == [.scroll, .scroll]
		assert first_events.map(it.id) == ['pane', 'pane']
		assert first_events.map(it.value) == [12.25, 60.75]
		assert (*second_events)[0].kind == .scroll
		assert (*second_events)[0].id == 'pane'
		assert (*second_events)[0].value == 42.5
	}
}
