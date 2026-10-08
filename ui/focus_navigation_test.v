module ui2

fn test_consumed_key_character_keeps_unrelated_and_ime_text_while_navigation_is_held() {
	// Tab and Space are held; A and scan-less IME text must still reach editors.
	suppressed := {u32(0x09): u32(0x0f), u32(0x20): u32(0x39), u32(0x0d): u32(0x11c)}
	assert consumed_key_character(0x0f, suppressed)
	assert consumed_key_character(0x39, suppressed)
	assert consumed_key_character(0x11c, suppressed)
	assert !consumed_key_character(0x1e, suppressed)
	assert !consumed_key_character(0x1c, suppressed) // Main Enter differs from keypad Enter.
	assert !consumed_key_character(0, suppressed)
	assert !consumed_key_character(0x0f, map[u32]u32{})
}

fn focus_fixture(id string, x f64, y f64) Element {
	return Element{ kind: .button, id: id, frame: rect(x, y, 40, 30) }
}

fn test_focus_tab_order_is_stable_and_excludes_unavailable_ancestors() {
	mut manager := FocusManager{}
	manager.update(Element{
		kind:     .screen
		children: [
			focus_fixture('normal-a', 0, 0),
			Element{ ...focus_fixture('second', 0, 40), tab_index: 2 },
			Element{ ...focus_fixture('first', 0, 80), tab_index: 1 },
			Element{ ...focus_fixture('tie', 0, 120), tab_index: 2 },
			Element{ ...focus_fixture('hidden', 0, 160), hidden: true },
			Element{ ...focus_fixture('disabled', 0, 200), enabled: false },
			Element{ kind: .view, hidden: true, children: [focus_fixture('hidden-child', 0, 0)] },
			Element{ kind: .view, enabled: false, children: [focus_fixture('disabled-child', 0, 0)] },
			Element{ ...focus_fixture('programmatic', 0, 240), tab_index: -1 },
			Element{ ...focus_fixture('excluded', 0, 280), focus_policy: .unfocusable },
			focus_fixture('normal-b', 0, 320),
		]
	}, map[string]f64{})
	assert manager.order() == ['first', 'second', 'tie', 'normal-a', 'normal-b']
	for id in ['first', 'second', 'tie', 'normal-a', 'normal-b', 'first'] {
		assert manager.traverse(false)
		assert manager.current == id
	}
	for id in ['normal-b', 'normal-a', 'tie', 'second', 'first', 'normal-b'] {
		assert manager.traverse(true)
		assert manager.current == id
	}
	assert manager.set_focus('programmatic')
	assert !manager.set_focus('hidden-child')
	assert !manager.set_focus('disabled-child')
	assert !manager.set_focus('excluded')
	assert manager.traverse(true) && manager.current == 'normal-b'
}

fn focus_scope_fixture() Element {
	return Element{
		kind:     .screen
		children: [focus_fixture('outside', 0, 0), Element{
			kind:        .view
			id:          'panel'
			focus_scope: true
			children:    [
				focus_fixture('a', 0, 40),
				focus_fixture('b', 60, 40),
				Element{ kind: .view, id: 'nested', focus_scope: true, children: [focus_fixture('c', 0, 80)] },
			]
		}, focus_fixture('after', 0, 120)]
	}
}

fn test_focus_scopes_nest_wrap_and_restore_and_handle_removed_destination() {
	mut manager := FocusManager{}
	root := focus_scope_fixture()
	manager.update(root, map[string]f64{})
	assert manager.set_focus('outside')
	assert manager.enter_scope('panel') && manager.current == 'a'
	assert !manager.set_focus('outside')
	assert !manager.enter_scope('panel')
	assert manager.traverse(true) && manager.current == 'c'
	assert manager.set_focus('b')
	assert manager.enter_scope('nested') && manager.current == 'c'
	assert manager.traverse(false) && manager.current == 'c'
	assert manager.leave_scope() && manager.current == 'b'
	assert manager.leave_scope() && manager.current == 'outside'
	assert !manager.leave_scope()
	assert manager.enter_scope('panel')
	manager.update(Element{ ...root, children: root.children[1..] }, map[string]f64{})
	assert manager.current == 'a'
	assert manager.leave_scope() && manager.current == 'a'
}

fn test_removed_hidden_or_disabled_scope_restores_eligible_parent() {
	for unavailable in ['removed', 'hidden', 'disabled'] {
		mut manager := FocusManager{}
		root := focus_scope_fixture()
		manager.update(root, map[string]f64{})
		assert manager.set_focus('outside')
		assert manager.enter_scope('panel')
		assert manager.set_focus('b')
		assert manager.enter_scope('nested')
		changed := Element{ ...root.children[1], hidden: unavailable == 'hidden', enabled: unavailable != 'disabled' }
		children := if unavailable == 'removed' {
			[root.children[0], root.children[2]]
		} else {
			[root.children[0], changed, root.children[2]]
		}
		manager.update(Element{ ...root, children: children }, map[string]f64{})
		assert manager.scopes.len == 0
		assert manager.current == 'outside'
	}
}

fn test_scope_stack_revalidates_all_owners_and_reparented_nesting() {
	root := focus_scope_fixture()
	for remove_parent in [true, false] {
		mut manager := FocusManager{}
		manager.update(root, map[string]f64{})
		assert manager.set_focus('outside')
		assert manager.enter_scope('panel')
		assert manager.set_focus('b')
		assert manager.enter_scope('nested')
		inner := root.children[1].children[2]
		children := if remove_parent {
			[root.children[0], inner, root.children[2]]
		} else {
			[root.children[0], Element{...root.children[1], children: root.children[1].children[..2]}, inner, root.children[2]]
		}
		manager.update(Element{...root, children: children}, map[string]f64{})
		if remove_parent {
			assert manager.scopes.len == 0 && manager.current == 'outside'
		} else {
			assert manager.scopes.map(it.id) == ['panel'] && manager.current == 'b'
			assert manager.leave_scope() && manager.current == 'outside'
		}
	}
}

fn test_automatic_scope_restoration_falls_back_when_saved_destination_is_removed() {
	mut manager := FocusManager{}
	root := focus_scope_fixture()
	manager.update(root, map[string]f64{})
	assert manager.set_focus('outside')
	assert manager.enter_scope('panel')
	manager.update(screen(0xffffff, [root.children[2]]), map[string]f64{})
	assert manager.scopes.len == 0 && manager.current == 'after'
}

fn test_directional_geometry_has_beam_priority_and_deterministic_ties() {
	mut manager := FocusManager{}
	manager.update(Element{
		kind:     .screen
		children: [
			focus_fixture('origin', 0, 0),
			focus_fixture('diagonal-close', 41, 40),
			focus_fixture('right', 120, 0),
			focus_fixture('tie', 120, 0),
			focus_fixture('down', 0, 120),
			focus_fixture('left', -80, 0),
			Element{...focus_fixture('programmatic-only', -160, 0), tab_index: -1},
			Element{ ...focus_fixture('disabled', 45, 0), enabled: false },
		]
	}, map[string]f64{})
	assert manager.set_focus('origin')
	assert manager.directional(.right) && manager.current == 'right'
	assert manager.set_focus('origin')
	assert manager.directional(.down) && manager.current == 'down'
	assert manager.set_focus('origin')
	assert manager.directional(.left) && manager.current == 'left'
	assert !manager.directional(.left)
	manager.set_geometry('right', rect(0, -80, 40, 30))
	assert manager.set_focus('origin')
	assert manager.directional(.up) && manager.current == 'right'
}

fn test_mounted_offscreen_controls_remain_in_order_and_reveal_inside_out() {
	mut manager := FocusManager{}
	root := Element{
		kind:     .screen
		children: [Element{
			kind:     .scroll
			id:       'outer'
			frame:    rect(10, 20, 300, 100)
			children: [
				Element{ kind: .scroll, id: 'inner', frame: rect(0, 400, 200, 80), children: [focus_fixture('below', 0, 600)] },
			]
		}]
	}
	manager.update(root, map[string]f64{
		'root/i:0':     30
		'root/i:0/i:0': 20
	})
	assert manager.order() == ['below']
	assert manager.set_focus('below')
	requests := manager.reveals('below')
	assert requests.len == 2
	assert requests[0].id == 'inner' && requests[0].rect == rect(0, 600, 40, 30)
	assert requests[1].id == 'outer' && requests[1].rect == rect(0, 450, 40, 30)
	assert focus_reveal_offset(20, 80, requests[0].rect) == 550
	assert focus_reveal_offset(30, 100, requests[1].rect) == 380
}

fn test_nested_reveal_keeps_the_target_when_inner_viewport_exceeds_outer() {
	mut manager := FocusManager{}
	manager.update(screen(0xffffff, [scroll('outer', rect(0, 0, 100, 100), 0xffffff, [
		scroll('inner', rect(0, 0, 80, 300), 0xffffff, [focus_fixture('below', 0, 250)]),
	])]), map[string]f64{})
	requests := manager.reveals('below')
	assert requests.len == 2
	assert focus_reveal_offset(0, 300, requests[0].rect) == 0
	assert requests[1].rect == rect(0, 250, 40, 30)
	assert focus_reveal_offset(0, 100, requests[1].rect) == 180
}

fn test_directional_and_reveal_geometry_share_scaled_content_coordinates() {
	mut manager := FocusManager{}
	manager.update(screen(0xffffff, [Element{
		kind: .view
		frame: rect(100, 50, 400, 200)
		content_size: LayoutSize{ width: 200, height: 100 }
		children: [
			focus_fixture('origin', 0, 0),
			focus_fixture('right', 60, 0),
			scroll('pane', rect(0, 40, 100, 50), 0xffffff, [focus_fixture('below', 0, 100)]),
		]
	}]), map[string]f64{ 'root/i:0/i:2': 10 })
	assert (manager.node('origin') or { panic('missing origin') }).frame == rect(100, 50, 80, 60)
	assert (manager.node('right') or { panic('missing right') }).frame == rect(220, 50, 80, 60)
	assert (manager.node('below') or { panic('missing below') }).frame == rect(100, 310, 80, 60)
	assert manager.set_focus('origin')
	assert manager.directional(.right) && manager.current == 'right'
	requests := manager.reveals('below')
	assert requests.len == 1 && requests[0].rect == rect(0, 100, 40, 30)
	assert focus_reveal_offset(10, 50, requests[0].rect) == 80
}

fn test_focus_semantics_expose_explicit_name_live_structure_and_effective_state() {
	mut manager := FocusManager{}
	manager.update(Element{
		kind:     .screen
		children: [Element{
			kind:     .view
			enabled:  false
			children: [
				Element{ ...focus_fixture('save', 0, 0), accessibility_name: 'Save document', accessibility_label: 'Guardar' },
			]
		},
			Element{ kind: .text_field, id: 'password', text: 'secret', secure: true, placeholder: 'Password' }]
	}, map[string]f64{})
	nodes := manager.semantics()
	assert nodes[2].role == 'button' && nodes[2].name == 'Save document'
	assert nodes[2].label == 'Guardar' && nodes[2].state.disabled
	assert nodes[2].actions.len == 0
	assert nodes[2].parent == nodes[1].path
	assert nodes[3].value == '' && nodes[3].state.secure
	assert nodes[3].label == 'Password'
	assert nodes[3].name == 'Password'
	assert nodes[3].actions == [SemanticAction.focus]
}
