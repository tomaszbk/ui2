// vtest vflags: -d ui2_custom_rendering -d ui2_embedder
// vfmt off
@[has_globals]
module ui2

$if macos && ui2_custom_rendering ? && ui2_embedder ? && !ui2_headless ? {
	import macos

	#include "@VMODROOT/tests/embedder/native_darwin.h"
	fn C.ui2_fixture_key(window voidptr, code u16, value &char, modifiers u64) bool
	fn C.ui2_fixture_click(window voidptr, x f64, y f64) bool
	fn C.ui2_fixture_preedit(window voidptr, value &char) bool
	fn C.ui2_fixture_commit(window voidptr, value &char) bool

	__global readonly_navigation_window = CustomWindow{}
	__global readonly_navigation_posted bool
	__global readonly_navigation_events = []ElementEvent{}
	__global readonly_navigation_keys = []KeyEvent{}
	__global readonly_navigation_shortcuts = []string{}

	fn readonly_navigation_event(event ElementEvent) { readonly_navigation_events << event }
	fn readonly_navigation_key(event KeyEvent) { readonly_navigation_keys << event }
	fn readonly_navigation_shortcut(key string) { readonly_navigation_shortcuts << key }

	fn readonly_navigation_send(code u16, value string, modifiers u64) {
		before := readonly_navigation_keys.len
		assert C.ui2_fixture_key(readonly_navigation_window.native_handle(), code, value.str, modifiers)
		assert readonly_navigation_keys.len == before + 1, 'host must dispatch each key-down once'
		assert readonly_navigation_shortcuts.len == readonly_navigation_keys.len
	}

	fn readonly_navigation_selection(id string, anchor int, caret int, location u64, length u64) {
		assert focused_id() == id
		editor := g_text_editors[id] or { panic('missing mounted editor') }
		assert editor.selection == TextSelection{anchor: anchor, caret: caret}
		view := macos.msg_id(readonly_navigation_window.native_handle(), 'contentView')
		range := macos.msg_range(view, 'selectedRange')
		assert range.location == location && range.length == length, 'native snapshot uses UTF-16 ranges'
	}

	fn readonly_navigation_check() {
		defer { readonly_navigation_window.close() }
		on_key_event(readonly_navigation_key)
		on_key(readonly_navigation_shortcut)
		dismiss_keyboard()
		readonly_navigation_send(0x30, '\t', 0)
		assert focused_id() == 'readonly_field', 'Tab includes readonly editors in declared order'
		view := macos.msg_id(readonly_navigation_window.native_handle(), 'contentView')
		for id in ['readonly_field', 'readonly_area'] {
			assert focused_id() == id
			assert !macos.msg_bool(view, 'textEnabled'), 'readonly must not enable Cocoa text mutations'
			original := text(id)
			assert original == if id == 'readonly_field' { 'ñ🙂 café' } else { 'ñ🙂\ncafé' }
			readonly_navigation_send(0x7b, '\uf702', 0)
			readonly_navigation_selection(id, 6, 6, 7, 0)
			readonly_navigation_send(0x7b, '\uf702', 0x20000)
			readonly_navigation_selection(id, 6, 5, 6, 1)
			readonly_navigation_send(0x7c, '\uf703', 0x20000)
			readonly_navigation_selection(id, 6, 6, 7, 0)
			readonly_navigation_send(0x73, '\uf729', 0)
			start := if id == 'readonly_field' { 0 } else { 3 }
			readonly_navigation_selection(id, start, start, u64(if start == 0 { 0 } else { 4 }), 0)
			if id == 'readonly_area' {
				readonly_navigation_send(0x7e, '\uf700', 0)
				readonly_navigation_selection(id, 0, 0, 0, 0)
				readonly_navigation_send(0x7d, '\uf701', 0x20000)
				readonly_navigation_selection(id, 0, 3, 0, 4)
			}
			readonly_navigation_send(0x73, '\uf729', 0x100000)
			readonly_navigation_selection(id, 0, 0, 0, 0)
			readonly_navigation_send(0x7c, '\uf703', 0x20000)
			readonly_navigation_send(0x7c, '\uf703', 0x20000)
			readonly_navigation_selection(id, 0, 2, 0, 3)
			readonly_navigation_send(0x7b, '\uf702', 0x20000)
			readonly_navigation_selection(id, 0, 1, 0, 1)
			readonly_navigation_send(0x7c, '\uf703', 0x20000)
			readonly_navigation_selection(id, 0, 2, 0, 3)
			readonly_navigation_send(0x77, '\uf72b', 0x100000)
			readonly_navigation_selection(id, 7, 7, 8, 0)
			readonly_navigation_send(0x73, '\uf729', 0x20000)
			readonly_navigation_selection(id, 7, start, u64(if start == 0 { 0 } else { 4 }), u64(if start == 0 { 8 } else { 4 }))
			readonly_navigation_send(0x00, 'a', 0x100000)
			readonly_navigation_selection(id, 0, 7, 0, 8)
			assert readonly_navigation_shortcuts.last() == if id == 'readonly_field' { 'cmd+a' } else { 'text:${id}:cmd+a' }
			for mutation in [u16(0x33), 0x75, 0x24, 0x4c, 0x31, 0x2d] {
				value := match mutation { 0x33 { '\u007f' } 0x75 { '\uf728' } 0x24, 0x4c { '\r' } 0x31 { ' ' } else { 'ñ' } }
				readonly_navigation_send(mutation, value, 0)
				assert text(id) == original
				readonly_navigation_selection(id, 0, 7, 0, 8)
			}
			assert C.ui2_fixture_preedit(readonly_navigation_window.native_handle(), 'á'.str)
			assert C.ui2_fixture_commit(readonly_navigation_window.native_handle(), 'é'.str)
			// Text deliveries themselves must remain guarded, independently of
			// Cocoa's disabled NSTextInputClient and the ordinary CHAR route.
			embedder_text(g_gg_app, &C.ui2_embedder_text_event{kind: 2, text: 'á'.str, replacement_start: -1})
			embedder_text(g_gg_app, &C.ui2_embedder_text_event{kind: 1, text: 'é'.str, replacement_start: -1})
			assert text(id) == original && g_gg_app.composition.field_id == ''
			assert !macos.msg_bool(view, 'hasMarkedText')
			assert macos.utf8_string(macos.msg_id(view, 'textSnapshot')) == original
			readonly_navigation_selection(id, 0, 7, 0, 8)
			assert readonly_navigation_events.len == 0, 'readonly emits no change or submit'
			readonly_navigation_send(0x30, '\t', 0)
		}
		// Ordinary editable commands still take Cocoa's text-input fallback,
		// without duplicate dispatch or duplicate caret movement.
		for id in ['editable_field', 'editable_area'] {
			assert focused_id() == id && macos.msg_bool(view, 'textEnabled')
			readonly_navigation_send(0x7b, '\uf702', 0)
			readonly_navigation_selection(id, 3, 3, 3, 0)
			readonly_navigation_send(0x7b, '\uf702', 0x20000)
			readonly_navigation_selection(id, 3, 2, 2, 1)
			assert C.ui2_fixture_commit(readonly_navigation_window.native_handle(), 'ñ'.str)
			assert text(id) == 'señd'
			readonly_navigation_selection(id, 3, 3, 3, 0)
			assert readonly_navigation_events.last() == ElementEvent{kind: .change, id: id, text: 'señd'}
			readonly_navigation_send(0x30, '\t', 0)
		}
		assert readonly_navigation_events.len == 2
		assert focused_id() == 'readonly_field'
		readonly_navigation_send(0x30, '\t', 0x20000)
		assert focused_id() == 'editable_area', 'Shift+Tab retains the same focus order'
		assert C.ui2_fixture_click(readonly_navigation_window.native_handle(), 30, 80)
		assert focused_id() == 'readonly_area' && !macos.msg_bool(view, 'textEnabled')
		readonly_navigation_send(0x00, 'a', 0x100000)
		readonly_navigation_selection('readonly_area', 0, 7, 0, 8)
		assert text('readonly_field') == 'ñ🙂 café' && text('readonly_area') == 'ñ🙂\ncafé'
		eprintln('owned Cocoa readonly text_field/text_area navigation selection mutation guards and editable fallback passed')
	}

	fn readonly_navigation_build() Element {
		if !readonly_navigation_posted {
			readonly_navigation_posted = true
			assert ui_dispatcher().post(readonly_navigation_check)
		}
		return screen(0xffffff, [
			Element{kind: .text_field, id: 'readonly_field', key: 'readonly_field', text: 'ñ🙂 café', readonly: true, on_event: readonly_navigation_event, frame: rect(20, 20, 240, 32)},
			Element{kind: .text_area, id: 'readonly_area', key: 'readonly_area', text: 'ñ🙂\ncafé', readonly: true, on_event: readonly_navigation_event, frame: rect(20, 70, 240, 80)},
			Element{kind: .text_field, id: 'editable_field', text: 'seed', on_event: readonly_navigation_event, frame: rect(20, 160, 240, 32)},
			Element{kind: .text_area, id: 'editable_area', text: 'seed', on_event: readonly_navigation_event, frame: rect(20, 200, 240, 80)},
		])
	}

	fn test_owned_embedder_readonly_navigation_and_mutation_guards() {
		pool := macos.autorelease_pool_new()
		defer { macos.release(pool) }
		previous_app := g_gg_app
		previous := activate_custom_window_state(new_custom_window_state())
		defer { activate_custom_window_state(previous); g_gg_app = previous_app }
		readonly_navigation_posted = false
		readonly_navigation_events.clear()
		readonly_navigation_keys.clear()
		readonly_navigation_shortcuts.clear()
		readonly_navigation_window = open_window('Readonly editor host navigation', 320, 320, readonly_navigation_build)!
		defer { readonly_navigation_window.close() }
		run_windows()
	}
}
