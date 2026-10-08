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

// These use real UIWindow/UIScrollView/UIKit responders. Mac verification only
// typechecks them; execution requires an iOS host and is reported separately.
fn test_ios_focus_reveals_fractional_scroll_target_with_uikit_selector() {
	begin_ios_semantic_fixture()
	defer { end_ios_semantic_fixture() }
	render_root(screen(0xffffff, [scroll('pane', rect(0, 0, 180.5, 80.5), 0xffffff, [
		Element{kind: .text_field, id: 'below', text: 'café ñ', frame: rect(0, 250.5, 150.25, 30.25)},
	])]))
	pane := g_views['pane'] or { panic('missing UIScrollView') }
	assert macos.responds_to(pane, 'scrollRectToVisible:animated:')
	assert !macos.responds_to(pane, 'scrollRectToVisible:')
	focus('below')
	assert focused_id() == 'below'
	visible_offset := scroll_content_offset_y(pane)
	assert visible_offset <= 250.5 && visible_offset + 80.5 >= 280.75
	// First-responder acquisition can also scroll UIKit. Reset after acquisition
	// to independently verify the nearest-edge reveal with fractional geometry.
	set_scroll_content_offset_y(pane, 0)
	focus('below')
	assert scroll_content_offset_y(pane) == 200.25
	assert text('below') == 'café ñ'
}

fn test_ios_reconciliation_resigns_ineligible_or_removed_native_editor_and_keeps_local_edits() {
	begin_ios_semantic_fixture()
	defer { end_ios_semantic_fixture() }
	for kind in [Kind.text_field, .text_area] {
		field := Element{kind: kind, id: 'edit', text: 'declared', frame: rect(0, 0, 180, 60)}
		for reason in ['unfocusable', 'hidden', 'disabled', 'ancestor', 'removed'] {
			root := screen(0xffffff, [Element{kind: .view, id: 'parent', children: [field]}])
			render_root(root)
			focus('edit')
			native := g_views['edit'] or { panic('missing editor') }
			macos.retain(native)
			defer { macos.release(native) }
			assert macos.msg_bool(native, 'isFirstResponder')
			set_text('edit', 'local ñá')
			C.ui2_ios_focus_test_select(native, 2, 3)
			assert C.ui2_ios_focus_test_selection_is(native, 2, 3)
			render_root(Element{...root, box: BoxStyle{bg: 0xeeeeee}})
			assert focused_id() == 'edit' && text('edit') == 'local ñá'
			assert (g_views['edit'] or { panic('lost editor') }) == native
			assert C.ui2_ios_focus_test_selection_is(native, 2, 3)
			changed := match reason {
				'unfocusable' { Element{...field, focus_policy: .unfocusable} }
				'hidden' { Element{...field, hidden: true} }
				'disabled' { Element{...field, enabled: false} }
				else { field }
			}
			render_root(screen(0xffffff, if reason == 'removed' { []Element{} } else {
				[Element{kind: .view, id: 'parent', enabled: reason != 'ancestor', children: [changed]}]
			}))
			assert g_ios_navigation.current == '' && focused_id() == ''
			assert !macos.msg_bool(native, 'isFirstResponder')
			if reason != 'removed' {
				assert text('edit') == 'local ñá'
				assert !(semantic_node('edit') or { panic('missing semantics') }).state.focused
			}
		}
	}
}

fn test_ios_scope_removal_restores_eligible_native_responder_and_resigns_removed_editor() {
	begin_ios_semantic_fixture()
	defer { end_ios_semantic_fixture() }
	outside := Element{kind: .text_field, id: 'outside', text: 'café ñ', frame: rect(0, 0, 180, 30)}
	render_root(screen(0xffffff, [outside,
		Element{kind: .view, id: 'scope', focus_scope: true, children: [
			Element{kind: .text_area, id: 'inside', text: 'editor', frame: rect(0, 50, 180, 60)},
		]},
	]))
	focus('outside')
	set_text('outside', 'local ñá')
	assert enter_focus_scope('scope') && focused_id() == 'inside'
	inside := g_views['inside'] or { panic('missing scoped editor') }
	macos.retain(inside)
	defer { macos.release(inside) }
	render_root(screen(0xffffff, [outside]))
	assert focused_id() == 'outside' && g_ios_navigation.current == 'outside'
	assert !macos.msg_bool(inside, 'isFirstResponder')
	assert text('outside') == 'local ñá'
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
	begin_ios_semantic_fixture()
	defer { end_ios_semantic_fixture() }
	for outer_id in ['', 'outer'] {
		for inner_id in ['', 'inner'] {
			root := screen(0xffffff, [ios_nested_scroll_fixture(outer_id, inner_id)])
			render_root(root)
			outer := g_nodes['i:0'] or { panic('missing outer UIScrollView') }
			inner := g_nodes['i:0/i:0'] or { panic('missing inner UIScrollView') }
			target := g_views['target'] or { panic('missing target') }
			set_scroll_content_offset_y(outer, 37.25)
			set_scroll_content_offset_y(inner, 15.75)
			node := semantic_node('target') or { panic('missing target semantics') }
			assert node.frame == rect(10.25, 518.5, 150.25, 30.25)
			assert g_ios_navigation.scroll_offsets['root/i:0'] == 37.25
			assert g_ios_navigation.scroll_offsets['root/i:0/i:0'] == 15.75
			if outer_id.len > 0 { assert (g_views[outer_id] or { panic('missing public outer lookup') }) == outer }
			if inner_id.len > 0 { assert (g_views[inner_id] or { panic('missing public inner lookup') }) == inner }
			assert enter_focus_scope('scope') && focused_id() == 'target'
			// Isolate our reveal from UIKit's first-responder automatic scrolling.
			set_scroll_content_offset_y(outer, 0)
			set_scroll_content_offset_y(inner, 0)
			focus('target')
			assert scroll_content_offset_y(inner) == 240.25
			assert scroll_content_offset_y(outer) == 230.5
			assert C.ui2_ios_focus_test_visible_in_scroll(target, inner)
			assert C.ui2_ios_focus_test_visible_in_scroll(target, outer)
			assert (semantic_node('target') or { panic('missing revealed target') }).frame.y == 100.75
			assert text('target') == 'café ñ' && active_focus_scope() == 'scope'
			assert leave_focus_scope()
			dismiss_keyboard()
			set_scroll_content_offset_y(outer, 37.25)
			set_scroll_content_offset_y(inner, 15.75)
			// Unkeyed sibling insertion changes actual mounted paths. Named
			// panes preserve declared-id restoration when recreated there.
			render_root(screen(0xffffff, [Element{kind: .label, text: 'Inserted'}, root.children[0]]))
			new_outer := g_nodes['i:1'] or { panic('missing reordered outer') }
			new_inner := g_nodes['i:1/i:0'] or { panic('missing reordered inner') }
			if outer_id.len > 0 {
				assert (g_views[outer_id] or { panic('lost public outer lookup') }) == new_outer
				assert scroll_content_offset_y(new_outer) == 37.25
			}
			if inner_id.len > 0 {
				assert (g_views[inner_id] or { panic('lost public inner lookup') }) == new_inner
				assert scroll_content_offset_y(new_inner) == 15.75
			}
			set_scroll_content_offset_y(new_outer, 37.25)
			set_scroll_content_offset_y(new_inner, 15.75)
			reordered := semantic_node('target') or { panic('missing reordered semantics') }
			assert reordered.path == 'root/i:1/i:0/i:0/i:0'
			assert reordered.frame.y == 518.5
			assert g_ios_navigation.reveals('target').map(it.path) == ['root/i:1/i:0', 'root/i:1']
			assert enter_focus_scope('scope') && focused_id() == 'target'
			set_scroll_content_offset_y(new_outer, 0)
			set_scroll_content_offset_y(new_inner, 0)
			focus('target')
			new_target := g_views['target'] or { panic('missing reordered target') }
			assert C.ui2_ios_focus_test_visible_in_scroll(new_target, new_inner)
			assert C.ui2_ios_focus_test_visible_in_scroll(new_target, new_outer)
			assert scroll_content_offset_y(new_inner) == 240.25 && scroll_content_offset_y(new_outer) == 230.5
			assert active_focus_scope() == 'scope'
			assert leave_focus_scope()
			render_root(screen(0xffffff, []))
		}
	}
}
