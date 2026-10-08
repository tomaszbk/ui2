// vtest vflags: -d ui2_custom_rendering -d ui2_embedder
// vfmt off
@[has_globals]
module ui2

$if macos && ui2_custom_rendering ? && ui2_embedder ? && !ui2_headless ? {
	import gg
	import macos

	__global pointer_focus_mode int
	__global pointer_focus_embedder bool
	__global pointer_focus_posted bool
	__global pointer_focus_calls = []string{}
	__global pointer_focus_scrolls int
	__global pointer_focus_window = CustomWindow{}
	__global pointer_menu_observers int
	__global pointer_menu_legacy int

	fn pointer_focus_action(event ElementEvent) {
		pointer_focus_calls << '${event.id}:${event.kind}'
	}

	fn pointer_focus_scroll(_event ElementEvent) {
		pointer_focus_scrolls++
		match pointer_focus_mode {
			0 { quit() }
			1 { on_event(&gg.Event{typ: .unfocused}, g_gg_app) }
			2 {
				previous := activate_custom_window_state(new_custom_window_state())
				activate_custom_window_state(previous)
			}
			3 { on_event(&gg.Event{typ: .key_down, key_code: .n}, g_gg_app) }
			else {
				// A nested pointer owns its own capture. Aborting the outer
				// start must not cancel or overwrite this newer gesture.
				on_event(&gg.Event{typ: .mouse_down, mouse_x: 180, mouse_y: 10}, g_gg_app)
			}
		}
	}

	fn pointer_focus_root() Element {
		if !pointer_focus_posted {
			pointer_focus_posted = true
			assert ui_dispatcher().post(fn () {
				defer { quit() }
				// The view is clipped to a ten-pixel strip; real painting
				// registers that hit target and its full focus geometry.
				if pointer_focus_embedder {
					embedder_event(g_gg_app, &C.ui2_embedder_event{kind: 1, x: 10, y: 95})
				} else {
					on_event(&gg.Event{typ: .mouse_down, mouse_x: 10, mouse_y: 95}, g_gg_app)
				}
				assert pointer_focus_scrolls == 1
				if pointer_focus_mode == 4 {
					assert pointer_focus_calls == ['fresh:pointer_down']
					assert g_touch.down && g_touch.pointer_captured && g_touch.pointer_target.id == 'fresh'
					on_event(&gg.Event{typ: .mouse_up, mouse_x: 180, mouse_y: 10}, g_gg_app)
					assert pointer_focus_calls == ['fresh:pointer_down', 'fresh:pointer_up']
				} else {
					assert pointer_focus_calls.len == 0, 'invalid focus must not dispatch the old pointer action'
					assert !g_touch.down && !g_touch.pointer_captured && g_touch.pressed_id.len == 0
					// Context restore must not leave a fallback gesture that
					// could fire an unmatched pointer_up/tap on release.
					on_event(&gg.Event{typ: .mouse_up, mouse_x: 10, mouse_y: 95}, g_gg_app)
					assert pointer_focus_calls.len == 0
				}
			})
		}
		return screen(0xffffff, [
			Element{kind: .scroll, id: 'pane', frame: rect(0, 0, 120, 100), on_event: pointer_focus_scroll,
				children: [Element{kind: .view, id: 'old', focus_policy: .focusable, clickable: true, draggable: true,
					button_behavior: true, on_event: pointer_focus_action, frame: rect(0, 90, 100, 30)}]},
			Element{kind: .view, id: 'fresh', focus_policy: .focusable, clickable: true, draggable: true,
				on_event: pointer_focus_action, frame: rect(170, 0, 50, 30)},
		])
	}

	fn test_pointer_focus_abort_discards_only_its_own_start_in_both_routes() {
		previous_app := g_gg_app
		previous := activate_custom_window_state(new_custom_window_state())
		defer { activate_custom_window_state(previous); g_gg_app = previous_app }
		for embedder in [false, true] {
			pointer_focus_embedder = embedder
			for mode in 0 .. 5 {
				pointer_focus_mode = mode
				pointer_focus_posted = false
				pointer_focus_calls = []string{}
				pointer_focus_scrolls = 0
				pointer_focus_window = open_window('Pointer focus lifecycle', 240, 180, pointer_focus_root) or { panic(err) }
				defer { pointer_focus_window.close() }
				run_windows()
			}
		}
	}

	fn pointer_focus_editor_root() Element {
		if !pointer_focus_posted {
			pointer_focus_posted = true
			assert ui_dispatcher().post(fn () {
				defer { quit() }
				embedder_event(g_gg_app, &C.ui2_embedder_event{kind: 1, x: 10, y: 10})
				assert focused_id() == 'editor'
				view := macos.msg_id(pointer_focus_window.native_handle(), 'contentView')
				assert macos.msg_bool(view, 'textEnabled')
				assert macos.utf8_string(macos.msg_id(view, 'textSnapshot')) == 'café ñ'
			})
		}
		return screen(0xffffff, [Element{kind: .text_field, id: 'editor', text: 'café ñ', frame: rect(0, 0, 120, 30)}])
	}

	fn test_embedder_mouse_focus_synchronizes_native_editor_snapshot() {
		previous_app := g_gg_app
		previous := activate_custom_window_state(new_custom_window_state())
		defer { activate_custom_window_state(previous); g_gg_app = previous_app }
		pointer_focus_posted = false
		pointer_focus_window = open_window('Pointer editor target', 240, 180, pointer_focus_editor_root) or { panic(err) }
		defer { pointer_focus_window.close() }
		run_windows()
	}

	fn pointer_menu_observer(_event KeyEvent) {
		pointer_menu_observers++
		titles := g_menu_hits.filter(it.is_title)
		assert titles.len > 0
		title := titles[0]
		x := title.x + title.w / 2
		y := title.y + title.h / 2
		if pointer_focus_embedder {
			embedder_event(g_gg_app, &C.ui2_embedder_event{kind: 1, x: f32(x), y: f32(y)})
		} else {
			on_event(&gg.Event{typ: .mouse_down, mouse_x: f32(x), mouse_y: f32(y)}, g_gg_app)
		}
		assert menu_bar_open()
	}

	fn pointer_menu_key(_key string) { pointer_menu_legacy++ }

	fn pointer_menu_root() Element {
		if !pointer_focus_posted {
			pointer_focus_posted = true
			assert ui_dispatcher().post(fn () {
				defer { quit() }
				focus('button')
				assert !menu_bar_open()
				on_key_event(pointer_menu_observer)
				on_key(pointer_menu_key)
				// The typed observer synchronously opens a painted menu through
				// another mouse-down route. That input owns its new context, so
				// the outer Space must stop before KeyFn or button activation.
				assert embedder_event(g_gg_app, &C.ui2_embedder_event{kind: 7, key_code: int(gg.KeyCode.space)})
				assert pointer_menu_observers == 1
				assert pointer_menu_legacy == 0, 'nested menu input: KeyFn=${pointer_menu_legacy}, actions=${pointer_focus_calls}'
				assert pointer_focus_calls.len == 0
				assert menu_bar_open()
				assert !g_custom_keyboard.space && g_custom_keyboard.pending == .invalid
				assert !g_touch.down && !g_touch.pointer_captured
			})
		}
		return screen(0xffffff, [Element{kind: .button, id: 'button', text: 'Activate', on_event: pointer_focus_action, frame: rect(20, 40, 120, 36)}])
	}

	fn test_menu_consumed_mouse_reentry_aborts_outer_key_in_both_routes() {
		previous_app := g_gg_app
		previous := activate_custom_window_state(new_custom_window_state())
		defer { activate_custom_window_state(previous); g_gg_app = previous_app }
		for embedder in [false, true] {
			pointer_focus_embedder = embedder
			pointer_focus_posted = false
			pointer_focus_calls = []string{}
			pointer_menu_observers = 0
			pointer_menu_legacy = 0
			pointer_focus_window = open_window('Menu input reentry', 240, 180, pointer_menu_root) or { panic(err) }
			defer { pointer_focus_window.close() }
			assert pointer_focus_window.update(fn () {
				set_menu_bar([Menu{title: 'Edit', items: [MenuItem{id: 'item', title: 'Action', on_select: pointer_focus_action}]}])
			})
			run_windows()
		}
	}
}
