// vtest vflags: -d ui2_custom_rendering -d ui2_embedder
// vfmt off
@[has_globals]
module ui2

$if (android || linux || ((macos || windows) && ui2_custom_rendering ?)) && !ui2_headless ? {
	import gg
	import sokol.sapp

	__global lifecycle_observers int
	__global lifecycle_legacy int
	__global lifecycle_actions int
	__global lifecycle_event = sapp.EventType.unfocused
	__global lifecycle_other = &CustomWindowState(unsafe { nil })

	fn lifecycle_mount(callback ElementCallback) {
		root := screen(0xffffff, [
			Element{kind: .button, id: 'button', on_event: callback},
			Element{kind: .text_area, id: 'editor', text: 'café ñ'},
		])
		update_custom_focus_tree(root)
		sync_mounted_focus_controls(root, 'root')
		lifecycle_observers = 0
		lifecycle_legacy = 0
		lifecycle_actions = 0
	}
	fn lifecycle_count(_event ElementEvent) { lifecycle_actions++ }
	fn lifecycle_count_key(_key string) { lifecycle_legacy++ }
	fn lifecycle_quit_key(_event KeyEvent) { lifecycle_observers++; quit() }
	fn lifecycle_quit_legacy(_key string) { lifecycle_legacy++; quit() }
	fn lifecycle_blur_key(_event KeyEvent) {
		lifecycle_observers++
		on_event(&gg.Event{typ: .unfocused}, g_gg_app)
	}
	fn lifecycle_blur_action(_event ElementEvent) {
		lifecycle_actions++
		focus('editor')
		on_event(&gg.Event{typ: lifecycle_event}, g_gg_app)
	}
	fn lifecycle_switch_key(_event KeyEvent) {
		lifecycle_observers++
		previous := activate_custom_window_state(lifecycle_other)
		activate_custom_window_state(previous)
	}
	fn lifecycle_remove_action(_event ElementEvent) {
		lifecycle_actions++
		root := screen(0xffffff, [Element{kind: .text_area, id: 'editor', text: 'café ñ'}])
		update_custom_focus_tree(root)
		sync_mounted_focus_controls(root, 'root')
		focus('editor')
	}
	fn lifecycle_reenter_action(_event ElementEvent) {
		lifecycle_actions++
		focus('editor')
		on_event(&gg.Event{typ: .key_down, key_code: .n}, g_gg_app)
		on_event(&gg.Event{typ: .char, char_code: `ñ`}, g_gg_app)
	}
	fn lifecycle_discard_action(_event ElementEvent) {
		lifecycle_actions++
		discard_custom_window_state(g_active_custom_window_state)
	}

	fn test_custom_quit_observer_aborts_legacy_activation_and_editor_fallback() {
		previous_app := g_gg_app
		previous := activate_custom_window_state(new_custom_window_state())
		defer { activate_custom_window_state(previous); g_gg_app = previous_app }
		for typed in [true, false] {
			for key in [gg.KeyCode.space, .backspace] {
				activate_custom_window_state(new_custom_window_state())
				mut app := &GgApp{}
				g_gg_app = app
				lifecycle_mount(lifecycle_count)
				focus(if key == .space { 'button' } else { 'editor' })
				on_key(if typed { lifecycle_count_key } else { lifecycle_quit_legacy })
				if typed { on_key_event(lifecycle_quit_key) }
				on_event(&gg.Event{typ: .key_down, key_code: key}, app)
				assert app.scheduler.is_closed()
				assert lifecycle_observers == if typed { 1 } else { 0 }
				assert lifecycle_legacy == if typed { 0 } else { 1 }
				assert lifecycle_actions == 0
				assert text('editor') == 'café ñ'
				assert !g_custom_keyboard.space && g_custom_keyboard.pending == .invalid
			}
		}
	}

	fn test_custom_blur_observer_preserves_editor_draft_selection_and_composition() {
		previous_app := g_gg_app
		previous := activate_custom_window_state(new_custom_window_state())
		defer { activate_custom_window_state(previous); g_gg_app = previous_app }
		mut app := &GgApp{}
		g_gg_app = app
		lifecycle_mount(lifecycle_count)
		focus('editor')
		set_text('editor', 'borrador ñ')
		mut editor := g_text_editors['editor'] or { panic('missing editor') }
		editor.selection = TextSelection{anchor: 2, caret: 5}
		replace_text_editor('editor', editor)
		app.composition.update('editor', editor, 'é', 1, 0, -1, 0)
		composition := app.composition
		on_key_event(lifecycle_blur_key)
		on_key(lifecycle_count_key)
		on_event(&gg.Event{typ: .key_down, key_code: .backspace}, app)
		assert lifecycle_observers == 1 && lifecycle_legacy == 0
		assert !app.scheduler.is_closed()
		assert g_text_editors['editor'] or { TextEditor{} } == editor
		assert app.composition == composition && focused_id() == 'editor'
		on_key_event(unsafe { nil })
		on_key(unsafe { nil })
		on_event(&gg.Event{typ: .focused}, app)
		on_event(&gg.Event{typ: .key_down, key_code: .backspace}, app)
		assert text('editor') == 'bo' + 'dor ñ'
	}

	fn test_custom_action_lifecycle_reset_does_not_relatch_after_callback() {
		previous_app := g_gg_app
		previous := activate_custom_window_state(new_custom_window_state())
		defer { activate_custom_window_state(previous); g_gg_app = previous_app }
		for event in [sapp.EventType.unfocused, .suspended, .iconified] {
			activate_custom_window_state(new_custom_window_state())
			mut app := &GgApp{}
			g_gg_app = app
			lifecycle_event = event
			lifecycle_mount(lifecycle_blur_action)
			focus('button')
			on_event(&gg.Event{typ: .key_down, key_code: .space}, app)
			assert lifecycle_actions == 1 && focused_id() == 'editor'
			assert !app.scheduler.is_closed()
			assert !g_custom_keyboard.space && g_custom_keyboard.pending == .invalid
			on_event(&gg.Event{typ: .focused}, app)
			on_event(&gg.Event{typ: .resumed}, app)
			on_event(&gg.Event{typ: .restored}, app)
			on_event(&gg.Event{typ: .key_down, key_code: .space, key_repeat: true}, app)
			on_event(&gg.Event{typ: .char, char_code: ` `}, app)
			assert text('editor') == 'café ñ '
			assert lifecycle_actions == 1
		}
	}

	fn test_custom_callback_window_switch_restore_aborts_outer_dispatch() {
		previous_app := g_gg_app
		previous := activate_custom_window_state(new_custom_window_state())
		defer { activate_custom_window_state(previous); g_gg_app = previous_app }
		mut app := &GgApp{}
		g_gg_app = app
		lifecycle_mount(lifecycle_count)
		focus('button')
		lifecycle_other = new_custom_window_state()
		on_key_event(lifecycle_switch_key)
		on_key(lifecycle_count_key)
		on_event(&gg.Event{typ: .key_down, key_code: .space}, app)
		assert lifecycle_observers == 1 && lifecycle_legacy == 0 && lifecycle_actions == 0
		assert !g_custom_keyboard.space && g_custom_keyboard.pending == .invalid
		activate_custom_window_state(lifecycle_other)
		assert !g_custom_keyboard.space && g_custom_keyboard.pending == .invalid
	}

	fn test_custom_removal_keeps_physical_repeat_owned_without_repeating_action() {
		previous_app := g_gg_app
		previous := activate_custom_window_state(new_custom_window_state())
		defer { activate_custom_window_state(previous); g_gg_app = previous_app }
		mut app := &GgApp{}
		g_gg_app = app
		lifecycle_mount(lifecycle_remove_action)
		focus('button')
		on_event(&gg.Event{typ: .key_down, key_code: .space}, app)
		on_event(&gg.Event{typ: .char, char_code: ` `}, app)
		on_event(&gg.Event{typ: .key_down, key_code: .space, key_repeat: true}, app)
		on_event(&gg.Event{typ: .char, char_code: ` `}, app)
		assert text('editor') == 'café ñ' && lifecycle_actions == 1
		on_event(&gg.Event{typ: .key_up, key_code: .space}, app)
		on_event(&gg.Event{typ: .char, char_code: `é`}, app)
		assert text('editor') == 'café ñé'
	}

	fn test_custom_reentrant_input_keeps_new_character_provenance_and_owned_repeat() {
		previous_app := g_gg_app
		previous := activate_custom_window_state(new_custom_window_state())
		defer { activate_custom_window_state(previous); g_gg_app = previous_app }
		mut app := &GgApp{}
		g_gg_app = app
		lifecycle_mount(lifecycle_reenter_action)
		focus('button')
		on_event(&gg.Event{typ: .key_down, key_code: .space}, app)
		assert text('editor') == 'café ññ' && lifecycle_actions == 1
		// Nested input consumed its own association. The invalid outer key must
		// not install a new pending CHAR over it, while physical repeats stay owned.
		on_event(&gg.Event{typ: .char, char_code: ` `}, app)
		assert text('editor') == 'café ññ '
		on_event(&gg.Event{typ: .key_down, key_code: .space, key_repeat: true}, app)
		on_event(&gg.Event{typ: .char, char_code: ` `}, app)
		assert text('editor') == 'café ññ ' && lifecycle_actions == 1
	}

	fn test_custom_discard_inside_activation_never_rearms_disposed_window() {
		previous_app := g_gg_app
		previous := activate_custom_window_state(new_custom_window_state())
		defer { activate_custom_window_state(previous); g_gg_app = previous_app }
		mut app := &GgApp{}
		g_gg_app = app
		lifecycle_mount(lifecycle_discard_action)
		focus('button')
		on_event(&gg.Event{typ: .key_down, key_code: .space}, app)
		assert lifecycle_actions == 1
		assert focused_id() == '' && g_focus_navigation.nodes.len == 0
		assert !g_custom_keyboard.space && g_custom_keyboard.pending == .invalid
	}

	fn lifecycle_replace_app_key(_event KeyEvent) {
		lifecycle_observers++
		g_gg_app = &GgApp{}
	}
	fn lifecycle_replace_scheduler_key(_event KeyEvent) {
		lifecycle_observers++
		g_gg_app.scheduler = new_frame_coordinator()
	}
	fn lifecycle_close_action(_event ElementEvent) { lifecycle_actions++; quit() }
	fn lifecycle_cleanup_action(_event ElementEvent) { lifecycle_actions++; on_cleanup(g_gg_app) }

	fn test_custom_context_replacement_never_delivers_outer_key_to_new_app_or_scheduler() {
		previous_app := g_gg_app
		previous := activate_custom_window_state(new_custom_window_state())
		defer { activate_custom_window_state(previous); g_gg_app = previous_app }
		for replace_app in [true, false] {
			activate_custom_window_state(new_custom_window_state())
			mut app := &GgApp{}
			g_gg_app = app
			lifecycle_mount(lifecycle_count)
			focus('button')
			on_key_event(if replace_app { lifecycle_replace_app_key } else { lifecycle_replace_scheduler_key })
			on_key(lifecycle_count_key)
			on_event(&gg.Event{typ: .key_down, key_code: .space}, app)
			assert lifecycle_observers == 1 && lifecycle_legacy == 0 && lifecycle_actions == 0
			assert !g_custom_keyboard.space && g_custom_keyboard.pending == .invalid
		}
	}

	fn test_custom_action_quit_or_cleanup_leaves_no_physical_ownership() {
		previous_app := g_gg_app
		previous := activate_custom_window_state(new_custom_window_state())
		defer { activate_custom_window_state(previous); g_gg_app = previous_app }
		for cleanup in [true, false] {
			activate_custom_window_state(new_custom_window_state())
			mut app := &GgApp{}
			g_gg_app = app
			lifecycle_mount(if cleanup { lifecycle_cleanup_action } else { lifecycle_close_action })
			focus('button')
			on_event(&gg.Event{typ: .key_down, key_code: .enter}, app)
			assert lifecycle_actions == 1 && app.scheduler.is_closed()
			assert !g_custom_keyboard.enter && g_custom_keyboard.pending == .invalid
		}
	}

	fn test_custom_menu_and_dropdown_callbacks_abort_before_relatch_or_observers() {
		previous_app := g_gg_app
		previous := activate_custom_window_state(new_custom_window_state())
		defer { activate_custom_window_state(previous); g_gg_app = previous_app }
		for menu in [true, false] {
			activate_custom_window_state(new_custom_window_state())
			mut app := &GgApp{ctx: &DrawContext{width: 320, height: 240}}
			g_gg_app = app
			lifecycle_mount(lifecycle_count)
			lifecycle_event = .unfocused
			on_key(lifecycle_count_key)
			if menu {
				set_menu_bar([Menu{title: 'Edit', items: [MenuItem{id: 'item', title: 'Edit', shortcut: 'cmd+n', on_select: lifecycle_blur_action}]}])
				on_event(&gg.Event{typ: .key_down, key_code: .n, modifiers: u32(gg.Modifier.super)}, app)
			} else {
				control := Element{kind: .dropdown, id: 'choice', text: 'A', on_event: lifecycle_blur_action,
					menu: [MenuEntry{title: 'A'}, MenuEntry{title: 'B'}], frame: rect(0, 0, 120, 30)}
				root := screen(0xffffff, [control, Element{kind: .text_area, id: 'editor', text: 'café ñ'}])
				update_custom_focus_tree(root)
				sync_mounted_focus_controls(root, 'root')
				focus('choice')
				on_event(&gg.Event{typ: .key_down, key_code: .enter}, app)
				track_dropdown_popup(control, 0, 0, ['A', 'B'], 'A')
				on_event(&gg.Event{typ: .key_up, key_code: .enter}, app)
				lifecycle_legacy = 0
				on_event(&gg.Event{typ: .key_down, key_code: .enter}, app)
			}
			assert lifecycle_actions == 1 && lifecycle_legacy == 0
			assert !g_custom_keyboard.enter && g_custom_keyboard.pending == .invalid
		}
	}
}

$if macos && ui2_custom_rendering ? && ui2_embedder ? && !ui2_headless ? {
	__global lifecycle_reveal_mode int
	__global lifecycle_reveal_posted bool
	__global lifecycle_reveal_calls = []string{}

	fn lifecycle_reveal_scroll(event ElementEvent) {
		lifecycle_reveal_calls << event.id
		if event.id != 'inner' { return }
		match lifecycle_reveal_mode {
			0 { quit() }
			1 { on_event(&gg.Event{typ: .unfocused}, g_gg_app) }
			2 {
				previous := activate_custom_window_state(new_custom_window_state())
				activate_custom_window_state(previous)
			}
			else { on_event(&gg.Event{typ: .key_down, key_code: .n}, g_gg_app) }
		}
	}

	fn lifecycle_reveal_root() Element {
		if !lifecycle_reveal_posted {
			lifecycle_reveal_posted = true
			assert ui_dispatcher().post(fn () {
				defer { quit() }
				focus('origin')
				on_event(&gg.Event{typ: .key_down, key_code: .tab}, g_gg_app)
				assert lifecycle_reveal_calls == ['inner'], 'invalid reveal must not invoke outer scroll callback'
				assert scroll_offset('outer') == 0
				assert g_custom_keyboard.pending == .invalid
			})
		}
		return screen(0xffffff, [
			Element{kind: .button, id: 'origin', frame: rect(170, 0, 50, 30)},
			Element{kind: .scroll, id: 'outer', frame: rect(0, 0, 160, 100), on_event: lifecycle_reveal_scroll,
				children: [Element{kind: .scroll, id: 'inner', frame: rect(0, 0, 140, 300), on_event: lifecycle_reveal_scroll,
					children: [Element{kind: .button, id: 'below', frame: rect(0, 500, 80, 30)}]}]},
		])
	}

	fn test_embedder_tab_reveal_stops_after_each_nested_scroll_lifecycle_callback() {
		previous_app := g_gg_app
		previous := activate_custom_window_state(new_custom_window_state())
		defer { activate_custom_window_state(previous); g_gg_app = previous_app }
		for mode in 0 .. 4 {
			lifecycle_reveal_mode = mode
			lifecycle_reveal_posted = false
			lifecycle_reveal_calls = []string{}
			window := open_window('Nested keyboard focus reveal', 240, 180, lifecycle_reveal_root) or { panic(err) }
			defer { window.close() }
			run_windows()
		}
	}

	fn lifecycle_embedder_blur(_event ElementEvent) {
		lifecycle_actions++
		focus('editor')
		embedder_event(g_gg_app, &C.ui2_embedder_event{kind: 12})
	}
	fn lifecycle_embedder_quit(_event KeyEvent) { lifecycle_observers++; quit() }

	fn test_embedder_skip_dispatch_field_change_close_claims_key_without_redispatch() {
		previous_app := g_gg_app
		previous := activate_custom_window_state(new_custom_window_state())
		defer { activate_custom_window_state(previous); g_gg_app = previous_app }
		mut app := &GgApp{window_state: new_custom_window_state()}
		activate_custom_window_state(app.window_state)
		g_gg_app = app
		root := screen(0xffffff, [Element{kind: .text_area, id: 'editor', text: 'seed', on_event: lifecycle_close_action}])
		update_custom_focus_tree(root)
		sync_mounted_focus_controls(root, 'root')
		lifecycle_actions = 0
		lifecycle_legacy = 0
		focus('editor')
		on_key(lifecycle_count_key)
		assert embedder_event(app, &C.ui2_embedder_event{kind: 7, key_code: int(KeyCode.backspace), skip_dispatch: true})
		assert text('editor') == 'see' && lifecycle_actions == 1
		assert lifecycle_legacy == 0 && app.scheduler.is_closed()
		assert g_custom_keyboard.pending == .invalid
	}

	fn test_embedder_observer_quit_returns_consumed_without_legacy_or_default() {
		previous_app := g_gg_app
		previous := activate_custom_window_state(new_custom_window_state())
		defer { activate_custom_window_state(previous); g_gg_app = previous_app }
		mut app := &GgApp{window_state: new_custom_window_state()}
		activate_custom_window_state(app.window_state)
		g_gg_app = app
		lifecycle_mount(lifecycle_count)
		focus('button')
		on_key_event(lifecycle_embedder_quit)
		on_key(lifecycle_count_key)
		assert embedder_event(app, &C.ui2_embedder_event{kind: 7, key_code: int(KeyCode.space)})
		assert app.scheduler.is_closed()
		assert lifecycle_observers == 1 && lifecycle_legacy == 0 && lifecycle_actions == 0
		assert !g_custom_keyboard.space && g_custom_keyboard.pending == .invalid
	}

	fn test_embedder_blur_inside_action_and_skip_dispatch_edit_preserve_new_context() {
		previous_app := g_gg_app
		previous := activate_custom_window_state(new_custom_window_state())
		defer { activate_custom_window_state(previous); g_gg_app = previous_app }
		mut app := &GgApp{window_state: new_custom_window_state()}
		activate_custom_window_state(app.window_state)
		g_gg_app = app
		lifecycle_mount(lifecycle_embedder_blur)
		focus('button')
		assert embedder_event(app, &C.ui2_embedder_event{kind: 7, key_code: int(KeyCode.space)})
		assert lifecycle_actions == 1 && focused_id() == 'editor'
		assert !g_custom_keyboard.space && g_custom_keyboard.pending == .invalid
		assert !embedder_event(app, &C.ui2_embedder_event{kind: 11})
		assert !embedder_event(app, &C.ui2_embedder_event{kind: 7, key_code: int(KeyCode.space), repeat: true, text_input: true})
		embedder_text(app, &C.ui2_embedder_text_event{kind: 1, text: ' '.str, replacement_start: -1})
		assert text('editor') == 'café ñ '
		on_key(lifecycle_count_key)
		assert !embedder_event(app, &C.ui2_embedder_event{kind: 7, key_code: int(KeyCode.left), text_input: true})
		assert !embedder_event(app, &C.ui2_embedder_event{kind: 7, key_code: int(KeyCode.left), skip_dispatch: true})
		assert lifecycle_legacy == 1
		assert (g_text_editors['editor'] or { panic('missing editor') }).selection.caret == 6
	}
}
