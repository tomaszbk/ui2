@[has_globals]
module ui2

import macos

__global ios_semantic_events = []ElementEvent{}
__global ios_semantic_handlers = []string{}

fn ios_semantic_event(event ElementEvent) {
	ios_semantic_events << event
	ios_semantic_handlers << 'current'
	if event.kind == .change && event.id != 'dropdown' {
		node := semantic_node(event.id) or { panic('callback lost its mounted control') }
		assert node.state.checked == event.checked
		assert node.value == if event.checked { 'checked' } else { 'unchecked' }
		if event.id.starts_with('toggle') { assert node.state.selected == event.checked }
	}
}

fn ios_semantic_old_event(event ElementEvent) {
	ios_semantic_events << event
	ios_semantic_handlers << 'captured'
}

fn begin_ios_semantic_fixture() {
	ensure_runtime_classes()
	g_root_view = macos.msg_id_rect(macos.alloc('UIView'), 'initWithFrame:', macos.rect(0, 0, 320, 480))
	g_root_vc = macos.msg_id(macos.alloc('UIViewController'), 'init')
	macos.msg_void1(g_root_vc, 'setView:', g_root_view)
	g_window = macos.msg_id_rect(macos.alloc('UIWindow'), 'initWithFrame:', macos.rect(0, 0, 320, 480))
	macos.msg_void1(g_window, 'setRootViewController:', g_root_vc)
	macos.msg_void(g_window, 'makeKeyAndVisible')
	g_button_handler = macos.msg_id(macos.alloc('VuiButtonHandler'), 'init')
	g_ios_navigation = &FocusManager{}
	ios_semantic_events = []ElementEvent{}
	ios_semantic_handlers = []string{}
}

fn end_ios_semantic_fixture() {
	render_root(screen(0xffffff, []))
	macos.msg_void_bool(g_window, 'setHidden:', true)
	macos.release(g_window)
	macos.release(g_root_vc)
	macos.release(g_root_view)
	macos.release(g_button_handler)
	g_window = View(unsafe { nil })
	g_root_vc = View(unsafe { nil })
	g_root_view = View(unsafe { nil })
	g_button_handler = View(unsafe { nil })
	g_ios_navigation = &FocusManager{}
}

fn test_ios_public_semantic_toggle_and_checkbox_commit_once_with_optional_handler() {
	begin_ios_semantic_fixture()
	defer { end_ios_semantic_fixture() }
	for kind in [Kind.toggle_button, .checkbox, .switch_control] {
		for has_handler in [true, false] {
			id := if kind == .toggle_button { 'toggle' } else { 'check' }
			callback := if has_handler { ElementCallback(ios_semantic_event) } else { ElementCallback(unsafe { nil }) }
			render_root(screen(0xffffff, [Element{ kind: kind, id: id, text: 'Choice', on_event: callback, frame: rect(0, 0, 140, 32) }]))
			ios_semantic_events = []ElementEvent{}
			for expected in [true, false] {
				assert perform_semantic_action(id, .activate)
				node := semantic_node(id) or { panic('missing semantic control') }
				assert node.state.checked == expected
				assert node.state.selected == (kind == .toggle_button && expected)
				assert node.value == if expected { 'checked' } else { 'unchecked' }
			}
			assert ios_semantic_events == if has_handler {
				[ElementEvent{ kind: .change, id: id, checked: true }, ElementEvent{ kind: .change, id: id, checked: false }]
			} else { []ElementEvent{} }
			render_root(screen(0xffffff, []))
		}
	}
}

fn test_ios_public_semantic_toggle_groups_keep_or_release_selection_by_policy() {
	begin_ios_semantic_fixture()
	defer { end_ios_semantic_fixture() }
	for allow_empty in [true, false] {
		for has_handler in [true, false] {
			callback := if has_handler { ElementCallback(ios_semantic_event) } else { ElementCallback(unsafe { nil }) }
			render_root(screen(0xffffff, [
				Element{ kind: .toggle_button, id: 'toggle_a', text: 'A', checked: true, toggle_group: 'group', toggle_allow_no_selection: allow_empty, on_event: callback, frame: rect(0, 0, 100, 32) },
				Element{ kind: .toggle_button, id: 'toggle_b', text: 'B', toggle_group: 'group', toggle_allow_no_selection: allow_empty, on_event: callback, frame: rect(0, 40, 100, 32) },
			]))
			ios_semantic_events = []ElementEvent{}
			assert perform_semantic_action('toggle_a', .activate)
			assert toggle_button_pressed('toggle_a') == !allow_empty
			assert !toggle_button_pressed('toggle_b')
			assert perform_semantic_action('toggle_b', .activate)
			assert !toggle_button_pressed('toggle_a') && toggle_button_pressed('toggle_b')
			assert perform_semantic_action('toggle_b', .activate)
			assert toggle_button_pressed('toggle_b') == !allow_empty
			assert ios_semantic_events == if has_handler {
				[ElementEvent{ kind: .change, id: 'toggle_a', checked: !allow_empty },
				 ElementEvent{ kind: .change, id: 'toggle_b', checked: true },
				 ElementEvent{ kind: .change, id: 'toggle_b', checked: !allow_empty }]
			} else { []ElementEvent{} }
			render_root(screen(0xffffff, []))
		}
	}
}

fn test_ios_semantics_uses_current_callback_and_pointer_release_keeps_captured_callback() {
	begin_ios_semantic_fixture()
	defer { end_ios_semantic_fixture() }
	old := Element{ kind: .checkbox, id: 'check', text: 'Choice', on_event: ios_semantic_old_event, frame: rect(0, 0, 140, 32) }
	render_root(screen(0xffffff, [old]))
	native := g_views['check'] or { panic('missing checkbox') }
	vui_control_tracking_begin(native)
	render_root(screen(0xffffff, [Element{ ...old, on_event: ios_semantic_event }]))
	assert perform_semantic_action('check', .activate)
	assert ios_semantic_handlers == ['current']
	assert ios_semantic_events == [ElementEvent{ kind: .change, id: 'check', checked: true }]
	vui_button_tap(unsafe { nil }, unsafe { nil }, native)
	vui_control_tracking_end(native)
	assert ios_semantic_handlers == ['current', 'captured']
	assert ios_semantic_events[1] == ElementEvent{ kind: .change, id: 'check', checked: false }
	assert !(semantic_node('check') or { panic('missing checkbox') }).state.checked
	// The same real pointer commit also works when no callback is installed.
	render_root(screen(0xffffff, [Element{ ...old, on_event: unsafe { nil } }]))
	vui_control_tracking_begin(native)
	vui_button_tap(unsafe { nil }, unsafe { nil }, native)
	vui_control_tracking_end(native)
	assert (semantic_node('check') or { panic('missing checkbox') }).state.checked
	assert ios_semantic_events.len == 2
}

fn test_ios_semantic_stateful_actions_reject_unavailable_and_disposed_controls() {
	begin_ios_semantic_fixture()
	defer { end_ios_semantic_fixture() }
	control := Element{ kind: .toggle_button, id: 'toggle', text: 'Choice', on_event: ios_semantic_event, frame: rect(0, 0, 140, 32) }
	for hidden in [true, false] {
		render_root(screen(0xffffff, [Element{ kind: .view, id: 'ancestor', hidden: hidden, enabled: hidden, children: [control] }]))
		assert !perform_semantic_action('toggle', .activate)
		assert !toggle_button_pressed('toggle')
		assert ios_semantic_events.len == 0
	}
	render_root(screen(0xffffff, [control, Element{ kind: .view, id: 'scope', focus_scope: true, children: [Element{ kind: .button, id: 'inside' }] }]))
	// Scope eligibility is shared; UIKit responder acceptance is independent.
	assert g_ios_navigation.enter_scope('scope')
	assert !perform_semantic_action('toggle', .activate)
	assert !toggle_button_pressed('toggle') && ios_semantic_events.len == 0
	render_root(screen(0xffffff, []))
	assert !perform_semantic_action('toggle', .activate)
	assert ios_semantic_events.len == 0
}

fn test_ios_dropdown_semantic_capability_and_native_command_selection() {
	begin_ios_semantic_fixture()
	defer { end_ios_semantic_fixture() }
	for has_handler in [true, false] {
		callback := if has_handler { ElementCallback(ios_semantic_event) } else { ElementCallback(unsafe { nil }) }
		render_root(screen(0xffffff, [Element{ kind: .dropdown, id: 'dropdown', text: 'A', menu: [MenuEntry{ title: 'A' }, MenuEntry{ title: 'B' }], on_event: callback, frame: rect(0, 0, 140, 32) }]))
		native := g_views['dropdown'] or { panic('missing dropdown') }
		ios_semantic_events = []ElementEvent{}
		supported := macos.responds_to(native, 'performPrimaryAction')
		assert (SemanticAction.activate in (semantic_node('dropdown') or { panic('missing dropdown') }).actions) == supported
		assert perform_semantic_action('dropdown', .activate) == supported
		assert text('dropdown') == 'A' && ios_semantic_events.len == 0
		// Menu opening / a stray touch-up must never claim a value change.
		vui_button_tap(unsafe { nil }, unsafe { nil }, native)
		assert ios_semantic_events.len == 0
		menu := macos.msg_id(native, 'menu')
		commands := macos.msg_id(menu, 'children')
		command := macos.msg_id_u64(commands, 'objectAtIndex:', 1)
		vui_dropdown_selected(unsafe { nil }, unsafe { nil }, command)
		assert text('dropdown') == 'B'
		assert (semantic_node('dropdown') or { panic('missing dropdown') }).value == 'B'
		assert ios_semantic_events == if has_handler { [ElementEvent{ kind: .change, id: 'dropdown', text: 'B' }] } else { []ElementEvent{} }
		macos.msg_void1(native, 'setMenu:', View(unsafe { nil }))
		assert SemanticAction.activate !in (semantic_node('dropdown') or { panic('missing dropdown') }).actions
		assert !perform_semantic_action('dropdown', .activate)
		assert text('dropdown') == 'B'
		render_root(screen(0xffffff, []))
	}
}
