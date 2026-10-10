// vtest build: macos && !ui2_custom_rendering?
// vfmt off
module ui2

$if !ui2_custom_rendering ? {
import macos

fn anonymous_appkit_semantic(path string) SemanticNode {
	for node in semantic_tree() { if node.path == path { return node } }
	panic('missing anonymous semantics at ${path}')
}

fn anonymous_appkit_controls() Element {
	return scroll('', rect(0, 0, 300, 470), 0xffffff, [
		Element{kind: .checkbox, key: 'check', text: 'Anonymous choice', frame: rect(0, 0, 180, 30)},
		Element{kind: .switch_control, key: 'switch', text: 'Switch', frame: rect(0, 35, 180, 30)},
		Element{kind: .toggle_button, key: 'toggle', text: 'Toggle', frame: rect(0, 70, 180, 30)},
		Element{kind: .text_field, key: 'field', text: 'declared', frame: rect(0, 105, 180, 30)},
		Element{kind: .text_area, key: 'area', text: 'declared area', frame: rect(0, 140, 180, 70)},
		Element{kind: .text_area, key: 'direct', text: 'declared direct', disable_scroll: true, frame: rect(0, 215, 180, 70)},
		Element{kind: .dropdown, key: 'choice', text: 'A', menu: [MenuEntry{title: 'A'}, MenuEntry{title: 'B'}], frame: rect(0, 290, 180, 30)},
		Element{kind: .slider, key: 'slider', value: 2.5, min_value: 0, max_value: 10, step: 0.5, frame: rect(0, 325, 180, 30)},
		Element{kind: .text_field, key: 'secret', text: 'secret', secure: true, frame: rect(0, 360, 180, 30)},
		Element{kind: .checkbox, key: 'override', accessibility_value: 'annotation', frame: rect(0, 395, 180, 30)},
	])
}

fn test_appkit_anonymous_semantics_reads_native_controls_through_nested_scroll_paths() {
	pool := macos.autorelease_pool_new()
	defer { macos.release(pool) }
	native_current_app()
	ensure_runtime_classes()
	mut st := state()
	previous := *st
	unsafe { *st = RuntimeState{} }
	st.window = native_new_window(native_rect(0, 0, 340, 500), 'Anonymous native semantic fixture')
	st.root_view = native_new_flipped_view(native_rect(0, 0, 340, 500), BoxStyle{})
	st.button_handler = native_new_object('UI2ButtonHandler')
	native_set_content_view(st.window, st.root_view)
	defer {
		render_root(screen(0xffffff, []))
		macos.msg_void(st.window, 'close')
		macos.release(st.window)
		macos.release(st.root_view)
		macos.release(st.button_handler)
		unsafe { *st = previous }
	}
	root := screen(0xffffff, [anonymous_appkit_controls()])
	render_root(root)
	for key in ['check', 'switch', 'toggle', 'override'] {
		native := st.nodes['i:0/document/k:' + key.bytes().hex()] or { panic('missing native checkbox') }
		macos.msg_void1(native, 'performClick:', native_nil_view())
		assert macos.msg_i64(native, 'state') == 1
		node := anonymous_appkit_semantic('root/i:0/k:' + key.bytes().hex())
		assert node.id == '' && node.state.checked
		assert node.state.selected == (key == 'toggle')
		assert node.value == if key == 'override' { 'annotation' } else { 'checked' }
	}
	field := st.nodes['i:0/document/k:6669656c64'] or { panic('missing anonymous field') }
	native_set_text(field, 'borrador café ñ')
	assert anonymous_appkit_semantic('root/i:0/k:6669656c64').value == 'borrador café ñ'
	for key in ['area', 'direct'] {
		native := st.nodes['i:0/document/k:' + key.bytes().hex()] or { panic('missing anonymous area') }
		tv := text_area_text_view(native, key == 'direct')
		macos.msg_void1(tv, 'setString:', macos.nsstring('área ñ ' + key))
		assert anonymous_appkit_semantic('root/i:0/k:' + key.bytes().hex()).value == 'área ñ ' + key
	}
	choice := st.nodes['i:0/document/k:63686f696365'] or { panic('missing anonymous dropdown') }
	native_select_dropdown_item(choice, 'B')
	assert anonymous_appkit_semantic('root/i:0/k:63686f696365').value == 'B'
	slider_native := st.nodes['i:0/document/k:736c69646572'] or { panic('missing anonymous slider') }
	macos.msg_void_f64(slider_native, 'setDoubleValue:', 7.5)
	assert anonymous_appkit_semantic('root/i:0/k:736c69646572').value == '7.5'
	secret := st.nodes['i:0/document/k:736563726574'] or { panic('missing anonymous secure field') }
	native_set_text(secret, 'private local ñ')
	secure := anonymous_appkit_semantic('root/i:0/k:736563726574')
	assert secure.value == '' && secure.state.secure

	// An unkeyed Scroll gets a new mounted path after sibling insertion. The
	// live snapshot must resolve its new native handles, never the old paths.
	render_root(screen(0xffffff, [Element{kind: .label, text: 'Inserted'}, root.children[0]]))
	new_field := st.nodes['i:1/document/k:6669656c64'] or { panic('missing reordered field') }
	native_set_text(new_field, 'reordered ñ')
	assert anonymous_appkit_semantic('root/i:1/k:6669656c64').value == 'reordered ñ'
	assert semantic_tree().filter(it.path == 'root/i:0/k:6669656c64').len == 0
	new_check := st.nodes['i:1/document/k:636865636b'] or { panic('missing reordered checkbox') }
	macos.msg_void1(new_check, 'performClick:', native_nil_view())
	assert anonymous_appkit_semantic('root/i:1/k:636865636b').state.checked == (macos.msg_i64(new_check, 'state') != 0)
	render_root(screen(0xffffff, [Element{kind: .label, text: 'Remaining'}]))
	assert semantic_tree().filter(it.path == 'root/i:1/k:636865636b').len == 0
}
}
