// vtest vflags: -d ui2_embedder
// vfmt off
@[has_globals]
module ui2

$if macos && ui2_embedder ? && !ui2_headless ? {
	import gg
	import macos

	__global pointer_focus_mode int
	__global pointer_focus_embedder bool
	__global pointer_focus_posted bool
	__global pointer_focus_calls = []string{}
	__global pointer_focus_scrolls int
	__global pointer_menu_observers int
	__global pointer_menu_legacy int

	fn pointer_focus_action(event ElementEvent) {
		pointer_focus_calls << '${event.id}:${event.kind}'
	}

	fn pointer_focus_scroll(event ElementEvent) {
		mut w := event.window
		pointer_focus_scrolls++
		match pointer_focus_mode {
			0 { w.quit() }
			1 { on_event(&gg.Event{typ: .unfocused}, mut w) }
			2 { on_event(&gg.Event{typ: .key_down, key_code: .n}, mut w) }
			else {
				// A nested pointer owns its own capture. Aborting the outer
				// start must not cancel or overwrite this newer gesture.
				on_event(&gg.Event{typ: .mouse_down, mouse_x: 180, mouse_y: 10}, mut w)
			}
		}
	}

	fn pointer_focus_root(mut w Window) Element {
		if !pointer_focus_posted {
			pointer_focus_posted = true
			assert w.dispatcher().post(fn [mut w] () {
				defer { w.quit() }
				// The view is clipped to a ten-pixel strip; real painting
				// registers that hit target and its full focus geometry.
				if pointer_focus_embedder {
					embedder_event(w, &C.ui2_embedder_event{kind: 1, x: 10, y: 95})
				} else {
					on_event(&gg.Event{typ: .mouse_down, mouse_x: 10, mouse_y: 95}, mut w)
				}
				assert pointer_focus_scrolls == 1
				if pointer_focus_mode == 3 {
					assert pointer_focus_calls == ['fresh:pointer_down']
					assert w.touch.down && w.touch.pointer_captured && w.touch.pointer_target.id == 'fresh'
					on_event(&gg.Event{typ: .mouse_up, mouse_x: 180, mouse_y: 10}, mut w)
					assert pointer_focus_calls == ['fresh:pointer_down', 'fresh:pointer_up']
				} else {
					assert pointer_focus_calls.len == 0, 'invalid focus must not dispatch the old pointer action'
					assert !w.touch.down && !w.touch.pointer_captured && w.touch.pressed_id.len == 0
					// Context restore must not leave a fallback gesture that
					// could fire an unmatched pointer_up/tap on release.
					on_event(&gg.Event{typ: .mouse_up, mouse_x: 10, mouse_y: 95}, mut w)
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
		for embedder in [false, true] {
			pointer_focus_embedder = embedder
			for mode in 0 .. 4 {
				pointer_focus_mode = mode
				pointer_focus_posted = false
				pointer_focus_calls = []string{}
				pointer_focus_scrolls = 0
				mut app := new_app()
				mut w := app.new_window(title: 'Pointer focus lifecycle', width: 240, height: 180, build: pointer_focus_root) or { panic(err) }
				defer { w.quit() }
				app.run()
			}
		}
	}

	fn pointer_focus_editor_root(mut w Window) Element {
		if !pointer_focus_posted {
			pointer_focus_posted = true
			assert w.dispatcher().post(fn [mut w] () {
				defer { w.quit() }
				embedder_event(w, &C.ui2_embedder_event{kind: 1, x: 10, y: 10})
				assert w.focused_id() == 'editor'
				view := macos.msg_id(w.native_handle(), 'contentView')
				assert macos.msg_bool(view, 'textEnabled')
				assert macos.utf8_string(macos.msg_id(view, 'textSnapshot')) == 'café ñ'
			})
		}
		return screen(0xffffff, [Element{kind: .text_field, id: 'editor', text: 'café ñ', frame: rect(0, 0, 120, 30)}])
	}

	fn test_embedder_mouse_focus_synchronizes_native_editor_snapshot() {
		pointer_focus_posted = false
		mut app := new_app()
		mut w := app.new_window(title: 'Pointer editor target', width: 240, height: 180, build: pointer_focus_editor_root) or { panic(err) }
		defer { w.quit() }
		app.run()
	}

	fn pointer_menu_observer(event KeyEvent) {
		mut w := event.window
		pointer_menu_observers++
		titles := w.menu_hits.filter(it.is_title)
		assert titles.len > 0
		title := titles[0]
		x := title.x + title.w / 2
		y := title.y + title.h / 2
		if pointer_focus_embedder {
			embedder_event(w, &C.ui2_embedder_event{kind: 1, x: f32(x), y: f32(y)})
		} else {
			on_event(&gg.Event{typ: .mouse_down, mouse_x: f32(x), mouse_y: f32(y)}, mut w)
		}
		assert w.menu_bar_open()
	}

	fn pointer_menu_key(mut _ Window, _key string) { pointer_menu_legacy++ }

	fn pointer_menu_root(mut w Window) Element {
		if !pointer_focus_posted {
			pointer_focus_posted = true
			assert w.dispatcher().post(fn [mut w] () {
				defer { w.quit() }
				w.focus('button')
				assert !w.menu_bar_open()
				w.on_key_event(pointer_menu_observer)
				w.on_key(pointer_menu_key)
				// The typed observer synchronously opens a painted menu through
				// another mouse-down route. That input owns its new context, so
				// the outer Space must stop before KeyFn or button activation.
				assert embedder_event(w, &C.ui2_embedder_event{kind: 7, key_code: int(gg.KeyCode.space)})
				assert pointer_menu_observers == 1
				assert pointer_menu_legacy == 0, 'nested menu input: KeyFn=${pointer_menu_legacy}, actions=${pointer_focus_calls}'
				assert pointer_focus_calls.len == 0
				assert w.menu_bar_open()
				assert !w.keyboard.space && w.keyboard.pending == .invalid
				assert !w.touch.down && !w.touch.pointer_captured
			})
		}
		return screen(0xffffff, [Element{kind: .button, id: 'button', text: 'Activate', on_event: pointer_focus_action, frame: rect(20, 40, 120, 36)}])
	}

	fn test_menu_consumed_mouse_reentry_aborts_outer_key_in_both_routes() {
		for embedder in [false, true] {
			pointer_focus_embedder = embedder
			pointer_focus_posted = false
			pointer_focus_calls = []string{}
			pointer_menu_observers = 0
			pointer_menu_legacy = 0
			mut app := new_app()
			mut w := app.new_window(title: 'Menu input reentry', width: 240, height: 180, build: pointer_menu_root) or { panic(err) }
			defer { w.quit() }
			w.set_menu_bar([Menu{title: 'Edit', items: [MenuItem{id: 'item', title: 'Action', on_select: pointer_focus_action}]}])
			app.run()
		}
	}
}
