// vfmt off
@[has_globals]
module ui2

$if !ui2_custom_rendering ? {
import macos

#include "@VMODROOT/appkit/focus_events_darwin_test.h"
fn C.ui2_focus_test_key_event(window voidptr, event_type u64, code u16, characters voidptr, modifiers u64, timestamp f64, repeated bool) voidptr

__global native_focus_timestamp f64
__global native_focus_keys = []KeyEvent{}
__global native_focus_resign_in_callback bool
__global native_focus_resign_in_observer bool
fn native_focus_key_observer(event KeyEvent) {
	native_focus_keys << event
	if native_focus_resign_in_observer { macos.msg_void(state().window, 'resignKeyWindow') }
}
fn native_focus_editor_event(event ElementEvent) {
	native_focus_events << event
	if event.id == 'press' {
		focus('edit')
		if native_focus_resign_in_callback { macos.msg_void(state().window, 'resignKeyWindow') }
	}
}

fn send_native_focus_key(code u16, characters string, repeated bool, event_type u64, modifiers u64) {
	native_focus_timestamp += 1
	event := C.ui2_focus_test_key_event(state().window, event_type, code, macos.nsstring(characters), modifiers, native_focus_timestamp, repeated)
	assert event != unsafe { nil }
	macos.msg_void1(state().window, 'sendEvent:', event)
}

__global native_focus_events = []ElementEvent{}
fn native_focus_event(event ElementEvent) { native_focus_events << event }

fn test_appkit_consumed_activation_repeats_preserve_new_native_editor_until_release() {
	pool := macos.autorelease_pool_new()
	defer { macos.release(pool) }
	native_current_app()
	ensure_runtime_classes()
	mut st := state()
	previous := *st
	unsafe { *st = RuntimeState{} }
	st.window = native_new_window(native_rect(0, 0, 380, 260), 'Held activation fixture')
	st.root_view = native_new_flipped_view(native_rect(0, 0, 380, 260), BoxStyle{})
	st.button_handler = native_new_object('UI2ButtonHandler')
	native_set_content_view(st.window, st.root_view)
	macos.msg_void1(st.window, 'makeKeyAndOrderFront:', st.window)
	defer {
		macos.msg_void(st.window, 'close')
		macos.release(st.window)
		macos.release(st.root_view)
		macos.release(st.button_handler)
		unsafe { *st = previous }
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
			render_root(root)
			set_text('edit', 'café ñ')
			focus('press')
			native_focus_events = []ElementEvent{}
			native_focus_keys = []KeyEvent{}
			on_key_event(native_focus_key_observer)
			send_native_focus_key(code, characters, false, 10, 0)
			assert focused_id() == 'edit'
			editor := macos.msg_id(st.window, 'firstResponder')
			macos.msg_void_range(editor, 'setSelectedRange:', macos.range(2, 3))
			before := text('edit')
			selection := macos.msg_range(editor, 'selectedRange')
			// Refresh retains the editor and may remove the activation source.
			render_root(Element{...root, children: [root.children[0]]})
			for _ in 0 .. 3 { send_native_focus_key(code, characters, true, 10, 0) }
			// Ownership follows keyCode even when modifiers change while held.
			for modifiers in [u64(0x20000), u64(0x40000), u64(0x80000), u64(0x100000)] {
				send_native_focus_key(code, characters, true, 10, modifiers)
			}
			if code == 0x4c {
				send_native_focus_key(0x24, '\r', false, 11, 0)
				send_native_focus_key(code, characters, true, 10, 0)
			}
			unchanged := text('edit') == before && macos.msg_range(editor, 'selectedRange') == selection
			activations := native_focus_events.filter(it.kind == .tap).len
			assert native_focus_events.filter(it.kind == .submit).len == 0
			eprintln('native held kind=${kind} code=${code} activations=${activations} unchanged=${unchanged} text=${text('edit').bytes()}')
			if !unchanged || activations != 1 { failures << '${kind}/${code}' }
			expected_keys := if code == 0x4c { 9 } else { 8 }
			if native_focus_keys.filter(it.code == appkit_key_code(code)).len != expected_keys { failures << 'observers:${kind}/${code}' }
			// Unrelated Unicode input still reaches the editor while owned.
			send_native_focus_key(0x2d, 'ñ', false, 10, 0)
			assert text('edit') == 'caññ'
			assert native_focus_keys.filter(it.code == .n).len == 1
			unicode_text := text('edit')
			unicode_selection := macos.msg_range(editor, 'selectedRange')
			send_native_focus_key(code, characters, true, 10, 0)
			assert text('edit') == unicode_text && macos.msg_range(editor, 'selectedRange') == unicode_selection
			send_native_focus_key(code, characters, false, 11, 0)
			send_native_focus_key(0x31, ' ', false, 10, 0)
			send_native_focus_key(0x31, ' ', true, 10, 0)
			assert text('edit') == 'cañ  ñ'
			if kind == .text_area {
				value := text('edit')
				send_native_focus_key(code, characters, false, 10, 0)
				assert text('edit') != value
			} else {
				send_native_focus_key(0x24, '\r', false, 10, 0)
				assert native_focus_events.filter(it.kind == .submit).len == 1
			}
		}
	}
	assert failures.len == 0, failures.str()
	// Repeat navigation remains per-event, unlike a consumed activation press.
	render_root(screen(0xffffff, [
		Element{kind: .text_field, id: 'edit', text: 'ordinary', frame: rect(10, 10, 180, 30)},
		Element{kind: .button, id: 'press', text: 'Left', on_event: native_focus_editor_event, frame: rect(10, 60, 100, 30)},
		Element{kind: .button, id: 'right', text: 'Right', on_event: native_focus_event, frame: rect(130, 60, 100, 30)},
	]))
	focus('edit')
	native_focus_keys = []KeyEvent{}
	send_native_focus_key(0x30, '\t', false, 10, 0)
	assert focused_id() == 'press'
	send_native_focus_key(0x30, '\t', true, 10, 0)
	assert focused_id() == 'right'
	send_native_focus_key(0x30, '\t', false, 11, 0)
	send_native_focus_key(0x7b, '\uf702', false, 10, 0)
	assert focused_id() == 'press'
	send_native_focus_key(0x7c, '\uf703', true, 10, 0)
	assert focused_id() == 'right'
	send_native_focus_key(0x30, '\t', false, 10, 0x20000)
	assert focused_id() == 'press' && st.activation_keys.len == 0
	assert native_focus_keys.len == 5
	// Resign during the synchronous action must not be undone by a late latch.
	render_root(screen(0xffffff, [
		Element{kind: .text_area, id: 'edit', text: 'local ñ', frame: rect(10, 10, 180, 80)},
		Element{kind: .button, id: 'press', text: 'Press', on_event: native_focus_editor_event, frame: rect(10, 110, 100, 30)},
	]))
	native_focus_resign_in_callback = true
	focus('press')
	send_native_focus_key(0x31, ' ', false, 10, 0)
	assert st.activation_keys.len == 0
	native_focus_resign_in_callback = false
	// Observers can release the host too; do not claim a press afterwards.
	focus('press')
	native_focus_resign_in_observer = true
	taps_before := native_focus_events.filter(it.kind == .tap).len
	send_native_focus_key(0x31, ' ', false, 10, 0)
	assert native_focus_events.filter(it.kind == .tap).len == taps_before
	assert st.activation_keys.len == 0
	native_focus_resign_in_observer = false
	focus('press')
	send_native_focus_key(0x31, ' ', false, 10, 0)
	assert st.activation_keys.len == 1
	delegate := native_new_object('UI2AppDelegate')
	macos.msg_void1(delegate, 'applicationDidResignActive:', unsafe { nil })
	macos.release(delegate)
	assert st.activation_keys.len == 0
	value := text('edit')
	send_native_focus_key(0x31, ' ', true, 10, 0)
	assert text('edit') != value
	focus('press')
	send_native_focus_key(0x4c, '\u0003', false, 10, 0)
	assert st.activation_keys.len == 1
	macos.msg_void(st.window, 'close')
	assert st.activation_keys.len == 0
}

fn test_appkit_navigation_preserves_native_editor_selection_and_reveals_offscreen_controls() {
	pool := macos.autorelease_pool_new()
	defer { macos.release(pool) }
	native_current_app()
	ensure_runtime_classes()
	mut st := state()
	previous := *st
	unsafe { *st = RuntimeState{} }
	st.window = native_new_window(native_rect(0, 0, 380, 260), 'Focus fixture')
	st.root_view = native_new_flipped_view(native_rect(0, 0, 380, 260), BoxStyle{})
	st.button_handler = native_new_object('UI2ButtonHandler')
	native_set_content_view(st.window, st.root_view)
	defer {
		macos.msg_void(st.window, 'close')
		macos.release(st.window)
		macos.release(st.root_view)
		macos.release(st.button_handler)
		unsafe { *st = previous }
	}
	root := screen(0xffffff, [
		Element{kind: .text_field, id: 'edit', text: 'café ñ', frame: rect(10, 10, 180, 30)},
		Element{kind: .button, id: 'press', text: 'Press', on_event: native_focus_event, frame: rect(10, 50, 100, 30)},
		Element{kind: .view, id: 'scope', focus_scope: true, frame: rect(210, 10, 150, 100), children: [
			Element{kind: .view, id: 'composite', button_behavior: true, on_event: native_focus_event, frame: rect(0, 0, 100, 30)},
		]},
		scroll('pane', rect(10, 110, 180, 80), 0xffffff, [Element{kind: .button, id: 'below', text: 'Below', on_event: native_focus_event, frame: rect(0, 500, 100, 30)}]),
	])
	render_root(root)
	focus('edit')
	assert focused_id() == 'edit'
	field := st.views['edit'] or { panic('missing field') }
	native_set_text(field, 'local ñá')
	native_restore_control_selection(field, 2, 3)
	assert native_control_selected_range(field) == macos.range(2, 3)
	render_root(Element{...root, box: BoxStyle{bg: 0xeeeeee}})
	assert text('edit') == 'local ñá' && focused_id() == 'edit'
	assert native_control_selected_range(field) == macos.range(2, 3)
	assert enter_focus_scope('scope') && focused_id() == 'composite'
	assert focus_next() && focused_id() == 'composite'
	assert leave_focus_scope() && focused_id() == 'edit'
	assert native_control_selected_range(field) == macos.range(2, 3)
	assert focus_next() && focused_id() == 'press'
	native_focus_events = []ElementEvent{}
	assert handle_focus_key(KeyEvent{code: .enter}, false)
	assert handle_focus_key(KeyEvent{code: .enter}, true)
	assert handle_focus_key(KeyEvent{code: .space}, false)
	assert native_focus_events == [ElementEvent{kind: .tap, id: 'press'}, ElementEvent{kind: .tap, id: 'press'}]
	focus('below')
	assert focused_id() == 'below' && scroll_offset('pane') > 400
	assert (semantic_node('edit') or { panic('missing semantics') }).value == 'local ñá'
	// A targeted reconciliation must retain disabled ancestry in its native
	// pointer registrations as well as in the shared focus policy.
	mut children := root.children.clone()
	children[2] = Element{...children[2], enabled: false}
	render_root(Element{...root, children: children})
	refresh_element('composite', root.children[2].children[0])
	assert (semantic_node('composite') or { panic('missing composite') }).state.disabled
	assert !perform_semantic_action('composite', .activate)
	assert !st.navigation.can_focus('composite')
	composite := st.views['composite'] or { panic('missing native composite') }
	assert u64(voidptr(composite)) !in st.pointer_callbacks
	render_root(screen(0xffffff, [scroll('outer', rect(10, 10, 100, 100), 0xffffff, [
		scroll('inner', rect(0, 0, 80, 300), 0xffffff, [Element{kind: .button, id: 'nested-below', text: 'Nested', frame: rect(0, 250, 60, 30)}]),
	])]))
	focus('nested-below')
	assert focused_id() == 'nested-below'
	assert scroll_offset('inner') == 0 && scroll_offset('outer') == 180
}
}
