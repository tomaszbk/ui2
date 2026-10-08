// vfmt off
module ui2

$if !ui2_custom_rendering ? {
import macos

fn scroll_semantic_window() RuntimeState {
	native_current_app()
	ensure_runtime_classes()
	mut st := state()
	previous := *st
	unsafe { *st = RuntimeState{} }
	st.window = native_new_window(native_rect(0, 0, 400, 300), 'Scroll and window semantics')
	st.root_view = native_new_flipped_view(native_rect(0, 0, 400, 300), BoxStyle{})
	st.button_handler = native_new_object('UI2ButtonHandler')
	native_set_content_view(st.window, st.root_view)
	macos.msg_void1(st.window, 'makeKeyAndOrderFront:', st.window)
	return previous
}

fn close_scroll_semantic_window(previous RuntimeState) {
	mut st := state()
	render_root(screen(0xffffff, []))
	macos.msg_void(st.window, 'close')
	macos.release(st.window)
	macos.release(st.root_view)
	macos.release(st.button_handler)
	unsafe { *st = previous }
}

fn test_appkit_explicit_scroll_focus_retains_identity_and_child_editor_ownership() {
	pool := macos.autorelease_pool_new()
	defer { macos.release(pool) }
	previous := scroll_semantic_window()
	defer { close_scroll_semantic_window(previous) }
	mut st := state()
	pane := Element{kind: .scroll, id: 'pane', focus_policy: .focusable,
		frame: rect(10, 50, 240, 180), children: [
			Element{kind: .text_field, id: 'field', text: 'declarado ñ', tab_index: -1, frame: rect(0, 0, 180, 30)},
			Element{kind: .text_area, id: 'area', text: 'área declarada', tab_index: -1, frame: rect(0, 40, 180, 60)},
			Element{kind: .button, id: 'child', text: 'Child', tab_index: -1, frame: rect(0, 110, 100, 30)},
		]}
	root := screen(0xffffff, [
		Element{kind: .button, id: 'a', text: 'A', frame: rect(10, 10, 100, 30)}, pane,
		Element{kind: .button, id: 'b', text: 'B', frame: rect(10, 250, 100, 30)},
	])
	render_root(root)
	focus('a')
	assert focused_id() == 'a'
	forward := focus_next()
	eprintln('scroll forward=${forward} id=${focused_id()}')
	assert forward && focused_id() == 'pane'
	native := st.views['pane'] or { panic('missing Scroll') }
	assert macos.msg_id(st.window, 'firstResponder') == macos.msg_id(native, 'documentView')
	assert (semantic_node('pane') or { panic('missing Scroll semantics') }).state.focused
	assert focus_next() && focused_id() == 'b'
	assert focus_previous() && focused_id() == 'pane'
	assert focus_previous() && focused_id() == 'a'
	focus('pane')
	assert focused_id() == 'pane'
	focus('b')
	assert perform_semantic_action('pane', .focus) && focused_id() == 'pane'
	for id in ['field', 'area', 'child'] {
		focus(id)
		assert focused_id() == id, 'Scroll must not claim its child responder'
	}
	focus('field')
	field := st.views['field'] or { panic('missing child field') }
	native_set_text(field, 'borrador café ñ')
	native_restore_control_selection(field, 2, 3)
	focus('pane')
	focus('field')
	assert text('field') == 'borrador café ñ'
	assert native_control_selected_range(field) == macos.range(2, 3)
	focus('area')
	area := text_area_document_view('area') or { panic('missing child text view') }
	macos.msg_void1(area, 'setString:', macos.nsstring('área local ñ'))
	text_area_set_selection('area', 1, 4)
	focus('pane')
	render_root(Element{...root, box: BoxStyle{bg: 0xeeeeee}})
	assert focused_id() == 'pane'
	focus('area')
	assert focused_id() == 'area' && text('area') == 'área local ñ'
	assert native_text_view_selected_range(area) == macos.range(1, 4)

	// The explicit Scroll is also the scope's first target; leaving restores
	// the real child editor and its selection, rather than the Scroll ancestor.
	scoped := screen(0xffffff, [Element{kind: .view, id: 'scope', focus_scope: true,
		frame: rect(0, 0, 400, 300), children: [pane, root.children[2]]}, root.children[0]])
	render_root(scoped)
	focus('a')
	assert enter_focus_scope('scope') && focused_id() == 'pane'
	assert focus_next() && focused_id() == 'b'
	assert focus_next() && focused_id() == 'pane'
	assert focus_previous() && focused_id() == 'b'
	assert perform_semantic_action('pane', .focus)
	assert leave_focus_scope() && focused_id() == 'a'
	focus('area')
	text_area_set_selection('area', 1, 3)
	assert enter_focus_scope('scope') && focused_id() == 'pane'
	assert leave_focus_scope() && focused_id() == 'area'
	assert text_area_selection_length('area') == 3
	assert !perform_semantic_action('scope', .focus)

	focus('pane')
	render_root(screen(0xffffff, [root.children[0], Element{...pane, enabled: false}, root.children[2]]))
	assert focused_id() != 'pane'
	focus('a')
	assert !perform_semantic_action('pane', .focus)
	focus('pane')
	assert focused_id() == 'a'
	assert focus_next() && focused_id() == 'b'
	render_root(root)
	focus('pane')
	render_root(screen(0xffffff, [root.children[0], root.children[2]]))
	assert focused_id() != 'pane' && !perform_semantic_action('pane', .focus)
	assert semantic_tree().filter(it.id == 'pane').len == 0
}

fn test_appkit_mounted_screen_semantics_use_current_logical_viewport_without_rebuild() {
	pool := macos.autorelease_pool_new()
	defer { macos.release(pool) }
	previous := scroll_semantic_window()
	defer { close_scroll_semantic_window(previous) }
	mut st := state()
	st.build_screen = fn () Element { panic('semantic read must not rebuild') }
	root := screen(0xffffff, [Element{kind: .view, id: 'panel', frame: rect(12.5, 9.25, 175, 80),
		children: [Element{kind: .label, id: 'caption', frame: rect(3.25, 4.5, 87.5, 10.25)}]}])
	render_root(root)
	debug := st.refresh_debug
	snapshot := semantic_tree()
	eprintln('mounted root=${snapshot[0].frame}')
	assert snapshot[0].role == 'window' && snapshot[0].frame == rect(0, 0, 400, 300)
	assert (semantic_node('panel') or { panic('missing panel') }).frame == rect(12.5, 9.25, 175, 80)
	assert (semantic_node('caption') or { panic('missing caption') }).frame == rect(15.75, 13.75, 87.5, 10.25)
	assert st.navigation.root.frame == root.frame && st.refresh_debug == debug
	macos.msg_void_point(st.window, 'setContentSize:', macos.point(520, 360))
	assert semantic_tree()[0].frame == rect(0, 0, 520, 360)
	assert st.navigation.root.frame == root.frame && st.refresh_debug == debug
	// A declared subtree is not a mounted screen viewport.
	st.navigation.root = root.children[0]
	assert semantic_tree()[0].frame == root.children[0].frame
	assert (semantic_node('caption') or { panic('missing subtree caption') }).frame == rect(15.75, 13.75, 87.5, 10.25)
}
}
