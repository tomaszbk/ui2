// vtest vflags: -d ui2_custom_rendering -d ui2_embedder
// vfmt off
@[has_globals]
module ui2

$if macos && ui2_custom_rendering ? && ui2_embedder ? && !ui2_headless ? {
	import gg
	import macos

	#include "@VMODROOT/tests/render_scheduler/drawable_hooks.h"
	#include "@VMODROOT/tests/embedder/native_darwin.h"
	fn C.ui2_test_pump(data voidptr, pump fn (voidptr) i64) i64
	fn C.ui2_fixture_preedit(window voidptr, value &char) bool
	fn C.ui2_fixture_commit(window voidptr, value &char) bool

	__global current_editor_readonly bool
	__global current_editor_kind = Kind.text_field
	__global current_editor_declared = 'declared ñ'
	__global current_editor_new_handler bool
	__global current_editor_events = []string{}

	fn current_editor_old(event ElementEvent) {
		current_editor_events << 'old:${event.kind}:${event.text}'
	}
	fn current_editor_new(event ElementEvent) {
		current_editor_events << 'current:${event.kind}:${event.text}'
	}
	fn current_editor_control() Element {
		return Element{kind: current_editor_kind, id: 'edit', text: current_editor_declared,
			readonly: current_editor_readonly, frame: rect(10, 10, 240, 36),
			on_event: if current_editor_new_handler { current_editor_new } else { current_editor_old }}
	}
	fn current_editor_root(mut _ Window) Element {
		return screen(0xffffff, [current_editor_control(),
			Element{kind: .text_area, id: 'other', text: 'other declared', frame: rect(10, 70, 240, 70)},
			label('caption', 'caption', rect(10, 170, 100, 24), TextStyle{}),
		])
	}
	fn current_editor_pointer(mut w Window, x f64, y f64) {
		embedder_event(w, &C.ui2_embedder_event{kind: 1, x: x, y: y})
		// Cancel without selecting a new caret on pointer-up. No frame is pumped
		// between adopting the retained patch and the following text delivery.
		w.cancel_touch()
	}
	fn current_editor_reset() {
		current_editor_readonly = false
		current_editor_kind = .text_field
		current_editor_declared = 'declared ñ'
		current_editor_new_handler = false
		current_editor_events.clear()
	}

	fn test_current_editor_policy_buffer_and_handler_are_adopted_before_paint() {
		pool := macos.autorelease_pool_new()
		defer { macos.release(pool) }
		current_editor_reset()
		mut app := new_app()
		mut w := app.new_window(title: 'Current editor before paint', width: 320, height: 240, build: current_editor_root)!
		defer { w.quit() }
		assert C.ui2_test_pump(w, embedder_pump) == -1
		draws := w.scheduler.stats().draws
		w.focus('edit')
		w.set_text('edit', 'local café ñ')
		w.set_text('other', 'other café ñ')
		w.text_area_set_selection('other', 3, 3)
		current_editor_pointer(mut w, 20, 20)
		assert C.ui2_fixture_preedit(w.native_handle(), 'á'.str)
		assert w.composition.field_id == 'edit'
		current_editor_readonly = true
		current_editor_declared = 'replacement ñ'
		current_editor_new_handler = true
		w.refresh_element('edit', current_editor_control())
		current_editor_pointer(mut w, 20, 20)
		assert w.focused_id() == 'edit'
		assert w.text('edit') == 'replacement ñ'
		assert !w.editable_fields['edit']
		assert w.composition.field_id == ''
		view := macos.msg_id(w.native_handle(), 'contentView')
		assert !macos.msg_bool(view, 'textEnabled')
		assert !macos.msg_bool(view, 'hasMarkedText')
		assert macos.utf8_string(macos.msg_id(view, 'textSnapshot')) == 'replacement ñ'
		embedder_event(w, &C.ui2_embedder_event{kind: 9, char_code: `é`})
		embedder_event(w, &C.ui2_embedder_event{kind: 7, key_code: int(gg.KeyCode.backspace)})
		assert C.ui2_fixture_commit(w.native_handle(), 'é'.str)
		embedder_text(w, &C.ui2_embedder_text_event{kind: 1, text: 'é'.str, replacement_start: -1})
		assert w.text('edit') == 'replacement ñ' && current_editor_events.len == 0
		// Readonly inputs still own caret/selection navigation.
		embedder_event(w, &C.ui2_embedder_event{kind: 7, key_code: int(gg.KeyCode.home)})
		assert w.text_editors['edit'].selection.caret == 0
		current_editor_readonly = false
		current_editor_declared = 'fresh ñ'
		w.refresh_element('edit', current_editor_control())
		current_editor_pointer(mut w, 20, 20)
		assert w.text('edit') == 'fresh ñ' && w.editable_fields['edit']
		assert C.ui2_fixture_commit(w.native_handle(), 'é'.str)
		embedder_event(w, &C.ui2_embedder_event{kind: 9, char_code: `ñ`})
		assert w.text('edit') == 'fresh ñéñ'
		assert current_editor_events == ['current:change:fresh ñé', 'current:change:fresh ñéñ']
		assert w.text('other') == 'other café ñ'
		assert w.text_area_caret('other') == 6 && w.text_area_selection_length('other') == 3
		// Replacing an editor with a focusable control removes the old owned
		// buffer before the host can deliver another text transaction.
		current_editor_kind = .button
		w.refresh_element('edit', current_editor_control())
		current_editor_pointer(mut w, 20, 20)
		assert w.focused_id() == 'edit'
		assert 'edit' !in w.text_values && 'edit' !in w.text_editors
		assert 'edit' !in w.active_fields && 'edit' !in w.editable_fields
		assert !macos.msg_bool(view, 'textEnabled')
		event_count := current_editor_events.len
		assert C.ui2_fixture_commit(w.native_handle(), 'á'.str)
		assert current_editor_events.len == event_count && 'edit' !in w.text_values
		assert w.scheduler.stats().draws == draws
	}

	fn test_input_patch_preserves_unrelated_local_selection_and_native_preedit() {
		pool := macos.autorelease_pool_new()
		defer { macos.release(pool) }
		current_editor_reset()
		mut app := new_app()
		mut w := app.new_window(title: 'Unrelated input patch before paint', width: 320, height: 240, build: current_editor_root)!
		defer { w.quit() }
		assert C.ui2_test_pump(w, embedder_pump) == -1
		draws := w.scheduler.stats().draws
		w.focus('other')
		w.set_text('other', 'other café ñ')
		w.text_area_set_selection('other', 3, 3)
		current_editor_pointer(mut w, 20, 80)
		assert C.ui2_fixture_preedit(w.native_handle(), 'á'.str)
		composition := w.composition
		selection := w.text_editors['other'].selection
		view := macos.msg_id(w.native_handle(), 'contentView')
		marked := macos.msg_range(view, 'markedRange')
		current_editor_readonly = true
		w.refresh_element('edit', current_editor_control())
		caption := current_editor_root(mut w).children[2]
		w.refresh_element('caption', Element{...caption, text_style: TextStyle{...caption.text_style, color: 0xff0000}})
		current_editor_pointer(mut w, 20, 80)
		assert w.focused_id() == 'other' && w.text('other') == 'other café ñ'
		assert w.text_editors['other'].selection == selection
		assert w.composition == composition
		assert macos.msg_bool(view, 'hasMarkedText')
		current_marked := macos.msg_range(view, 'markedRange')
		assert current_marked.location == marked.location && current_marked.length == marked.length
		assert !w.editable_fields['edit']
		assert w.scheduler.stats().draws == draws
	}
}
