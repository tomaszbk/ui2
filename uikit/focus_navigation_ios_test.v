@[has_globals]
module ui2

import macos

#include "@VMODROOT/uikit/focus_events_ios_test.h"
fn C.ui2_ios_focus_test_visible_in_scroll(target voidptr, pane voidptr) bool
fn C.ui2_ios_focus_test_select(view voidptr, location i64, length i64)
fn C.ui2_ios_focus_test_selection_is(view voidptr, location i64, length i64) bool

__global ios_semantic_events = []ElementEvent{}
__global ios_semantic_handlers = []string{}

fn ios_semantic_event(event ElementEvent) {
	mut st := event.window
	// Kept without their window, so the tests compare them by value.
	ios_semantic_events << ElementEvent{ ...event, window: unsafe { nil } }
	ios_semantic_handlers << 'current'
	if event.kind == .change && event.id != 'dropdown' {
		node := st.semantic_node(event.id) or { panic('callback lost its mounted control') }
		assert node.state.checked == event.checked
		assert node.value == if event.checked { 'checked' } else { 'unchecked' }
		if event.id.starts_with('toggle') { assert node.state.selected == event.checked }
	}
}

fn ios_semantic_old_event(event ElementEvent) {
	ios_semantic_events << ElementEvent{ ...event, window: unsafe { nil } }
	ios_semantic_handlers << 'captured'
}

fn begin_ios_semantic_fixture() &Window {
	ensure_runtime_classes()
	mut st := &Window{}
	mut host := ios_host()
	host.window = st
	st.root_view = macos.msg_id_rect(macos.alloc('UIView'), 'initWithFrame:', macos.rect(0, 0, 320, 480))
	st.root_vc = macos.msg_id(macos.alloc('UIViewController'), 'init')
	macos.msg_void1(st.root_vc, 'setView:', st.root_view)
	st.window = macos.msg_id_rect(macos.alloc('UIWindow'), 'initWithFrame:', macos.rect(0, 0, 320, 480))
	macos.msg_void1(st.window, 'setRootViewController:', st.root_vc)
	macos.msg_void(st.window, 'makeKeyAndVisible')
	st.button_handler = macos.msg_id(macos.alloc('VuiButtonHandler'), 'init')
	st.ios_navigation = &FocusManager{}
	ios_semantic_events = []ElementEvent{}
	ios_semantic_handlers = []string{}
	return st
}

fn end_ios_semantic_fixture(mut st Window) {
	st.render_root(screen(0xffffff, []))
	macos.msg_void_bool(st.window, 'setHidden:', true)
	macos.release(st.window)
	macos.release(st.root_vc)
	macos.release(st.root_view)
	macos.release(st.button_handler)
	st.window = View(unsafe { nil })
	st.root_vc = View(unsafe { nil })
	st.root_view = View(unsafe { nil })
	st.button_handler = View(unsafe { nil })
	st.ios_navigation = &FocusManager{}
	mut host := ios_host()
	host.window = unsafe { nil }
}

fn test_ios_public_semantic_toggle_and_checkbox_commit_once_with_optional_handler() {
	mut st := begin_ios_semantic_fixture()
	defer { end_ios_semantic_fixture(mut st) }
	for kind in [Kind.toggle_button, .checkbox, .switch_control] {
		for has_handler in [true, false] {
			id := if kind == .toggle_button { 'toggle' } else { 'check' }
			callback := if has_handler { ElementCallback(ios_semantic_event) } else { ElementCallback(unsafe { nil }) }
			st.render_root(screen(0xffffff, [Element{ kind: kind, id: id, text: 'Choice', on_event: callback, frame: rect(0, 0, 140, 32) }]))
			ios_semantic_events = []ElementEvent{}
			for expected in [true, false] {
				assert st.perform_semantic_action(id, .activate)
				node := st.semantic_node(id) or { panic('missing semantic control') }
				assert node.state.checked == expected
				assert node.state.selected == (kind == .toggle_button && expected)
				assert node.value == if expected { 'checked' } else { 'unchecked' }
			}
			assert ios_semantic_events == if has_handler {
				[ElementEvent{ kind: .change, id: id, checked: true }, ElementEvent{ kind: .change, id: id, checked: false }]
			} else { []ElementEvent{} }
			st.render_root(screen(0xffffff, []))
		}
	}
}

fn test_ios_public_semantic_toggle_groups_keep_or_release_selection_by_policy() {
	mut st := begin_ios_semantic_fixture()
	defer { end_ios_semantic_fixture(mut st) }
	for allow_empty in [true, false] {
		for has_handler in [true, false] {
			callback := if has_handler { ElementCallback(ios_semantic_event) } else { ElementCallback(unsafe { nil }) }
			st.render_root(screen(0xffffff, [
				Element{ kind: .toggle_button, id: 'toggle_a', text: 'A', checked: true, toggle: &ToggleSpec{ group: 'group', allow_no_selection: allow_empty }, on_event: callback, frame: rect(0, 0, 100, 32) },
				Element{ kind: .toggle_button, id: 'toggle_b', text: 'B', toggle: &ToggleSpec{ group: 'group', allow_no_selection: allow_empty }, on_event: callback, frame: rect(0, 40, 100, 32) },
			]))
			ios_semantic_events = []ElementEvent{}
			assert st.perform_semantic_action('toggle_a', .activate)
			assert st.toggle_button_pressed('toggle_a') == !allow_empty
			assert !st.toggle_button_pressed('toggle_b')
			assert st.perform_semantic_action('toggle_b', .activate)
			assert !st.toggle_button_pressed('toggle_a') && st.toggle_button_pressed('toggle_b')
			assert st.perform_semantic_action('toggle_b', .activate)
			assert st.toggle_button_pressed('toggle_b') == !allow_empty
			assert ios_semantic_events == if has_handler {
				[ElementEvent{ kind: .change, id: 'toggle_a', checked: !allow_empty },
				 ElementEvent{ kind: .change, id: 'toggle_b', checked: true },
				 ElementEvent{ kind: .change, id: 'toggle_b', checked: !allow_empty }]
			} else { []ElementEvent{} }
			st.render_root(screen(0xffffff, []))
		}
	}
}

fn test_ios_semantics_uses_current_callback_and_pointer_release_keeps_captured_callback() {
	mut st := begin_ios_semantic_fixture()
	defer { end_ios_semantic_fixture(mut st) }
	old := Element{ kind: .checkbox, id: 'check', text: 'Choice', on_event: ios_semantic_old_event, frame: rect(0, 0, 140, 32) }
	st.render_root(screen(0xffffff, [old]))
	native := st.views['check'] or { panic('missing checkbox') }
	vui_control_tracking_begin(native)
	st.render_root(screen(0xffffff, [Element{ ...old, on_event: ios_semantic_event }]))
	assert st.perform_semantic_action('check', .activate)
	assert ios_semantic_handlers == ['current']
	assert ios_semantic_events == [ElementEvent{ kind: .change, id: 'check', checked: true }]
	vui_button_tap(unsafe { nil }, unsafe { nil }, native)
	vui_control_tracking_end(native)
	assert ios_semantic_handlers == ['current', 'captured']
	assert ios_semantic_events[1] == ElementEvent{ kind: .change, id: 'check', checked: false }
	assert !(st.semantic_node('check') or { panic('missing checkbox') }).state.checked
	// The same real pointer commit also works when no callback is installed.
	st.render_root(screen(0xffffff, [Element{ ...old, on_event: unsafe { nil } }]))
	vui_control_tracking_begin(native)
	vui_button_tap(unsafe { nil }, unsafe { nil }, native)
	vui_control_tracking_end(native)
	assert (st.semantic_node('check') or { panic('missing checkbox') }).state.checked
	assert ios_semantic_events.len == 2
}

fn test_ios_semantic_stateful_actions_reject_unavailable_and_disposed_controls() {
	mut st := begin_ios_semantic_fixture()
	defer { end_ios_semantic_fixture(mut st) }
	control := Element{ kind: .toggle_button, id: 'toggle', text: 'Choice', on_event: ios_semantic_event, frame: rect(0, 0, 140, 32) }
	for hidden in [true, false] {
		st.render_root(screen(0xffffff, [Element{ kind: .view, id: 'ancestor', hidden: hidden, enabled: hidden, children: [control] }]))
		assert !st.perform_semantic_action('toggle', .activate)
		assert !st.toggle_button_pressed('toggle')
		assert ios_semantic_events.len == 0
	}
	st.render_root(screen(0xffffff, [control, Element{ kind: .view, id: 'scope', focus_scope: true, children: [Element{ kind: .button, id: 'inside' }] }]))
	// Scope eligibility is shared; UIKit responder acceptance is independent.
	assert st.ios_navigation.enter_scope('scope')
	assert !st.perform_semantic_action('toggle', .activate)
	assert !st.toggle_button_pressed('toggle') && ios_semantic_events.len == 0
	st.render_root(screen(0xffffff, []))
	assert !st.perform_semantic_action('toggle', .activate)
	assert ios_semantic_events.len == 0
}

fn test_ios_dropdown_semantic_capability_and_native_command_selection() {
	mut st := begin_ios_semantic_fixture()
	defer { end_ios_semantic_fixture(mut st) }
	for has_handler in [true, false] {
		callback := if has_handler { ElementCallback(ios_semantic_event) } else { ElementCallback(unsafe { nil }) }
		st.render_root(screen(0xffffff, [Element{ kind: .dropdown, id: 'dropdown', text: 'A', menu: [MenuEntry{ title: 'A' }, MenuEntry{ title: 'B' }], on_event: callback, frame: rect(0, 0, 140, 32) }]))
		native := st.views['dropdown'] or { panic('missing dropdown') }
		ios_semantic_events = []ElementEvent{}
		supported := macos.responds_to(native, 'performPrimaryAction')
		assert (SemanticAction.activate in (st.semantic_node('dropdown') or { panic('missing dropdown') }).actions) == supported
		assert st.perform_semantic_action('dropdown', .activate) == supported
		assert st.text('dropdown') == 'A' && ios_semantic_events.len == 0
		// Menu opening / a stray touch-up must never claim a value change.
		vui_button_tap(unsafe { nil }, unsafe { nil }, native)
		assert ios_semantic_events.len == 0
		menu := macos.msg_id(native, 'menu')
		commands := macos.msg_id(menu, 'children')
		command := macos.msg_id_u64(commands, 'objectAtIndex:', 1)
		vui_dropdown_selected(unsafe { nil }, unsafe { nil }, command)
		assert st.text('dropdown') == 'B'
		assert (st.semantic_node('dropdown') or { panic('missing dropdown') }).value == 'B'
		assert ios_semantic_events == if has_handler { [ElementEvent{ kind: .change, id: 'dropdown', text: 'B' }] } else { []ElementEvent{} }
		macos.msg_void1(native, 'setMenu:', View(unsafe { nil }))
		assert SemanticAction.activate !in (st.semantic_node('dropdown') or { panic('missing dropdown') }).actions
		assert !st.perform_semantic_action('dropdown', .activate)
		assert st.text('dropdown') == 'B'
		st.render_root(screen(0xffffff, []))
	}
}

// These use real UIWindow/UIScrollView/UIKit responders. Mac verification only
// typechecks them; execution requires an iOS host and is reported separately.
fn test_ios_focus_reveals_fractional_scroll_target_with_uikit_selector() {
	mut st := begin_ios_semantic_fixture()
	defer { end_ios_semantic_fixture(mut st) }
	st.render_root(screen(0xffffff, [scroll('pane', rect(0, 0, 180.5, 80.5), 0xffffff, [
		Element{kind: .text_field, id: 'below', text: 'café ñ', frame: rect(0, 250.5, 150.25, 30.25)},
	])]))
	pane := st.views['pane'] or { panic('missing UIScrollView') }
	assert macos.responds_to(pane, 'scrollRectToVisible:animated:')
	assert !macos.responds_to(pane, 'scrollRectToVisible:')
	st.focus('below')
	assert st.focused_id() == 'below'
	visible_offset := scroll_content_offset(pane).y
	assert visible_offset <= 250.5 && visible_offset + 80.5 >= 280.75
	// First-responder acquisition can also scroll UIKit. Reset after acquisition
	// to independently verify the nearest-edge reveal with fractional geometry.
	set_scroll_content_offset(pane, 0, 0)
	st.focus('below')
	assert scroll_content_offset(pane).y == 200.25
	assert st.text('below') == 'café ñ'
}

fn test_ios_reconciliation_resigns_ineligible_or_removed_native_editor_and_keeps_local_edits() {
	mut st := begin_ios_semantic_fixture()
	defer { end_ios_semantic_fixture(mut st) }
	for kind in [Kind.text_field, .text_area] {
		field := Element{kind: kind, id: 'edit', text: 'declared', frame: rect(0, 0, 180, 60)}
		for reason in ['unfocusable', 'hidden', 'disabled', 'ancestor', 'removed'] {
			root := screen(0xffffff, [Element{kind: .view, id: 'parent', children: [field]}])
			st.render_root(root)
			st.focus('edit')
			native := st.views['edit'] or { panic('missing editor') }
			macos.retain(native)
			defer { macos.release(native) }
			assert macos.msg_bool(native, 'isFirstResponder')
			st.set_text('edit', 'local ñá')
			C.ui2_ios_focus_test_select(native, 2, 3)
			assert C.ui2_ios_focus_test_selection_is(native, 2, 3)
			st.render_root(Element{...root, box: BoxStyle{bg: 0xeeeeee}})
			assert st.focused_id() == 'edit' && st.text('edit') == 'local ñá'
			assert (st.views['edit'] or { panic('lost editor') }) == native
			assert C.ui2_ios_focus_test_selection_is(native, 2, 3)
			changed := match reason {
				'unfocusable' { Element{...field, focus_policy: .unfocusable} }
				'hidden' { Element{...field, hidden: true} }
				'disabled' { Element{...field, enabled: false} }
				else { field }
			}
			st.render_root(screen(0xffffff, if reason == 'removed' { []Element{} } else {
				[Element{kind: .view, id: 'parent', enabled: reason != 'ancestor', children: [changed]}]
			}))
			assert st.ios_navigation.current == '' && st.focused_id() == ''
			assert !macos.msg_bool(native, 'isFirstResponder')
			if reason != 'removed' {
				assert st.text('edit') == 'local ñá'
				assert !(st.semantic_node('edit') or { panic('missing semantics') }).state.focused
			}
		}
	}
}

fn test_ios_scope_removal_restores_eligible_native_responder_and_resigns_removed_editor() {
	mut st := begin_ios_semantic_fixture()
	defer { end_ios_semantic_fixture(mut st) }
	outside := Element{kind: .text_field, id: 'outside', text: 'café ñ', frame: rect(0, 0, 180, 30)}
	st.render_root(screen(0xffffff, [outside,
		Element{kind: .view, id: 'scope', focus_scope: true, children: [
			Element{kind: .text_area, id: 'inside', text: 'editor', frame: rect(0, 50, 180, 60)},
		]},
	]))
	st.focus('outside')
	st.set_text('outside', 'local ñá')
	assert st.enter_focus_scope('scope') && st.focused_id() == 'inside'
	inside := st.views['inside'] or { panic('missing scoped editor') }
	macos.retain(inside)
	defer { macos.release(inside) }
	st.render_root(screen(0xffffff, [outside]))
	assert st.focused_id() == 'outside' && st.ios_navigation.current == 'outside'
	assert !macos.msg_bool(inside, 'isFirstResponder')
	assert st.text('outside') == 'local ñá'
}

fn ios_nested_scroll_fixture(outer_id string, inner_id string) Element {
	return scroll(outer_id, rect(10.25, 20.5, 220.75, 110.5), 0xffffff, [
		scroll(inner_id, rect(0, 250.5, 180.5, 90.5), 0xffffff, [
			Element{kind: .view, id: 'scope', focus_scope: true, frame: rect(0, 0, 180.5, 330.75), children: [
				Element{kind: .text_field, id: 'target', text: 'café ñ', frame: rect(0, 300.5, 150.25, 30.25)},
			]},
		]),
	])
}

fn test_ios_nested_anonymous_and_named_scrolls_use_mounted_paths_for_geometry_and_reveal() {
	mut st := begin_ios_semantic_fixture()
	defer { end_ios_semantic_fixture(mut st) }
	for outer_id in ['', 'outer'] {
		for inner_id in ['', 'inner'] {
			root := screen(0xffffff, [ios_nested_scroll_fixture(outer_id, inner_id)])
			st.render_root(root)
			outer := st.nodes['i:0'] or { panic('missing outer UIScrollView') }
			inner := st.nodes['i:0/i:0'] or { panic('missing inner UIScrollView') }
			target := st.views['target'] or { panic('missing target') }
			set_scroll_content_offset(outer, 0, 37.25)
			set_scroll_content_offset(inner, 0, 15.75)
			node := st.semantic_node('target') or { panic('missing target semantics') }
			assert node.frame == rect(10.25, 518.5, 150.25, 30.25)
			assert st.ios_navigation.scroll_offsets['root/i:0'] == 37.25
			assert st.ios_navigation.scroll_offsets['root/i:0/i:0'] == 15.75
			if outer_id.len > 0 { assert (st.views[outer_id] or { panic('missing public outer lookup') }) == outer }
			if inner_id.len > 0 { assert (st.views[inner_id] or { panic('missing public inner lookup') }) == inner }
			assert st.enter_focus_scope('scope') && st.focused_id() == 'target'
			// Isolate our reveal from UIKit's first-responder automatic scrolling.
			set_scroll_content_offset(outer, 0, 0)
			set_scroll_content_offset(inner, 0, 0)
			st.focus('target')
			assert scroll_content_offset(inner).y == 240.25
			assert scroll_content_offset(outer).y == 230.5
			assert C.ui2_ios_focus_test_visible_in_scroll(target, inner)
			assert C.ui2_ios_focus_test_visible_in_scroll(target, outer)
			assert (st.semantic_node('target') or { panic('missing revealed target') }).frame.y == 100.75
			assert st.text('target') == 'café ñ' && st.active_focus_scope() == 'scope'
			assert st.leave_focus_scope()
			st.dismiss_keyboard()
			set_scroll_content_offset(outer, 0, 37.25)
			set_scroll_content_offset(inner, 0, 15.75)
			// Unkeyed sibling insertion changes actual mounted paths. Named
			// panes preserve declared-id restoration when recreated there.
			st.render_root(screen(0xffffff, [Element{kind: .label, text: 'Inserted'}, root.children[0]]))
			new_outer := st.nodes['i:1'] or { panic('missing reordered outer') }
			new_inner := st.nodes['i:1/i:0'] or { panic('missing reordered inner') }
			if outer_id.len > 0 {
				assert (st.views[outer_id] or { panic('lost public outer lookup') }) == new_outer
				assert scroll_content_offset(new_outer).y == 37.25
			}
			if inner_id.len > 0 {
				assert (st.views[inner_id] or { panic('lost public inner lookup') }) == new_inner
				assert scroll_content_offset(new_inner).y == 15.75
			}
			set_scroll_content_offset(new_outer, 0, 37.25)
			set_scroll_content_offset(new_inner, 0, 15.75)
			reordered := st.semantic_node('target') or { panic('missing reordered semantics') }
			assert reordered.path == 'root/i:1/i:0/i:0/i:0'
			assert reordered.frame.y == 518.5
			assert st.ios_navigation.reveals('target').map(it.path) == ['root/i:1/i:0', 'root/i:1']
			assert st.enter_focus_scope('scope') && st.focused_id() == 'target'
			set_scroll_content_offset(new_outer, 0, 0)
			set_scroll_content_offset(new_inner, 0, 0)
			st.focus('target')
			new_target := st.views['target'] or { panic('missing reordered target') }
			assert C.ui2_ios_focus_test_visible_in_scroll(new_target, new_inner)
			assert C.ui2_ios_focus_test_visible_in_scroll(new_target, new_outer)
			assert scroll_content_offset(new_inner).y == 240.25 && scroll_content_offset(new_outer).y == 230.5
			assert st.active_focus_scope() == 'scope'
			assert st.leave_focus_scope()
			st.render_root(screen(0xffffff, []))
		}
	}
}

fn ios_anonymous_semantic_event(_event ElementEvent) {}

fn ios_anonymous_semantic(path string) SemanticNode {
	mut st := ios_window() or { panic('no UIKit fixture window') }
	for node in st.semantic_tree() { if node.path == path { return node } }
	panic('missing anonymous UIKit semantics at ${path}')
}

// Actual UIKit controls and native commands; macOS verification typechecks
// this fixture only and must never credit it as iOS runtime acceptance.
fn test_ios_anonymous_semantics_reads_native_values_and_rebuilt_scroll_paths() {
	mut st := begin_ios_semantic_fixture()
	defer { end_ios_semantic_fixture(mut st) }
	pane := scroll('', rect(0, 0, 300, 440), 0xffffff, [
		Element{kind: .checkbox, key: 'check', text: 'Choice', on_event: ios_anonymous_semantic_event, frame: rect(0, 0, 180, 30)},
		Element{kind: .toggle_button, key: 'toggle', text: 'Toggle', on_event: ios_anonymous_semantic_event, frame: rect(0, 35, 180, 30)},
		Element{kind: .switch_control, key: 'switch', on_event: ios_anonymous_semantic_event, frame: rect(0, 70, 180, 30)},
		Element{kind: .text_field, key: 'field', text: 'declared', frame: rect(0, 105, 180, 30)},
		Element{kind: .text_area, key: 'area', text: 'declared area', frame: rect(0, 140, 180, 70)},
		Element{kind: .dropdown, key: 'choice', text: 'A', menu: [MenuEntry{title: 'A'}, MenuEntry{title: 'B'}], on_event: ios_anonymous_semantic_event, frame: rect(0, 215, 180, 30)},
		Element{kind: .slider, key: 'slider', value: 2.5, min_value: 0, max_value: 10, step: 0.5, frame: rect(0, 250, 180, 30)},
		Element{kind: .text_field, key: 'secret', text: 'secret', secure: true, frame: rect(0, 285, 180, 30)},
		Element{kind: .checkbox, key: 'override', accessibility_value: 'annotation', on_event: ios_anonymous_semantic_event, frame: rect(0, 320, 180, 30)},
	])
	st.render_root(screen(0xffffff, [pane]))
	for key in ['check', 'toggle', 'override'] {
		native := st.nodes['i:0/k:' + key.bytes().hex()] or { panic('missing anonymous checkbox') }
		vui_button_tap(unsafe { nil }, unsafe { nil }, native)
		assert macos.msg_bool(native, 'isSelected')
		node := ios_anonymous_semantic('root/i:0/k:' + key.bytes().hex())
		assert node.id == '' && node.state.checked
		assert node.state.selected == (key == 'toggle')
		assert node.value == if key == 'override' { 'annotation' } else { 'checked' }
	}
	native_switch := st.nodes['i:0/k:737769746368'] or { panic('missing anonymous UISwitch') }
	macos.msg_void_bool(native_switch, 'setOn:', true)
	vui_button_tap(unsafe { nil }, unsafe { nil }, native_switch)
	assert ios_anonymous_semantic('root/i:0/k:737769746368').state.checked
	for key in ['field', 'area'] {
		native := st.nodes['i:0/k:' + key.bytes().hex()] or { panic('missing anonymous editor') }
		macos.msg_void1(native, 'setText:', macos.nsstring('local café ñ ' + key))
		assert ios_anonymous_semantic('root/i:0/k:' + key.bytes().hex()).value == 'local café ñ ' + key
	}
	choice := st.nodes['i:0/k:63686f696365'] or { panic('missing anonymous dropdown') }
	commands := macos.msg_id(macos.msg_id(choice, 'menu'), 'children')
	command := macos.msg_id_u64(commands, 'objectAtIndex:', 1)
	vui_dropdown_selected(unsafe { nil }, unsafe { nil }, command)
	assert ios_anonymous_semantic('root/i:0/k:63686f696365').value == 'B'
	slider_native := st.nodes['i:0/k:736c69646572'] or { panic('missing anonymous UISlider') }
	slider_set_number(slider_native, 'value', 7.5)
	assert ios_anonymous_semantic('root/i:0/k:736c69646572').value == '7.5'
	secret := st.nodes['i:0/k:736563726574'] or { panic('missing anonymous secure field') }
	macos.msg_void1(secret, 'setText:', macos.nsstring('private local ñ'))
	secure := ios_anonymous_semantic('root/i:0/k:736563726574')
	assert secure.value == '' && secure.state.secure
	st.render_root(screen(0xffffff, [Element{kind: .label, text: 'Inserted'}, pane]))
	new_field := st.nodes['i:1/k:6669656c64'] or { panic('missing reordered anonymous editor') }
	macos.msg_void1(new_field, 'setText:', macos.nsstring('reordered ñ'))
	assert ios_anonymous_semantic('root/i:1/k:6669656c64').value == 'reordered ñ'
	assert st.semantic_tree().filter(it.path == 'root/i:0/k:6669656c64').len == 0
	st.render_root(screen(0xffffff, []))
	assert st.semantic_tree().filter(it.path == 'root/i:1/k:6669656c64').len == 0
}
