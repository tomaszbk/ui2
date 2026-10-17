// vtest vflags: -d ui2_embedder
// vfmt off
@[has_globals]
module ui2

$if (android || ios || linux || macos || windows) && !ui2_headless ? {
	import gg
	import sokol.sapp

	__global lifecycle_observers int
	__global lifecycle_legacy int
	__global lifecycle_actions int
	__global lifecycle_event = sapp.EventType.unfocused

	fn lifecycle_mount(mut w Window, callback ElementCallback) {
		root := screen(0xffffff, [
			Element{kind: .button, id: 'button', on_event: callback},
			Element{kind: .text_area, id: 'editor', text: 'café ñ'},
		])
		w.update_custom_focus_tree(root)
		w.sync_mounted_focus_controls(root, 'root')
		lifecycle_observers = 0
		lifecycle_legacy = 0
		lifecycle_actions = 0
	}
	fn lifecycle_count(_event ElementEvent) { lifecycle_actions++ }
	fn lifecycle_count_key(mut _ Window, _key string) { lifecycle_legacy++ }
	fn lifecycle_quit_key(event KeyEvent) { mut w := event.window; lifecycle_observers++; w.quit() }
	fn lifecycle_quit_legacy(mut w Window, _key string) { lifecycle_legacy++; w.quit() }
	fn lifecycle_blur_key(event KeyEvent) {
		mut w := event.window
		lifecycle_observers++
		on_event(&gg.Event{typ: .unfocused}, mut w)
	}
	fn lifecycle_blur_action(event ElementEvent) {
		mut w := event.window
		lifecycle_actions++
		w.focus('editor')
		on_event(&gg.Event{typ: lifecycle_event}, mut w)
	}
	fn lifecycle_remove_action(event ElementEvent) {
		mut w := event.window
		lifecycle_actions++
		root := screen(0xffffff, [Element{kind: .text_area, id: 'editor', text: 'café ñ'}])
		w.update_custom_focus_tree(root)
		w.sync_mounted_focus_controls(root, 'root')
		w.focus('editor')
	}
	fn lifecycle_reenter_action(event ElementEvent) {
		mut w := event.window
		lifecycle_actions++
		w.focus('editor')
		on_event(&gg.Event{typ: .key_down, key_code: .n}, mut w)
		on_event(&gg.Event{typ: .char, char_code: `ñ`}, mut w)
	}
	fn lifecycle_discard_action(event ElementEvent) {
		mut w := event.window
		lifecycle_actions++
		on_cleanup(mut w)
	}

	fn test_custom_quit_observer_aborts_legacy_activation_and_editor_fallback() {
		for typed in [true, false] {
			for key in [gg.KeyCode.space, .backspace] {
				mut w := &Window{}
				lifecycle_mount(mut w, lifecycle_count)
				w.focus(if key == .space { 'button' } else { 'editor' })
				w.on_key(if typed { lifecycle_count_key } else { lifecycle_quit_legacy })
				if typed { w.on_key_event(lifecycle_quit_key) }
				on_event(&gg.Event{typ: .key_down, key_code: key}, mut w)
				assert w.scheduler.is_closed()
				assert lifecycle_observers == if typed { 1 } else { 0 }
				assert lifecycle_legacy == if typed { 0 } else { 1 }
				assert lifecycle_actions == 0
				assert w.text('editor') == 'café ñ'
				assert !w.keyboard.space && w.keyboard.pending == .invalid
			}
		}
	}

	fn test_custom_blur_observer_preserves_editor_draft_selection_and_composition() {
		mut w := &Window{}
		lifecycle_mount(mut w, lifecycle_count)
		w.focus('editor')
		w.set_text('editor', 'borrador ñ')
		mut editor := w.text_editors['editor'] or { panic('missing editor') }
		editor.selection = TextSelection{anchor: 2, caret: 5}
		w.replace_text_editor('editor', editor)
		w.composition.update('editor', editor, 'é', 1, 0, -1, 0)
		composition := w.composition
		w.on_key_event(lifecycle_blur_key)
		w.on_key(lifecycle_count_key)
		on_event(&gg.Event{typ: .key_down, key_code: .backspace}, mut w)
		assert lifecycle_observers == 1 && lifecycle_legacy == 0
		assert !w.scheduler.is_closed()
		assert w.text_editors['editor'] or { TextEditor{} } == editor
		assert w.composition == composition && w.focused_id() == 'editor'
		w.on_key_event(unsafe { nil })
		w.on_key(unsafe { nil })
		on_event(&gg.Event{typ: .focused}, mut w)
		on_event(&gg.Event{typ: .key_down, key_code: .backspace}, mut w)
		assert w.text('editor') == 'bo' + 'dor ñ'
	}

	fn test_custom_action_lifecycle_reset_does_not_relatch_after_callback() {
		for event in [sapp.EventType.unfocused, .suspended, .iconified] {
			mut w := &Window{}
			lifecycle_event = event
			lifecycle_mount(mut w, lifecycle_blur_action)
			w.focus('button')
			on_event(&gg.Event{typ: .key_down, key_code: .space}, mut w)
			assert lifecycle_actions == 1 && w.focused_id() == 'editor'
			assert !w.scheduler.is_closed()
			assert !w.keyboard.space && w.keyboard.pending == .invalid
			on_event(&gg.Event{typ: .focused}, mut w)
			on_event(&gg.Event{typ: .resumed}, mut w)
			on_event(&gg.Event{typ: .restored}, mut w)
			on_event(&gg.Event{typ: .key_down, key_code: .space, key_repeat: true}, mut w)
			on_event(&gg.Event{typ: .char, char_code: ` `}, mut w)
			assert w.text('editor') == 'café ñ '
			assert lifecycle_actions == 1
		}
	}

	fn test_custom_removal_keeps_physical_repeat_owned_without_repeating_action() {
		mut w := &Window{}
		lifecycle_mount(mut w, lifecycle_remove_action)
		w.focus('button')
		on_event(&gg.Event{typ: .key_down, key_code: .space}, mut w)
		on_event(&gg.Event{typ: .char, char_code: ` `}, mut w)
		on_event(&gg.Event{typ: .key_down, key_code: .space, key_repeat: true}, mut w)
		on_event(&gg.Event{typ: .char, char_code: ` `}, mut w)
		assert w.text('editor') == 'café ñ' && lifecycle_actions == 1
		on_event(&gg.Event{typ: .key_up, key_code: .space}, mut w)
		on_event(&gg.Event{typ: .char, char_code: `é`}, mut w)
		assert w.text('editor') == 'café ñé'
	}

	fn test_custom_reentrant_input_keeps_new_character_provenance_and_owned_repeat() {
		mut w := &Window{}
		lifecycle_mount(mut w, lifecycle_reenter_action)
		w.focus('button')
		on_event(&gg.Event{typ: .key_down, key_code: .space}, mut w)
		assert w.text('editor') == 'café ññ' && lifecycle_actions == 1
		// Nested input consumed its own association. The invalid outer key must
		// not install a new pending CHAR over it, while physical repeats stay owned.
		on_event(&gg.Event{typ: .char, char_code: ` `}, mut w)
		assert w.text('editor') == 'café ññ '
		on_event(&gg.Event{typ: .key_down, key_code: .space, key_repeat: true}, mut w)
		on_event(&gg.Event{typ: .char, char_code: ` `}, mut w)
		assert w.text('editor') == 'café ññ ' && lifecycle_actions == 1
	}

	fn test_custom_discard_inside_activation_never_rearms_disposed_window() {
		mut w := &Window{}
		lifecycle_mount(mut w, lifecycle_discard_action)
		w.focus('button')
		on_event(&gg.Event{typ: .key_down, key_code: .space}, mut w)
		assert lifecycle_actions == 1
		assert w.focused_id() == '' && w.navigation.nodes.len == 0
		assert !w.keyboard.space && w.keyboard.pending == .invalid
	}

	fn lifecycle_replace_scheduler_key(event KeyEvent) {
		mut w := event.window
		lifecycle_observers++
		w.scheduler = new_frame_coordinator()
	}
	fn lifecycle_close_action(event ElementEvent) { mut w := event.window; lifecycle_actions++; w.quit() }
	fn lifecycle_cleanup_action(event ElementEvent) { mut w := event.window; lifecycle_actions++; on_cleanup(mut w) }

	fn test_custom_scheduler_replacement_never_delivers_outer_key_to_new_scheduler() {
		mut w := &Window{}
		lifecycle_mount(mut w, lifecycle_count)
		w.focus('button')
		w.on_key_event(lifecycle_replace_scheduler_key)
		w.on_key(lifecycle_count_key)
		on_event(&gg.Event{typ: .key_down, key_code: .space}, mut w)
		assert lifecycle_observers == 1 && lifecycle_legacy == 0 && lifecycle_actions == 0
		assert !w.keyboard.space && w.keyboard.pending == .invalid
	}

	fn test_custom_action_quit_or_cleanup_leaves_no_physical_ownership() {
		for cleanup in [true, false] {
			mut w := &Window{}
			lifecycle_mount(mut w, if cleanup { lifecycle_cleanup_action } else { lifecycle_close_action })
			w.focus('button')
			on_event(&gg.Event{typ: .key_down, key_code: .enter}, mut w)
			assert lifecycle_actions == 1 && w.scheduler.is_closed()
			assert !w.keyboard.enter && w.keyboard.pending == .invalid
		}
	}

	fn test_custom_menu_and_dropdown_callbacks_abort_before_relatch_or_observers() {
		for menu in [true, false] {
			mut w := &Window{ctx: &DrawContext{width: 320, height: 240}}
			lifecycle_mount(mut w, lifecycle_count)
			lifecycle_event = .unfocused
			w.on_key(lifecycle_count_key)
			if menu {
				w.set_menu_bar([Menu{title: 'Edit', items: [MenuItem{id: 'item', title: 'Edit', shortcut: 'cmd+n', on_select: lifecycle_blur_action}]}])
				on_event(&gg.Event{typ: .key_down, key_code: .n, modifiers: u32(gg.Modifier.super)}, mut w)
			} else {
				control := Element{kind: .dropdown, id: 'choice', text: 'A', on_event: lifecycle_blur_action,
					menu: [MenuEntry{title: 'A'}, MenuEntry{title: 'B'}], frame: rect(0, 0, 120, 30)}
				root := screen(0xffffff, [control, Element{kind: .text_area, id: 'editor', text: 'café ñ'}])
				w.update_custom_focus_tree(root)
				w.sync_mounted_focus_controls(root, 'root')
				w.focus('choice')
				on_event(&gg.Event{typ: .key_down, key_code: .enter}, mut w)
				w.track_dropdown_popup(control, 0, 0, ['A', 'B'], 'A')
				on_event(&gg.Event{typ: .key_up, key_code: .enter}, mut w)
				lifecycle_legacy = 0
				on_event(&gg.Event{typ: .key_down, key_code: .enter}, mut w)
			}
			assert lifecycle_actions == 1 && lifecycle_legacy == 0
			assert !w.keyboard.enter && w.keyboard.pending == .invalid
		}
	}
}

$if macos && ui2_embedder ? && !ui2_headless ? {
	__global lifecycle_reveal_mode int
	__global lifecycle_reveal_posted bool
	__global lifecycle_reveal_calls = []string{}

	fn lifecycle_reveal_scroll(event ElementEvent) {
		mut w := event.window
		lifecycle_reveal_calls << event.id
		if event.id != 'inner' { return }
		match lifecycle_reveal_mode {
			0 { w.quit() }
			1 { on_event(&gg.Event{typ: .unfocused}, mut w) }
			else { on_event(&gg.Event{typ: .key_down, key_code: .n}, mut w) }
		}
	}

	fn lifecycle_reveal_root(mut w Window) Element {
		if !lifecycle_reveal_posted {
			lifecycle_reveal_posted = true
			assert w.dispatcher().post(fn [mut w] () {
				defer { w.quit() }
				w.focus('origin')
				on_event(&gg.Event{typ: .key_down, key_code: .tab}, mut w)
				assert lifecycle_reveal_calls == ['inner'], 'invalid reveal must not invoke outer scroll callback'
				assert w.scroll_offset('outer') == 0
				assert w.keyboard.pending == .invalid
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
		for mode in 0 .. 3 {
			lifecycle_reveal_mode = mode
			lifecycle_reveal_posted = false
			lifecycle_reveal_calls = []string{}
			mut app := new_app()
			mut w := app.new_window(title: 'Nested keyboard focus reveal', width: 240, height: 180, build: lifecycle_reveal_root) or { panic(err) }
			defer { w.quit() }
			app.run()
		}
	}

	fn lifecycle_embedder_blur(event ElementEvent) {
		mut w := event.window
		lifecycle_actions++
		w.focus('editor')
		embedder_event(w, &C.ui2_embedder_event{kind: 12})
	}
	fn lifecycle_embedder_quit(event KeyEvent) { mut w := event.window; lifecycle_observers++; w.quit() }

	fn test_embedder_skip_dispatch_field_change_close_claims_key_without_redispatch() {
		mut w := &Window{}
		root := screen(0xffffff, [Element{kind: .text_area, id: 'editor', text: 'seed', on_event: lifecycle_close_action}])
		w.update_custom_focus_tree(root)
		w.sync_mounted_focus_controls(root, 'root')
		lifecycle_actions = 0
		lifecycle_legacy = 0
		w.focus('editor')
		w.on_key(lifecycle_count_key)
		assert embedder_event(w, &C.ui2_embedder_event{kind: 7, key_code: int(KeyCode.backspace), skip_dispatch: true})
		assert w.text('editor') == 'see' && lifecycle_actions == 1
		assert lifecycle_legacy == 0 && w.scheduler.is_closed()
		assert w.keyboard.pending == .invalid
	}

	fn test_embedder_observer_quit_returns_consumed_without_legacy_or_default() {
		mut w := &Window{}
		lifecycle_mount(mut w, lifecycle_count)
		w.focus('button')
		w.on_key_event(lifecycle_embedder_quit)
		w.on_key(lifecycle_count_key)
		assert embedder_event(w, &C.ui2_embedder_event{kind: 7, key_code: int(KeyCode.space)})
		assert w.scheduler.is_closed()
		assert lifecycle_observers == 1 && lifecycle_legacy == 0 && lifecycle_actions == 0
		assert !w.keyboard.space && w.keyboard.pending == .invalid
	}

	fn test_embedder_blur_inside_action_and_skip_dispatch_edit_preserve_new_context() {
		mut w := &Window{}
		lifecycle_mount(mut w, lifecycle_embedder_blur)
		w.focus('button')
		assert embedder_event(w, &C.ui2_embedder_event{kind: 7, key_code: int(KeyCode.space)})
		assert lifecycle_actions == 1 && w.focused_id() == 'editor'
		assert !w.keyboard.space && w.keyboard.pending == .invalid
		assert !embedder_event(w, &C.ui2_embedder_event{kind: 11})
		assert !embedder_event(w, &C.ui2_embedder_event{kind: 7, key_code: int(KeyCode.space), repeat: true, text_input: true})
		embedder_text(w, &C.ui2_embedder_text_event{kind: 1, text: ' '.str, replacement_start: -1})
		assert w.text('editor') == 'café ñ '
		w.on_key(lifecycle_count_key)
		assert !embedder_event(w, &C.ui2_embedder_event{kind: 7, key_code: int(KeyCode.left), text_input: true})
		assert !embedder_event(w, &C.ui2_embedder_event{kind: 7, key_code: int(KeyCode.left), skip_dispatch: true})
		assert lifecycle_legacy == 1
		assert (w.text_editors['editor'] or { panic('missing editor') }).selection.caret == 6
	}
}
