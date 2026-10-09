// vtest vflags: -d ui2_custom_rendering
@[has_globals]
module ui2

$if ( linux || ( ( macos || windows ) && ui2_custom_rendering ?) ) && !ui2_headless ? {
	import gg
	import sokol.gfx

	__global custom_runtime_changes = []string{}

	fn custom_runtime_change(event ElementEvent) {
		if event.kind == .change {
			custom_runtime_changes << event.text
		}
	}

	fn mount_custom_runtime_editor(multiline bool, value string, readonly bool) {
		root := effective_element_state(screen(0xffffff, [Element{
			kind:     if multiline { Kind.text_area } else { Kind.text_field }
			id:       'editor'
			frame:    rect(0, 0, 180, 60)
			text:     value
			readonly: readonly
			on_event: custom_runtime_change
		}]), true)
		g_active_fields.clear()
		update_custom_focus_tree(root)
		sync_mounted_focus_controls(root, 'root')
		prune_unmounted_state()
		focus('editor')
		g_hit_targets = [custom_focus_target(g_focus_navigation.node('editor') or {
			panic('missing mounted editor')
		})]
	}

	fn test_custom_d3d_retained_presentation_survives_suspend_restore_and_pending_work() {
		previous_app := g_gg_app
		state := new_custom_window_state()
		previous := activate_custom_window_state(state)
		defer {
			activate_custom_window_state(previous)
			g_gg_app = previous_app
		}
		mut app := &GgApp{ scheduler: new_frame_coordinator() }
		g_gg_app = app
		configure_custom_presentation(app, gfx.Backend.d3d11)
		initial := app.scheduler.begin_frame(0) or { panic('missing first frame') }
		assert initial.build && initial.draw
		app.scheduler.finish_frame(initial)
		baseline := app.scheduler.stats()
		for now in 1 .. 4 {
			idle := app.scheduler.begin_frame(now) or { panic('D3D must repaint its backbuffer') }
			assert idle.draw && !idle.build && idle.reasons == [.presentation]
			app.scheduler.finish_frame(idle)
		}
		assert app.scheduler.stats().requests == baseline.requests
		assert app.scheduler.stats().generation == baseline.generation
		// A model change requested during presentation survives finish_frame.
		presenting := app.scheduler.begin_frame(4) or { panic('missing presentation') }
		app.scheduler.invalidate(.build)
		app.scheduler.finish_frame(presenting)
		changed := app.scheduler.begin_frame(5) or { panic('lost model update') }
		assert changed.build && changed.reasons == [.build]
		app.scheduler.finish_frame(changed)
		on_event(&gg.Event{ typ: .iconified }, app)
		if _ := app.scheduler.begin_frame(6) {
			assert false, 'a minimized D3D window must suspend UI drawing'
		}
		on_event(&gg.Event{ typ: .restored }, app)
		restored := app.scheduler.begin_frame(7) or { panic('missing restored surface') }
		assert restored.build && restored.draw && RenderReason.surface in restored.reasons
		app.scheduler.finish_frame(restored)
		retained := app.scheduler.begin_frame(8) or { panic('lost D3D presentation after restore') }
		assert retained.draw && !retained.build && retained.reasons == [.presentation]
		app.scheduler.finish_frame(retained)
		app.scheduler.close()
		if _ := app.scheduler.begin_frame(9) {
			assert false, 'closed contexts must never repaint'
		}
		// A Metal callback can omit submission; do not make all hosts repaint.
		mut metal := &GgApp{ scheduler: new_frame_coordinator() }
		configure_custom_presentation(metal, gfx.Backend.metal_macos)
		first := metal.scheduler.begin_frame(0) or { panic('missing Metal mount') }
		metal.scheduler.finish_frame(first)
		if _ := metal.scheduler.begin_frame(1) {
			assert false, 'idle Metal must skip drawing'
		}
	}

	fn test_custom_windows_x11_delete_char_sequence_edits_utf8_once() {
		previous_app := g_gg_app
		previous_changes := custom_runtime_changes.clone()
		state := new_custom_window_state()
		previous := activate_custom_window_state(state)
		defer {
			forget_text_state('editor')
			activate_custom_window_state(previous)
			g_gg_app = previous_app
			custom_runtime_changes = previous_changes.clone()
		}
		mut app := &GgApp{ scheduler: new_frame_coordinator() }
		g_gg_app = app
		for multiline in [false, true] {
			mount_custom_runtime_editor(multiline, 'cañé🙂', false)
			replace_text_value('editor', 'cañé🙂')
			replace_text_editor('editor', TextEditor{
				text:      'cañé🙂'.clone()
				selection: TextSelection{ anchor: 2, caret: 2 }
			})
			custom_runtime_changes = []string{}
			// gg forwards KEY_DOWN, then synthesizes CHAR(127) on Windows/X11.
			on_event(&gg.Event{ typ: .key_down, key_code: .delete }, app)
			on_event(&gg.Event{ typ: .char, char_code: 127 }, app)
			assert text('editor') == 'caé🙂'
			assert g_text_editors['editor'].selection == TextSelection{ anchor: 2, caret: 2 }
			assert focused_id() == 'editor'
			assert custom_runtime_changes == ['caé🙂']
		}
	}

	fn test_custom_char_events_ignore_control_codes_and_invalid_unicode_scalars() {
		previous_app := g_gg_app
		previous_changes := custom_runtime_changes.clone()
		state := new_custom_window_state()
		previous := activate_custom_window_state(state)
		defer {
			forget_text_state('editor')
			activate_custom_window_state(previous)
			g_gg_app = previous_app
			custom_runtime_changes = previous_changes.clone()
		}
		mut app := &GgApp{ scheduler: new_frame_coordinator() }
		g_gg_app = app
		mount_custom_runtime_editor(true, 'café', false)
		replace_text_value('editor', 'café')
		replace_text_editor('editor', text_editor('café'.clone()))
		custom_runtime_changes = []string{}
		for code in [u32(0), 8, 9, 13, 31, 127, 0xd800, 0xdfff, 0x110000, 0xffffffff] {
			on_event(&gg.Event{ typ: .char, char_code: code }, app)
		}
		assert text('editor') == 'café'
		assert g_text_editors['editor'].selection == TextSelection{ anchor: 4, caret: 4 }
		assert custom_runtime_changes.len == 0
		// AltGr is Ctrl+Alt on Windows: printable text must still be accepted.
		on_event(&gg.Event{ typ: .char, char_code: u32(`ñ`), modifiers: u32(gg.Modifier.ctrl) | u32(gg.Modifier.alt) }, app)
		on_event(&gg.Event{ typ: .char, char_code: u32(`🙂`) }, app)
		assert text('editor') == 'caféñ🙂'
		assert g_text_editors['editor'].selection == TextSelection{ anchor: 6, caret: 6 }
		assert custom_runtime_changes == ['caféñ', 'caféñ🙂']
	}

	fn test_custom_scalar_filter_preserves_mounted_readonly_edit_guard() {
		previous_app := g_gg_app
		previous_changes := custom_runtime_changes.clone()
		previous := activate_custom_window_state(new_custom_window_state())
		defer {
			activate_custom_window_state(previous)
			g_gg_app = previous_app
			custom_runtime_changes = previous_changes.clone()
		}
		mut app := &GgApp{ scheduler: new_frame_coordinator() }
		g_gg_app = app
		for multiline in [false, true] {
			mount_custom_runtime_editor(multiline, 'cañé🙂', true)
			custom_runtime_changes = []string{}
			on_event(&gg.Event{ typ: .key_down, key_code: .delete }, app)
			for code in [u32(127), u32(`ñ`), u32(`🙂`)] {
				on_event(&gg.Event{ typ: .char, char_code: code }, app)
			}
			assert focused_id() == 'editor'
			assert text('editor') == 'cañé🙂'
			assert custom_runtime_changes.len == 0
		}
	}
}
