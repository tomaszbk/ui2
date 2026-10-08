// vfmt off
@[has_globals]
module ui2

$if !ui2_custom_rendering ? {
import macos

__global native_focus_events = []ElementEvent{}
fn native_focus_event(event ElementEvent) { native_focus_events << event }

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
