module ui2

fn test_mounted_root_geometry_preserves_declarations_and_scaled_children() {
	root := Element{kind: .screen, frame: rect(30, 40, 1, 2), children: [
		scaled_content('composition', rect(0, 0, 400, 300), 200, 100, BoxStyle{}, [
			Element{kind: .view, id: 'panel', frame: rect(12.5, 9.25, 175, 80), children: [
				Element{kind: .label, id: 'caption', frame: rect(3.25, 4.5, 87.5, 10.25)},
			]},
		]),
	]}
	$if ui2_custom_rendering ? { validate_element_tree(root)! }
	mut manager := FocusManager{}
	manager.update_mounted(root, {}, rect(0, 0, 400, 300), ContentTransform{})
	assert manager.semantics()[0].frame == rect(0, 0, 400, 300)
	assert manager.root == root
	assert (manager.path_node('root') or { panic('missing root') }).el.frame == root.frame
	assert (manager.node('panel') or { panic('missing panel') }).frame == rect(25, 68.5, 350, 160)
	assert (manager.node('caption') or { panic('missing caption') }).frame == rect(31.5, 77.5, 175, 20.5)
	manager.update_mounted(root, {}, rect(0, 0, 600, 300), ContentTransform{y: 24})
	assert manager.semantics()[0].frame == rect(0, 24, 600, 300)
	assert (manager.node('caption') or { panic('missing resized caption') }).frame == rect(31.5, 101.5, 175, 20.5)
	subtree := root.children[0].children[0]
	manager.update_mounted(subtree, {}, rect(0, 0, 600, 300), ContentTransform{})
	assert manager.semantics()[0].frame == subtree.frame
	assert (manager.node('caption') or { panic('missing subtree caption') }).frame == rect(15.75, 13.75, 87.5, 10.25)
	manager.update(root, {})
	assert manager.semantics()[0].frame == root.frame
}

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

fn test_geometry_lookup_tracks_named_labels_reorder_removal_and_scope_reparenting() {
	mut manager := FocusManager{}
	outside := focus_fixture('outside', 0, 0)
	origin := Element{ ...focus_fixture('origin', 0, 40), key: 'origin' }
	right := Element{ ...focus_fixture('right', 100, 40), key: 'right' }
	label := Element{ kind: .label, id: 'caption', key: 'caption', frame: rect(3.25, 4.5, 20, 10) }
	panel := Element{ kind: .view, id: 'panel', key: 'panel', focus_scope: true, children: [origin, label, right] }
	root := screen(0xffffff, [outside, panel])
	manager.update(root, map[string]f64{})
	assert manager.set_focus('outside')
	assert manager.enter_scope('panel') && manager.current == 'origin'
	manager.set_geometry('caption', rect(6.5, 9.25, 20.5, 10.75))
	assert (manager.node('caption') or { panic('missing label') }).frame == rect(6.5, 9.25, 20.5, 10.75)
	assert !manager.can_focus('caption')
	assert (manager.path_node('root/k:70616e656c/k:63617074696f6e') or { panic('missing label path') }).frame == rect(6.5, 9.25, 20.5, 10.75)

	// Removing the label and reversing declaration order changes every retained
	// index. Paint geometry must still update the requested control and its path.
	manager.update(screen(0xffffff, [Element{ ...panel, children: [right, origin] }, outside]), map[string]f64{})
	assert manager.current == 'origin' && manager.scopes.map(it.id) == ['panel']
	assert manager.order() == ['right', 'origin']
	assert manager.node('caption') == none
	assert manager.path_node('root/k:70616e656c/k:63617074696f6e') == none
	manager.set_geometry('caption', rect(-100, -100, 1, 1))
	manager.set_geometry('right', rect(0.25, -60.5, 40.5, 30.25))
	assert (manager.path_node('root/k:70616e656c/k:7269676874') or { panic('missing reordered control') }).frame == rect(0.25, -60.5, 40.5, 30.25)
	assert (manager.node('origin') or { panic('missing origin') }).frame == rect(0, 40, 40, 30)
	assert manager.directional(.up) && manager.current == 'right'

	// A surviving id can move out of an active scope. Lookups must expose its
	// new ancestry immediately, while scope removal restores the outside target.
	manager.update(screen(0xffffff, [right, outside]), map[string]f64{})
	assert manager.scopes.len == 0 && manager.current == 'outside'
	assert manager.node('panel') == none && manager.node('origin') == none
	assert manager.path_node('root/k:70616e656c/k:7269676874') == none
	assert (manager.node('right') or { panic('missing reparented control') }).scopes.len == 0
	assert (manager.path_node('root/k:7269676874') or { panic('missing new path') }).el.id == 'right'
	manager.set_geometry('right', rect(90.125, 0.25, 40.5, 30.25))
	assert manager.directional(.right) && manager.current == 'right'
}

fn test_fractional_geometry_lookup_and_anonymous_scroll_paths_survive_rebuild() {
	mut manager := FocusManager{}
	below := Element{ ...focus_fixture('below', 6.25, 75.125), key: 'below' }
	pane := Element{ kind: .scroll, key: 'pane', frame: rect(4.5, 8.25, 90, 40), children: [below] }
	composition := Element{
		kind: .view
		key: 'composition'
		frame: rect(10.25, 20.5, 250, 125)
		content_size: LayoutSize{ width: 200, height: 100 }
		children: [pane]
	}
	root := screen(0xffffff, [composition])
	manager.update(root, map[string]f64{ 'root/k:636f6d706f736974696f6e/k:70616e65': 5.5 })
	assert (manager.node('below') or { panic('missing projected control') }).frame == rect(23.6875, 117.84375, 50, 37.5)
	assert (manager.path_node('root/k:636f6d706f736974696f6e/k:70616e65') or { panic('missing anonymous pane') }).frame == rect(15.875, 30.8125, 112.5, 50)
	requests := manager.reveals('below')
	assert requests.len == 1 && requests[0].id == ''
	assert requests[0].path == 'root/k:636f6d706f736974696f6e/k:70616e65'
	assert requests[0].rect == rect(6.25, 75.125, 40, 30)
	assert focus_reveal_offset(5.5, 40, requests[0].rect) == 65.125

	manager.set_geometry('below', rect(24.3125, 116.90625, 49.375, 36.875))
	assert (manager.path_node('root/k:636f6d706f736974696f6e/k:70616e65/k:62656c6f77') or { panic('missing painted control') }).frame == rect(24.3125, 116.90625, 49.375, 36.875)
	assert (manager.node('below') or { panic('missing painted id') }).frame == rect(24.3125, 116.90625, 49.375, 36.875)
	root_frame := (manager.path_node('root') or { panic('missing root') }).frame
	manager.set_geometry('', rect(-1, -1, 1, 1))
	manager.set_geometry('absent', rect(-2, -2, 1, 1))
	assert (manager.path_node('root') or { panic('missing root after unnamed geometry') }).frame == root_frame

	// Replace the keyed pane with an index-addressed ancestor and a new offset.
	// Neither its former path nor the paint-only geometry may survive rebuilding.
	changed := Element{ ...composition, children: [Element{ ...pane, key: '' }] }
	manager.update(screen(0xffffff, [focus_fixture('before', 0, 0), changed]), map[string]f64{ 'root/k:636f6d706f736974696f6e/i:0': 15.25 })
	assert manager.path_node('root/k:636f6d706f736974696f6e/k:70616e65') == none
	assert manager.path_node('root/k:636f6d706f736974696f6e/k:70616e65/k:62656c6f77') == none
	assert (manager.node('below') or { panic('missing rebuilt projection') }).frame == rect(23.6875, 105.65625, 50, 37.5)
	rebuilt := manager.reveals('below')
	assert rebuilt.len == 1 && rebuilt[0].path == 'root/k:636f6d706f736974696f6e/i:0'
	assert rebuilt[0].rect == rect(6.25, 75.125, 40, 30)
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
