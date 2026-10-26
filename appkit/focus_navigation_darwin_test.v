// vtest build: macos && !ui2_custom_rendering?
// vfmt off
@[has_globals]
module ui2

$if !ui2_custom_rendering ? {
import macos

#include "@VMODROOT/appkit/focus_events_darwin_test.h"
fn C.ui2_focus_test_mark_text(editor voidptr, text voidptr, location u64, length u64)
fn C.ui2_focus_test_key_event(window voidptr, event_type u64, code u16, characters voidptr, modifiers u64, timestamp f64, repeated bool) voidptr

__global native_focus_timestamp f64
__global native_focus_keys = []KeyEvent{}
__global native_focus_resign_in_callback bool
__global native_focus_resign_in_observer bool
__global native_focus_consume_in_observer bool
__global native_marked_legacy_keys = []string{}
__global native_marked_consume bool
fn native_marked_key_handler(mut w Window, key string) {
	native_marked_legacy_keys << key
	if !native_marked_consume { return }
	if key.starts_with('text:') { w.consume_text_key() } else { w.consume_key() }
}
fn native_focus_key_observer(event KeyEvent) {
	native_focus_keys << event
	mut w := event.window
	if native_focus_consume_in_observer { w.consume_key() }
	if native_focus_resign_in_observer { macos.msg_void(w.window, 'resignKeyWindow') }
}
fn native_focus_editor_event(event ElementEvent) {
	native_focus_events << event
	if event.id == 'press' {
		mut w := event.window
		w.focus('edit')
		if native_focus_resign_in_callback { macos.msg_void(w.window, 'resignKeyWindow') }
	}
}

fn send_native_focus_key(st &Window, code u16, characters string, repeated bool, event_type u64, modifiers u64) {
	native_focus_timestamp += 1
	event := C.ui2_focus_test_key_event(st.window, event_type, code, macos.nsstring(characters), modifiers, native_focus_timestamp, repeated)
	assert event != unsafe { nil }
	macos.msg_void1(st.window, 'sendEvent:', event)
}

__global native_focus_events = []ElementEvent{}
fn native_focus_event(event ElementEvent) { native_focus_events << event }

fn test_appkit_consumed_activation_repeats_preserve_new_native_editor_until_release() {
	pool := macos.autorelease_pool_new()
	defer { macos.release(pool) }
	native_current_app()
	ensure_runtime_classes()
	mut st := appkit_fixture_window('Held activation fixture', 380, 260)
	defer {
		st.close_fixture()
	}
	mut failures := []string{}
	native_focus_resign_in_callback = false
	native_focus_resign_in_observer = false
	for kind in [Kind.text_field, .text_area] {
		for code in [u16(0x31), u16(0x24), u16(0x4c)] {
			characters := if code == 0x31 { ' ' } else if code == 0x4c { '\u0003' } else { '\r' }
			root := screen(0xffffff, [
				Element{kind: kind, id: 'edit', text: 'café ñ', on_event: native_focus_editor_event, frame: rect(10, 10, 180, 80)},
				Element{kind: .button, id: 'press', text: 'Press', on_event: native_focus_editor_event, frame: rect(10, 110, 100, 30)},
			])
			st.render_root(root)
			st.set_text('edit', 'café ñ')
			st.focus('press')
			native_focus_events = []ElementEvent{}
			native_focus_keys = []KeyEvent{}
			st.on_key_event(native_focus_key_observer)
			send_native_focus_key(st, code, characters, false, 10, 0)
			assert st.focused_id() == 'edit'
			editor := macos.msg_id(st.window, 'firstResponder')
			macos.msg_void_range(editor, 'setSelectedRange:', macos.range(2, 3))
			before := st.text('edit')
			selection := macos.msg_range(editor, 'selectedRange')
			// Refresh retains the editor and may remove the activation source.
			st.render_root(Element{...root, children: [root.children[0]]})
			for _ in 0 .. 3 { send_native_focus_key(st, code, characters, true, 10, 0) }
			// Ownership follows keyCode even when modifiers change while held.
			for modifiers in [u64(0x20000), u64(0x40000), u64(0x80000), u64(0x100000)] {
				send_native_focus_key(st, code, characters, true, 10, modifiers)
			}
			if code == 0x4c {
				send_native_focus_key(st, 0x24, '\r', false, 11, 0)
				send_native_focus_key(st, code, characters, true, 10, 0)
			}
			unchanged := st.text('edit') == before && macos.msg_range(editor, 'selectedRange') == selection
			activations := native_focus_events.filter(it.kind == .click).len
			assert native_focus_events.filter(it.kind == .submit).len == 0
			eprintln('native held kind=${kind} code=${code} activations=${activations} unchanged=${unchanged} text=${st.text('edit').bytes()}')
			if !unchanged || activations != 1 { failures << '${kind}/${code}' }
			expected_keys := if code == 0x4c { 9 } else { 8 }
			if native_focus_keys.filter(it.code == appkit_key_code(code)).len != expected_keys { failures << 'observers:${kind}/${code}' }
			// Owned activation repeats remain consumed even if composition starts
			// in the newly focused real NSTextInputClient before key release.
			C.ui2_focus_test_mark_text(editor, macos.nsstring('áñ'), 0, 2)
			assert macos.msg_bool(editor, 'hasMarkedText')
			marked_draft := st.text('edit')
			marked_selection := macos.msg_range(editor, 'selectedRange')
			observed := native_focus_keys.len
			send_native_focus_key(st, code, characters, true, 10, 0)
			assert native_focus_keys.len == observed + 1
			assert st.text('edit') == marked_draft && macos.msg_range(editor, 'selectedRange') == marked_selection
			assert macos.msg_bool(editor, 'hasMarkedText') && st.focused_id() == 'edit'
			macos.msg_void(editor, 'unmarkText')
			st.set_text('edit', before)
			macos.msg_void_range(editor, 'setSelectedRange:', selection)
			// Unrelated Unicode input still reaches the editor while owned.
			send_native_focus_key(st, 0x2d, 'ñ', false, 10, 0)
			assert st.text('edit') == 'caññ'
			assert native_focus_keys.filter(it.code == .n).len == 1
			unicode_text := st.text('edit')
			unicode_selection := macos.msg_range(editor, 'selectedRange')
			send_native_focus_key(st, code, characters, true, 10, 0)
			assert st.text('edit') == unicode_text && macos.msg_range(editor, 'selectedRange') == unicode_selection
			send_native_focus_key(st, code, characters, false, 11, 0)
			send_native_focus_key(st, 0x31, ' ', false, 10, 0)
			send_native_focus_key(st, 0x31, ' ', true, 10, 0)
			assert st.text('edit') == 'cañ  ñ'
			if kind == .text_area {
				value := st.text('edit')
				send_native_focus_key(st, code, characters, false, 10, 0)
				assert st.text('edit') != value
			} else {
				send_native_focus_key(st, 0x24, '\r', false, 10, 0)
				assert native_focus_events.filter(it.kind == .submit).len == 1
			}
		}
	}
	assert failures.len == 0, failures.str()
	// Repeat navigation remains per-event, unlike a consumed activation press.
	st.render_root(screen(0xffffff, [
		Element{kind: .text_field, id: 'edit', text: 'ordinary', frame: rect(10, 10, 180, 30)},
		Element{kind: .button, id: 'press', text: 'Left', on_event: native_focus_editor_event, frame: rect(10, 60, 100, 30)},
		Element{kind: .button, id: 'right', text: 'Right', on_event: native_focus_event, frame: rect(130, 60, 100, 30)},
	]))
	st.focus('edit')
	native_focus_keys = []KeyEvent{}
	send_native_focus_key(st, 0x30, '\t', false, 10, 0)
	assert st.focused_id() == 'press'
	send_native_focus_key(st, 0x30, '\t', true, 10, 0)
	assert st.focused_id() == 'right'
	send_native_focus_key(st, 0x30, '\t', false, 11, 0)
	send_native_focus_key(st, 0x7b, '\uf702', false, 10, 0)
	assert st.focused_id() == 'press'
	send_native_focus_key(st, 0x7c, '\uf703', true, 10, 0)
	assert st.focused_id() == 'right'
	send_native_focus_key(st, 0x30, '\t', false, 10, 0x20000)
	assert st.focused_id() == 'press' && st.activation_keys.len == 0
	assert native_focus_keys.len == 5
	// Resign during the synchronous action must not be undone by a late latch.
	st.render_root(screen(0xffffff, [
		Element{kind: .text_area, id: 'edit', text: 'local ñ', frame: rect(10, 10, 180, 80)},
		Element{kind: .button, id: 'press', text: 'Press', on_event: native_focus_editor_event, frame: rect(10, 110, 100, 30)},
	]))
	native_focus_resign_in_callback = true
	st.focus('press')
	send_native_focus_key(st, 0x31, ' ', false, 10, 0)
	assert st.activation_keys.len == 0
	native_focus_resign_in_callback = false
	// Observers can release the host too; do not claim a press afterwards.
	st.focus('press')
	native_focus_resign_in_observer = true
	taps_before := native_focus_events.filter(it.kind == .click).len
	send_native_focus_key(st, 0x31, ' ', false, 10, 0)
	assert native_focus_events.filter(it.kind == .click).len == taps_before
	assert st.activation_keys.len == 0
	native_focus_resign_in_observer = false
	st.focus('press')
	send_native_focus_key(st, 0x31, ' ', false, 10, 0)
	assert st.activation_keys.len == 1
	delegate := native_new_object('UI2AppDelegate')
	macos.msg_void1(delegate, 'applicationDidResignActive:', unsafe { nil })
	macos.release(delegate)
	assert st.activation_keys.len == 0
	value := st.text('edit')
	send_native_focus_key(st, 0x31, ' ', true, 10, 0)
	assert st.text('edit') != value
	st.focus('press')
	send_native_focus_key(st, 0x4c, '\u0003', false, 10, 0)
	assert st.activation_keys.len == 1
	macos.msg_void(st.window, 'close')
	assert st.activation_keys.len == 0
}

fn test_appkit_navigation_preserves_native_editor_selection_and_reveals_offscreen_controls() {
	pool := macos.autorelease_pool_new()
	defer { macos.release(pool) }
	native_current_app()
	ensure_runtime_classes()
	mut st := appkit_fixture_window('Focus fixture', 380, 260)
	defer {
		st.close_fixture()
	}
	root := screen(0xffffff, [
		Element{kind: .text_field, id: 'edit', text: 'café ñ', frame: rect(10, 10, 180, 30)},
		Element{kind: .button, id: 'press', text: 'Press', on_event: native_focus_event, frame: rect(10, 50, 100, 30)},
		Element{kind: .view, id: 'scope', focus_scope: true, frame: rect(210, 10, 150, 100), children: [
			Element{kind: .view, id: 'composite', button_behavior: true, on_event: native_focus_event, frame: rect(0, 0, 100, 30)},
		]},
		scroll('pane', rect(10, 110, 180, 80), 0xffffff, [Element{kind: .button, id: 'below', text: 'Below', on_event: native_focus_event, frame: rect(0, 500, 100, 30)}]),
	])
	st.render_root(root)
	st.focus('edit')
	assert st.focused_id() == 'edit'
	field := st.views['edit'] or { panic('missing field') }
	native_set_text(field, 'local ñá')
	native_restore_control_selection(field, 2, 3)
	assert native_control_selected_range(field) == macos.range(2, 3)
	st.render_root(Element{...root, box: BoxStyle{bg: 0xeeeeee}})
	assert st.text('edit') == 'local ñá' && st.focused_id() == 'edit'
	assert native_control_selected_range(field) == macos.range(2, 3)
	assert st.enter_focus_scope('scope') && st.focused_id() == 'composite'
	assert st.focus_next() && st.focused_id() == 'composite'
	assert st.leave_focus_scope() && st.focused_id() == 'edit'
	assert native_control_selected_range(field) == macos.range(2, 3)
	assert st.focus_next() && st.focused_id() == 'press'
	native_focus_events = []ElementEvent{}
	assert st.handle_focus_key(KeyEvent{code: .enter}, false)
	assert st.handle_focus_key(KeyEvent{code: .enter}, true)
	assert st.handle_focus_key(KeyEvent{code: .space}, false)
	// Events name the window they happened in; compare what happened.
	assert native_focus_events.map('${it.kind}:${it.id}') == ['click:press', 'click:press']
	assert native_focus_events.all(it.window == st)
	st.focus('below')
	assert st.focused_id() == 'below' && st.scroll_offset('pane') > 400
	assert (st.semantic_node('edit') or { panic('missing semantics') }).value == 'local ñá'
	// A targeted reconciliation must retain disabled ancestry in its native
	// pointer registrations as well as in the shared focus policy.
	mut children := root.children.clone()
	children[2] = Element{...children[2], enabled: false}
	st.render_root(Element{...root, children: children})
	st.refresh_element('composite', root.children[2].children[0])
	assert (st.semantic_node('composite') or { panic('missing composite') }).state.disabled
	assert !st.perform_semantic_action('composite', .activate)
	assert !st.navigation.can_focus('composite')
	composite := st.views['composite'] or { panic('missing native composite') }
	assert u64(voidptr(composite)) !in st.pointer_callbacks
	st.render_root(screen(0xffffff, [scroll('outer', rect(10, 10, 100, 100), 0xffffff, [
		scroll('inner', rect(0, 0, 80, 300), 0xffffff, [Element{kind: .button, id: 'nested-below', text: 'Nested', frame: rect(0, 250, 60, 30)}]),
	])]))
	st.focus('nested-below')
	assert st.focused_id() == 'nested-below'
	assert st.scroll_offset('inner') == 0 && st.scroll_offset('outer') == 180
}

// Real NSTextInputClient marked text and injected Cocoa sendEvent: commands;
// this does not exercise a physical OS input method or candidate window.
fn test_appkit_marked_text_tab_uses_native_editor_without_default_focus_navigation() {
	pool := macos.autorelease_pool_new()
	defer { macos.release(pool) }
	native_current_app()
	ensure_runtime_classes()
	mut st := appkit_fixture_window('Marked text fixture', 380, 260)
	defer {
		st.close_fixture()
	}
	mut failures := []string{}
	native_focus_consume_in_observer = false
	for kind in [Kind.text_field, .text_area] {
		for modifiers in [u64(0), u64(0x20000)] {
			root := screen(0xffffff, [Element{kind: .view, id: 'scope', focus_scope: true, children: [
				Element{kind: .button, id: 'before', text: 'Before', frame: rect(10, 10, 100, 30)},
				Element{kind: kind, id: 'edit', text: 'café ñ', frame: rect(10, 50, 180, 80)},
				Element{kind: .button, id: 'after', text: 'After', frame: rect(10, 150, 100, 30)},
			]}])
			st.render_root(root)
			assert st.enter_focus_scope('scope')
			st.focus('edit')
			st.set_text('edit', 'borrador café ñ')
			editor := macos.msg_id(st.window, 'firstResponder')
			assert macos.responds_to(editor, 'hasMarkedText')
			if kind == .text_field {
				field := st.views['edit'] or { panic('missing field') }
				assert editor == macos.msg_id(field, 'currentEditor')
				assert editor != field
			}
			macos.msg_void_range(editor, 'setSelectedRange:', macos.range(9, 4))
			C.ui2_focus_test_mark_text(editor, macos.nsstring('cañé'), 1, 2)
			assert macos.msg_bool(editor, 'hasMarkedText')
			assert st.text('edit') == 'borrador cañé ñ'
			draft := st.text('edit')
			selection := macos.msg_range(editor, 'selectedRange')
			st.render_root(Element{...root, box: BoxStyle{bg: 0xeeeeee}})
			assert macos.msg_bool(editor, 'hasMarkedText')
			assert st.text('edit') == draft && macos.msg_range(editor, 'selectedRange') == selection
			// Record Cocoa's own behavior on exactly the same real editor/draft.
			// The reference goes straight to NSWindow's implementation.
			native_focus_timestamp += 1
			reference := C.ui2_focus_test_key_event(st.window, 10, 0x30, macos.nsstring('\t'), modifiers, native_focus_timestamp, false)
			C.ui2_macos_window_send_event(st.window, reference)
			expected_text := st.text('edit')
			expected_selection := macos.msg_range(editor, 'selectedRange')
			expected_marked := macos.msg_bool(editor, 'hasMarkedText')
			assert st.focused_id() == 'edit'
			macos.msg_void(editor, 'unmarkText')
			st.set_text('edit', 'borrador café ñ')
			macos.msg_void_range(editor, 'setSelectedRange:', macos.range(9, 4))
			C.ui2_focus_test_mark_text(editor, macos.nsstring('cañé'), 1, 2)
			assert st.text('edit') == draft && macos.msg_range(editor, 'selectedRange') == selection
			native_focus_keys = []KeyEvent{}
			st.on_key_event(native_focus_key_observer)
			send_native_focus_key(st, 0x30, '\t', false, 10, modifiers)
			assert native_focus_keys.len == 1 && native_focus_keys[0].code == .tab
			unchanged_route := st.focused_id() == 'edit' && st.active_focus_scope() == 'scope'
			native_result := st.text('edit') == expected_text && macos.msg_range(editor, 'selectedRange') == expected_selection
				&& macos.msg_bool(editor, 'hasMarkedText') == expected_marked
			eprintln('marked Cocoa kind=${kind} shift=${modifiers != 0} retained_focus=${unchanged_route} native_text_selection=${native_result}')
			if !unchanged_route || !native_result { failures << '${kind}/${modifiers}' }
			// Explicit application handlers may still consume a composition key.
			st.focus('edit')
			macos.msg_void(editor, 'unmarkText')
			st.set_text('edit', 'borrador café ñ')
			macos.msg_void_range(editor, 'setSelectedRange:', macos.range(9, 4))
			C.ui2_focus_test_mark_text(editor, macos.nsstring('cañé'), 1, 2)
			native_marked_legacy_keys = []string{}
			native_marked_consume = false
			st.on_key(native_marked_key_handler)
			send_native_focus_key(st, 0x30, '\t', false, 10, modifiers)
			assert native_marked_legacy_keys.len == 1
			assert st.text('edit') == expected_text && macos.msg_range(editor, 'selectedRange') == expected_selection
			assert macos.msg_bool(editor, 'hasMarkedText') == expected_marked && st.focused_id() == 'edit'
			macos.msg_void(editor, 'unmarkText')
			st.set_text('edit', 'borrador café ñ')
			macos.msg_void_range(editor, 'setSelectedRange:', macos.range(9, 4))
			C.ui2_focus_test_mark_text(editor, macos.nsstring('cañé'), 1, 2)
			native_marked_legacy_keys = []string{}
			native_marked_consume = true
			send_native_focus_key(st, 0x30, '\t', false, 10, modifiers)
			assert native_marked_legacy_keys.len == 1
			assert native_marked_legacy_keys[0] == (if kind == .text_area { 'text:edit:' } else { '' }) + if modifiers == 0 { 'tab' } else { 'shift+tab' }
			assert st.text('edit') == draft && macos.msg_range(editor, 'selectedRange') == selection
			assert macos.msg_bool(editor, 'hasMarkedText') && st.focused_id() == 'edit'
			st.on_key(unsafe { nil })
			native_focus_consume_in_observer = true
			send_native_focus_key(st, 0x30, '\t', false, 10, modifiers)
			native_focus_consume_in_observer = false
			assert st.text('edit') == draft && macos.msg_range(editor, 'selectedRange') == selection
			assert macos.msg_bool(editor, 'hasMarkedText') && st.focused_id() == 'edit'
			macos.msg_void(editor, 'unmarkText')
			assert !macos.msg_bool(editor, 'hasMarkedText')
			send_native_focus_key(st, 0x30, '\t', false, 11, modifiers)
			send_native_focus_key(st, 0x30, '\t', false, 10, modifiers)
			assert st.focused_id() == if modifiers == 0 { 'after' } else { 'before' }
			assert native_focus_keys.len == 5
			st.render_root(screen(0xffffff, []))
		}
	}
	assert failures.len == 0, failures.str()
}

}
