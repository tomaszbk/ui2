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

	fn mount_custom_runtime_editor(mut w Window, multiline bool, value string, readonly bool) {
		mut tree := LayoutTree{}
		tree.replace(screen(0xffffff, [Element{
			kind:     if multiline { Kind.text_area } else { Kind.text_field }
			id:       'editor'
			frame:    rect(0, 0, 180, 60)
			text:     value
			readonly: readonly
			on_event: custom_runtime_change
		}])) or { panic(err) }
		root := tree.resolve(LayoutConstraints{}, unsafe { nil }, LayoutEnvironment{}) or { panic(err) }
		w.active_fields.clear()
		w.update_custom_focus_tree(root)
		w.sync_mounted_focus_controls(root, 'root')
		w.prune_unmounted_state()
		w.focus('editor')
		w.hit_targets = [w.custom_focus_target(w.navigation.node('editor') or {
			panic('missing mounted editor')
		})]
	}

	fn test_custom_d3d_retained_presentation_survives_suspend_restore_and_pending_work() {
		mut w := &Window{}
		w.configure_custom_presentation(gfx.Backend.d3d11)
		initial := w.scheduler.begin_frame(0) or { panic('missing first frame') }
		assert initial.build && initial.draw
		w.scheduler.finish_frame(initial)
		baseline := w.scheduler.stats()
		for now in 1 .. 4 {
			idle := w.scheduler.begin_frame(now) or { panic('D3D must repaint its backbuffer') }
			assert idle.draw && !idle.build && idle.reasons == RenderReason.presentation
			w.scheduler.finish_frame(idle)
		}
		assert w.scheduler.stats().requests == baseline.requests
		assert w.scheduler.stats().generation == baseline.generation
		// A model change requested during presentation survives finish_frame.
		presenting := w.scheduler.begin_frame(4) or { panic('missing presentation') }
		w.scheduler.invalidate(.build)
		w.scheduler.finish_frame(presenting)
		changed := w.scheduler.begin_frame(5) or { panic('lost model update') }
		assert changed.build && changed.reasons == RenderReason.build
		w.scheduler.finish_frame(changed)
		on_event(&gg.Event{ typ: .iconified }, mut w)
		if _ := w.scheduler.begin_frame(6) {
			assert false, 'a minimized D3D window must suspend UI drawing'
		}
		on_event(&gg.Event{ typ: .restored }, mut w)
		restored := w.scheduler.begin_frame(7) or { panic('missing restored surface') }
		assert restored.build && restored.draw && restored.reasons.has(.surface)
		w.scheduler.finish_frame(restored)
		retained := w.scheduler.begin_frame(8) or { panic('lost D3D presentation after restore') }
		assert retained.draw && !retained.build && retained.reasons == RenderReason.presentation
		w.scheduler.finish_frame(retained)
		w.scheduler.close()
		if _ := w.scheduler.begin_frame(9) {
			assert false, 'closed contexts must never repaint'
		}
		// A Metal callback can omit submission; do not make all hosts repaint.
		mut metal := &Window{}
		metal.configure_custom_presentation(gfx.Backend.metal_macos)
		first := metal.scheduler.begin_frame(0) or { panic('missing Metal mount') }
		metal.scheduler.finish_frame(first)
		if _ := metal.scheduler.begin_frame(1) {
			assert false, 'idle Metal must skip drawing'
		}
	}

	fn test_custom_windows_x11_delete_char_sequence_edits_utf8_once() {
		previous_changes := custom_runtime_changes.clone()
		mut w := &Window{}
		defer {
			w.forget_text_state('editor')
			custom_runtime_changes = previous_changes.clone()
		}
		for multiline in [false, true] {
			mount_custom_runtime_editor(mut w, multiline, 'cañé🙂', false)
			w.replace_text_value('editor', 'cañé🙂')
			w.replace_text_editor('editor', TextEditor{
				text:      'cañé🙂'.clone()
				selection: TextSelection{ anchor: 2, caret: 2 }
			})
			custom_runtime_changes = []string{}
			// gg forwards KEY_DOWN, then synthesizes CHAR(127) on Windows/X11.
			on_event(&gg.Event{ typ: .key_down, key_code: .delete }, mut w)
			on_event(&gg.Event{ typ: .char, char_code: 127 }, mut w)
			assert w.text('editor') == 'caé🙂'
			assert w.text_editors['editor'].selection == TextSelection{ anchor: 2, caret: 2 }
			assert w.focused_id() == 'editor'
			assert custom_runtime_changes == ['caé🙂']
		}
	}

	fn test_custom_char_events_ignore_control_codes_and_invalid_unicode_scalars() {
		previous_changes := custom_runtime_changes.clone()
		mut w := &Window{}
		defer {
			w.forget_text_state('editor')
			custom_runtime_changes = previous_changes.clone()
		}
		mount_custom_runtime_editor(mut w, true, 'café', false)
		w.replace_text_value('editor', 'café')
		w.replace_text_editor('editor', text_editor('café'.clone()))
		custom_runtime_changes = []string{}
		for code in [u32(0), 8, 9, 13, 31, 127, 0xd800, 0xdfff, 0x110000, 0xffffffff] {
			on_event(&gg.Event{ typ: .char, char_code: code }, mut w)
		}
		assert w.text('editor') == 'café'
		assert w.text_editors['editor'].selection == TextSelection{ anchor: 4, caret: 4 }
		assert custom_runtime_changes.len == 0
		// AltGr is Ctrl+Alt on Windows: printable text must still be accepted.
		on_event(&gg.Event{ typ: .char, char_code: u32(`ñ`), modifiers: u32(gg.Modifier.ctrl) | u32(gg.Modifier.alt) }, mut w)
		on_event(&gg.Event{ typ: .char, char_code: u32(`🙂`) }, mut w)
		assert w.text('editor') == 'caféñ🙂'
		assert w.text_editors['editor'].selection == TextSelection{ anchor: 6, caret: 6 }
		assert custom_runtime_changes == ['caféñ', 'caféñ🙂']
	}

	fn test_custom_scalar_filter_preserves_mounted_readonly_edit_guard() {
		previous_changes := custom_runtime_changes.clone()
		defer {
			custom_runtime_changes = previous_changes.clone()
		}
		mut w := &Window{}
		for multiline in [false, true] {
			mount_custom_runtime_editor(mut w, multiline, 'cañé🙂', true)
			custom_runtime_changes = []string{}
			on_event(&gg.Event{ typ: .key_down, key_code: .delete }, mut w)
			for code in [u32(127), u32(`ñ`), u32(`🙂`)] {
				on_event(&gg.Event{ typ: .char, char_code: code }, mut w)
			}
			assert w.focused_id() == 'editor'
			assert w.text('editor') == 'cañé🙂'
			assert custom_runtime_changes.len == 0
		}
	}
}
