// vtest vflags: -d ui2_custom_rendering -d ui2_embedder
// vfmt off
@[has_globals]
module ui2

$if macos && ui2_custom_rendering ? && ui2_embedder ? && !ui2_headless ? {
	__global embedder_focus_taps = []ElementEvent{}
	__global embedder_focus_keys = []KeyEvent{}

	fn embedder_focus_tap(event ElementEvent) {
		mut w := event.window
		embedder_focus_taps << event
		w.focus('edit')
	}
	fn embedder_focus_key(event KeyEvent) { embedder_focus_keys << event }

	fn mount_embedder_focus_fixture(mut w Window) {
		root := screen(0xffffff, [
			Element{ kind: .text_area, id: 'edit', text: 'seed', frame: rect(0, 40, 180, 60) },
			Element{ kind: .button, id: 'button', on_event: embedder_focus_tap, frame: rect(0, 0, 100, 30) },
			Element{ kind: .button, id: 'right', on_event: embedder_focus_tap, frame: rect(200, 0, 100, 30) },
		])
		w.update_custom_focus_tree(root)
		w.sync_mounted_focus_controls(root, 'root')
		w.key_event_handler = embedder_focus_key
		w.focus('edit')
	}

	fn test_embedder_real_keyboard_route_navigates_and_returns_consumption_to_host() {
		mut w := &Window{}
		mount_embedder_focus_fixture(mut w)
		embedder_focus_taps = []ElementEvent{}
		embedder_focus_keys = []KeyEvent{}
		assert embedder_event(w, &C.ui2_embedder_event{ kind: 7, key_code: int(KeyCode.tab), text_input: true })
		assert w.focused_id() == 'button'
		assert embedder_event(w, &C.ui2_embedder_event{ kind: 7, key_code: int(KeyCode.right) })
		assert w.focused_id() == 'right'
		for key in [KeyCode.space, .enter, .kp_enter] {
			w.focus('button')
			assert embedder_event(w, &C.ui2_embedder_event{ kind: 7, key_code: int(key) })
			assert w.focused_id() == 'edit'
			for _ in 0 .. 2 {
				assert embedder_event(w, &C.ui2_embedder_event{ kind: 7, key_code: int(key), repeat: true, text_input: true })
			}
			assert !embedder_event(w, &C.ui2_embedder_event{ kind: 8, key_code: int(key) })
			assert w.text('edit') == 'seed'
		}
		assert embedder_focus_taps == [ElementEvent{ window: w, kind: .click, id: 'button' }, ElementEvent{ window: w, kind: .click, id: 'button' }, ElementEvent{ window: w, kind: .click, id: 'button' }]
		// NSTextInputClient retries an ordinary editing command with skip_dispatch;
		// the application observer receives its original key-down only once.
		before := embedder_focus_keys.len
		assert !embedder_event(w, &C.ui2_embedder_event{ kind: 7, key_code: int(KeyCode.left), text_input: true })
		assert !embedder_event(w, &C.ui2_embedder_event{ kind: 7, key_code: int(KeyCode.left), skip_dispatch: true })
		assert embedder_focus_keys.len == before + 1
		assert (w.text_editors['edit'] or { panic('missing editor') }).selection.caret == 3
	}

	fn test_embedder_composition_and_text_commit_keep_their_own_input_provenance() {
		mut w := &Window{}
		mount_embedder_focus_fixture(mut w)
		embedder_focus_taps = []ElementEvent{}
		w.focus('button')
		assert embedder_event(w, &C.ui2_embedder_event{ kind: 7, key_code: int(KeyCode.space) })
		assert w.text('edit') == 'seed'
		// IME text has no association with that consumed physical action.
		embedder_text(w, &C.ui2_embedder_text_event{ kind: 2, text: 'ñ'.str, selection_start: 1, replacement_start: -1 })
		assert w.composition.field_id == 'edit'
		assert w.text('edit') == 'seed'
		assert !embedder_event(w, &C.ui2_embedder_event{ kind: 7, key_code: int(KeyCode.enter), text_input: true })
		assert !embedder_event(w, &C.ui2_embedder_event{ kind: 7, key_code: int(KeyCode.tab), text_input: true })
		assert w.focused_id() == 'edit' && w.composition.field_id == 'edit'
		embedder_text(w, &C.ui2_embedder_text_event{ kind: 1, text: 'ñ'.str, replacement_start: -1 })
		assert w.text('edit') == 'seedñ' && w.composition.field_id == ''
		assert !embedder_event(w, &C.ui2_embedder_event{ kind: 8, key_code: int(KeyCode.space) })
		assert !embedder_event(w, &C.ui2_embedder_event{ kind: 7, key_code: int(KeyCode.space), text_input: true })
		embedder_text(w, &C.ui2_embedder_text_event{ kind: 1, text: ' '.str, replacement_start: -1 })
		assert w.text('edit') == 'seedñ '
		assert embedder_focus_taps == [ElementEvent{ window: w, kind: .click, id: 'button' }]
	}
}
