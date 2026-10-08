// vtest vflags: -d ui2_custom_rendering -d ui2_embedder
// vfmt off
@[has_globals]
module ui2

$if macos && ui2_custom_rendering ? && ui2_embedder ? && !ui2_headless ? {
	__global embedder_focus_taps = []ElementEvent{}
	__global embedder_focus_keys = []KeyEvent{}

	fn embedder_focus_tap(event ElementEvent) {
		embedder_focus_taps << event
		focus('edit')
	}
	fn embedder_focus_key(event KeyEvent) { embedder_focus_keys << event }

	fn mount_embedder_focus_fixture(app &GgApp) {
		previous := activate_custom_window_state(app.window_state)
		previous_app := g_gg_app
		g_gg_app = app
		defer { activate_custom_window_state(previous); g_gg_app = previous_app }
		root := screen(0xffffff, [
			Element{ kind: .text_area, id: 'edit', text: 'seed', frame: rect(0, 40, 180, 60) },
			Element{ kind: .button, id: 'button', on_event: embedder_focus_tap, frame: rect(0, 0, 100, 30) },
			Element{ kind: .button, id: 'right', on_event: embedder_focus_tap, frame: rect(200, 0, 100, 30) },
		])
		update_custom_focus_tree(root)
		sync_mounted_focus_controls(root, 'root')
		g_key_event_handler = embedder_focus_key
		focus('edit')
	}

	fn test_embedder_real_keyboard_route_navigates_and_returns_consumption_to_host() {
		previous_app := g_gg_app
		previous := activate_custom_window_state(new_custom_window_state())
		defer { activate_custom_window_state(previous); g_gg_app = previous_app }
		mut app := &GgApp{ window_state: new_custom_window_state() }
		activate_custom_window_state(app.window_state)
		g_gg_app = app
		mount_embedder_focus_fixture(app)
		embedder_focus_taps = []ElementEvent{}
		embedder_focus_keys = []KeyEvent{}
		assert embedder_event(app, &C.ui2_embedder_event{ kind: 7, key_code: int(KeyCode.tab), text_input: true })
		assert focused_id() == 'button'
		assert embedder_event(app, &C.ui2_embedder_event{ kind: 7, key_code: int(KeyCode.right) })
		assert focused_id() == 'right'
		for key in [KeyCode.space, .enter, .kp_enter] {
			focus('button')
			assert embedder_event(app, &C.ui2_embedder_event{ kind: 7, key_code: int(key) })
			assert focused_id() == 'edit'
			for _ in 0 .. 2 {
				assert embedder_event(app, &C.ui2_embedder_event{ kind: 7, key_code: int(key), repeat: true, text_input: true })
			}
			assert !embedder_event(app, &C.ui2_embedder_event{ kind: 8, key_code: int(key) })
			assert text('edit') == 'seed'
		}
		assert embedder_focus_taps == [ElementEvent{ kind: .tap, id: 'button' }, ElementEvent{ kind: .tap, id: 'button' }, ElementEvent{ kind: .tap, id: 'button' }]
		// NSTextInputClient retries an ordinary editing command with skip_dispatch;
		// the application observer receives its original key-down only once.
		before := embedder_focus_keys.len
		assert !embedder_event(app, &C.ui2_embedder_event{ kind: 7, key_code: int(KeyCode.left), text_input: true })
		assert !embedder_event(app, &C.ui2_embedder_event{ kind: 7, key_code: int(KeyCode.left), skip_dispatch: true })
		assert embedder_focus_keys.len == before + 1
		assert (g_text_editors['edit'] or { panic('missing editor') }).selection.caret == 3
	}

	fn test_embedder_composition_and_text_commit_keep_their_own_input_provenance() {
		previous_app := g_gg_app
		previous := activate_custom_window_state(new_custom_window_state())
		defer { activate_custom_window_state(previous); g_gg_app = previous_app }
		mut app := &GgApp{ window_state: new_custom_window_state() }
		activate_custom_window_state(app.window_state)
		g_gg_app = app
		mount_embedder_focus_fixture(app)
		embedder_focus_taps = []ElementEvent{}
		focus('button')
		assert embedder_event(app, &C.ui2_embedder_event{ kind: 7, key_code: int(KeyCode.space) })
		assert text('edit') == 'seed'
		// IME text has no association with that consumed physical action.
		embedder_text(app, &C.ui2_embedder_text_event{ kind: 2, text: 'ñ'.str, selection_start: 1, replacement_start: -1 })
		assert app.composition.field_id == 'edit'
		assert text('edit') == 'seed'
		assert !embedder_event(app, &C.ui2_embedder_event{ kind: 7, key_code: int(KeyCode.enter), text_input: true })
		assert !embedder_event(app, &C.ui2_embedder_event{ kind: 7, key_code: int(KeyCode.tab), text_input: true })
		assert focused_id() == 'edit' && app.composition.field_id == 'edit'
		embedder_text(app, &C.ui2_embedder_text_event{ kind: 1, text: 'ñ'.str, replacement_start: -1 })
		assert text('edit') == 'seedñ' && app.composition.field_id == ''
		assert !embedder_event(app, &C.ui2_embedder_event{ kind: 8, key_code: int(KeyCode.space) })
		assert !embedder_event(app, &C.ui2_embedder_event{ kind: 7, key_code: int(KeyCode.space), text_input: true })
		embedder_text(app, &C.ui2_embedder_text_event{ kind: 1, text: ' '.str, replacement_start: -1 })
		assert text('edit') == 'seedñ '
		assert embedder_focus_taps == [ElementEvent{ kind: .tap, id: 'button' }]
	}
}
