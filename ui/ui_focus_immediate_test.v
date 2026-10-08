// vtest vflags: -d ui2_custom_rendering
@[has_globals]
module ui2

$if ( android || linux || ( ( macos || windows ) && ui2_custom_rendering ?) ) && !ui2_headless ? {
	import gg
	import sokol.sapp

	__global focus_input_events = []ElementEvent{}
	fn focus_input_event(event ElementEvent) { focus_input_events << event }
	fn focus_input_move_to_editor(event ElementEvent) {
		focus_input_events << event
		focus('edit')
	}

	fn activation_editor_root() Element {
		return screen(0xffffff, [
			Element{ kind: .button, id: 'button', on_event: focus_input_move_to_editor, frame: rect(0, 0, 100, 30) },
			Element{ kind: .text_area, id: 'edit', text: 'seed', frame: rect(0, 40, 180, 60) },
		])
	}

	fn test_custom_consumed_activation_and_repeats_do_not_edit_callback_destination() {
		previous_app := g_gg_app
		previous := activate_custom_window_state(new_custom_window_state())
		defer { activate_custom_window_state(previous); g_gg_app = previous_app }
		mut app := &GgApp{}
		g_gg_app = app
		for key in [gg.KeyCode.space, .enter, .kp_enter] {
			root := activation_editor_root()
			mount_focus_fixture(root)
			set_text('edit', 'seed')
			focus('button')
			focus_input_events = []ElementEvent{}
			character := if key == .space { u32(` `) } else { u32(`\r`) }
			on_event(&gg.Event{ typ: .key_down, key_code: key }, app)
			assert focused_id() == 'edit'
			on_event(&gg.Event{ typ: .char, char_code: character }, app)
			assert text('edit') == 'seed'
			// Unrelated reconciliation preserves physical press ownership.
			mount_focus_fixture(Element{ ...root, box: BoxStyle{ bg: 0xeeeeee } })
			for _ in 0 .. 3 {
				on_event(&gg.Event{ typ: .key_down, key_code: key, key_repeat: true }, app)
				on_event(&gg.Event{ typ: .char, char_code: character, key_repeat: true }, app)
				assert text('edit') == 'seed'
			}
			assert focus_input_events == [ElementEvent{ kind: .tap, id: 'button' }]
			// Another physical key and scan-less UTF-8 text remain editable while
			// the activation key is still held.
			on_event(&gg.Event{ typ: .key_down, key_code: .n }, app)
			on_event(&gg.Event{ typ: .char, char_code: `ñ` }, app)
			on_event(&gg.Event{ typ: .char, char_code: `é` }, app)
			assert text('edit') == 'seedñé'
			on_event(&gg.Event{ typ: .key_up, key_code: .n }, app)
			on_event(&gg.Event{ typ: .key_down, key_code: key, key_repeat: true }, app)
			on_event(&gg.Event{ typ: .char, char_code: character, key_repeat: true }, app)
			assert text('edit') == 'seedñé'
			on_event(&gg.Event{ typ: .key_up, key_code: key }, app)
			// A new press now belongs to the editor, including normal newline.
			on_event(&gg.Event{ typ: .key_down, key_code: key }, app)
			on_event(&gg.Event{ typ: .char, char_code: character }, app)
			assert text('edit') == 'seedñé' + if key == .space { ' ' } else { '\n' }
			on_event(&gg.Event{ typ: .key_up, key_code: key }, app)
			assert focus_input_events.len == 1
		}
	}

	fn test_custom_character_consumption_is_one_delivery_and_window_owned() {
		previous_app := g_gg_app
		first := new_custom_window_state()
		second := new_custom_window_state()
		previous := activate_custom_window_state(first)
		defer { activate_custom_window_state(previous); g_gg_app = previous_app }
		mut app := &GgApp{}
		g_gg_app = app
		mount_focus_fixture(activation_editor_root())
		focus('button')
		on_event(&gg.Event{ typ: .key_down, key_code: .space }, app)
		activate_custom_window_state(second)
		mount_focus_fixture(activation_editor_root())
		focus('edit')
		on_event(&gg.Event{ typ: .char, char_code: ` ` }, app)
		assert text('edit') == 'seed '
		activate_custom_window_state(first)
		on_event(&gg.Event{ typ: .char, char_code: ` ` }, app)
		assert text('edit') == 'seed'
		// Consuming the associated CHAR cannot swallow a later synthesized one.
		on_event(&gg.Event{ typ: .char, char_code: ` ` }, app)
		assert text('edit') == 'seed '
		for lifecycle in [sapp.EventType.unfocused, .suspended, .iconified] {
			focus('button')
			on_event(&gg.Event{ typ: .key_down, key_code: .space }, app)
			on_event(&gg.Event{ typ: lifecycle }, app)
			on_event(&gg.Event{ typ: .char, char_code: ` ` }, app)
			on_event(&gg.Event{ typ: .key_down, key_code: .space, key_repeat: true }, app)
			on_event(&gg.Event{ typ: .char, char_code: ` `, key_repeat: true }, app)
		}
		assert text('edit') == 'seed       '
		focus('button')
		on_event(&gg.Event{ typ: .key_down, key_code: .space }, app)
		discard_custom_window_state(first)
		mount_focus_fixture(activation_editor_root())
		focus('edit')
		on_event(&gg.Event{ typ: .char, char_code: ` ` }, app)
		assert text('edit') == 'seed '
		activate_custom_window_state(second)
		assert text('edit') == 'seed '
		focus('button')
		on_event(&gg.Event{ typ: .key_down, key_code: .space }, app)
		on_cleanup(app)
		mut replacement_app := &GgApp{}
		g_gg_app = replacement_app
		mount_focus_fixture(activation_editor_root())
		focus('edit')
		on_event(&gg.Event{ typ: .char, char_code: ` ` }, replacement_app)
		assert text('edit') == 'seed  '
		on_event(&gg.Event{ typ: .key_down, key_code: .space, key_repeat: true }, replacement_app)
		on_event(&gg.Event{ typ: .char, char_code: ` `, key_repeat: true }, replacement_app)
		assert text('edit') == 'seed   '
	}

	fn test_public_stateful_semantic_actions_commit_once_and_respect_group_policy() {
		previous_app := g_gg_app
		previous := activate_custom_window_state(new_custom_window_state())
		defer { activate_custom_window_state(previous); g_gg_app = previous_app }
		g_gg_app = &GgApp{}
		for kind in [Kind.checkbox, .toggle_button, .switch_control] {
			for has_handler in [true, false] {
				callback := if has_handler { ElementCallback(focus_input_event) } else { ElementCallback(unsafe { nil }) }
				mount_focus_fixture(screen(0xffffff, [Element{ kind: kind, id: 'control', on_event: callback }]))
				focus_input_events = []ElementEvent{}
				for expected in [true, false] {
					assert perform_semantic_action('control', .activate)
					node := semantic_node('control') or { panic('missing control') }
					assert node.state.checked == expected
					assert node.state.selected == (kind == .toggle_button && expected)
					assert node.value == if expected { 'checked' } else { 'unchecked' }
				}
				assert focus_input_events == if has_handler {
					[ElementEvent{ kind: .change, id: 'control', checked: true }, ElementEvent{ kind: .change, id: 'control', checked: false }]
				} else { []ElementEvent{} }
				mount_focus_fixture(screen(0xffffff, []))
			}
		}
		for allow_empty in [true, false] {
			for has_handler in [true, false] {
				callback := if has_handler { ElementCallback(focus_input_event) } else { ElementCallback(unsafe { nil }) }
				root := screen(0xffffff, [
					Element{ kind: .toggle_button, id: 'a', checked: true, toggle_group: 'group', toggle_allow_no_selection: allow_empty, on_event: callback },
					Element{ kind: .toggle_button, id: 'b', toggle_group: 'group', toggle_allow_no_selection: allow_empty, on_event: callback },
				])
				mount_focus_fixture(root)
				focus_input_events = []ElementEvent{}
				assert perform_semantic_action('a', .activate)
				assert toggle_button_pressed('a') == !allow_empty
				assert perform_semantic_action('b', .activate)
				assert !toggle_button_pressed('a') && toggle_button_pressed('b')
				assert perform_semantic_action('b', .activate)
				assert toggle_button_pressed('b') == !allow_empty
				assert focus_input_events == if has_handler {
					[ElementEvent{ kind: .change, id: 'a', checked: !allow_empty }, ElementEvent{ kind: .change, id: 'b', checked: true }, ElementEvent{ kind: .change, id: 'b', checked: !allow_empty }]
				} else { []ElementEvent{} }
				for hidden in [true, false] {
					mount_focus_fixture(screen(0xffffff, [Element{ kind: .view, hidden: hidden, enabled: hidden, children: root.children }]))
					before := focus_input_events.len
					assert !perform_semantic_action('a', .activate)
					assert focus_input_events.len == before
				}
				mount_focus_fixture(screen(0xffffff, []))
				assert !perform_semantic_action('a', .activate)
			}
		}
	}

	fn test_custom_dropdown_activation_repeat_does_not_select_the_new_menu() {
		previous_app := g_gg_app
		previous := activate_custom_window_state(new_custom_window_state())
		defer { activate_custom_window_state(previous); g_gg_app = previous_app }
		mut app := &GgApp{}
		g_gg_app = app
		app.ctx = &DrawContext{ width: 320, height: 240 }
		control := Element{ kind: .dropdown, id: 'choice', text: 'A', on_event: focus_input_event, menu: [MenuEntry{ title: 'A' }, MenuEntry{ title: 'B' }], frame: rect(0, 0, 140, 32) }
		mount_focus_fixture(screen(0xffffff, [control]))
		focus_input_events = []ElementEvent{}
		focus('choice')
		on_event(&gg.Event{ typ: .key_down, key_code: .enter }, app)
		// Run the actual painter's popup projection/cache step between native
		// events, without opening a GPU surface or inventing a popup snapshot.
		track_dropdown_popup(control, 0, 0, ['A', 'B'], text('choice'))
		assert (semantic_node('choice') or { panic('missing dropdown') }).state.expanded
		for _ in 0 .. 3 { on_event(&gg.Event{ typ: .key_down, key_code: .enter, key_repeat: true }, app) }
		assert (semantic_node('choice') or { panic('missing dropdown') }).state.expanded
		assert text('choice') == 'A' && focus_input_events.len == 0
		on_event(&gg.Event{ typ: .key_up, key_code: .enter }, app)
		on_event(&gg.Event{ typ: .key_down, key_code: .down }, app)
		on_event(&gg.Event{ typ: .key_down, key_code: .enter }, app)
		assert !(semantic_node('choice') or { panic('missing dropdown') }).state.expanded
		assert text('choice') == 'B'
		assert focus_input_events == [ElementEvent{ kind: .change, id: 'choice', text: 'B' }]
	}

	fn mount_focus_fixture(root Element) {
		g_active_fields.clear()
		g_active_sliders.clear()
		g_active_switches.clear()
		g_active_checkboxes.clear()
		g_active_toggles.clear()
		g_active_scrolls.clear()
		update_custom_focus_tree(effective_element_state(root, true))
		sync_mounted_focus_controls(effective_element_state(root, true), 'root')
		prune_unmounted_state()
	}

	fn focus_input_root() Element {
		return screen(0xffffff, [
			Element{ kind: .text_field, id: 'edit', text: 'café ñ', on_event: focus_input_event, frame: rect(0, 0, 160, 30) },
			Element{ kind: .button, id: 'button', on_event: focus_input_event, frame: rect(0, 50, 100, 30) },
			Element{ kind: .view, id: 'scope', focus_scope: true, children: [Element{ kind: .view, id: 'composite', button_behavior: true, on_event: focus_input_event, frame: rect(120, 50, 100, 30) }] },
		])
	}

	fn test_custom_real_event_pipeline_consumes_tab_and_activates_once_per_press() {
		previous_app := g_gg_app
		previous := activate_custom_window_state(new_custom_window_state())
		defer {
			activate_custom_window_state(previous)
			g_gg_app = previous_app
		}
		mut app := &GgApp{}
		g_gg_app = app
		focus_input_events = []ElementEvent{}
		mount_focus_fixture(focus_input_root())
		focus('edit')
		on_event(&gg.Event{ typ: .key_down, key_code: .tab }, app)
		assert focused_id() == 'button'
		// A direction with no destination is still consumed by navigation.
		assert handle_focus_key(KeyEvent{ code: .left }, false)
		assert focused_id() == 'button'
		on_event(&gg.Event{ typ: .key_down, key_code: .enter }, app)
		on_event(&gg.Event{ typ: .key_down, key_code: .enter, key_repeat: true }, app)
		on_event(&gg.Event{ typ: .key_down, key_code: .space }, app)
		on_event(&gg.Event{ typ: .char, char_code: ` ` }, app)
		on_event(&gg.Event{ typ: .key_down, key_code: .space, key_repeat: true }, app)
		assert focus_input_events == [ElementEvent{ kind: .tap, id: 'button' },
			ElementEvent{ kind: .tap, id: 'button' }]
		assert text('edit') == 'café ñ'
		on_event(&gg.Event{ typ: .key_down, key_code: .tab, key_repeat: true }, app)
		assert focused_id() == 'composite'
		on_event(&gg.Event{ typ: .key_down, key_code: .space }, app)
		assert focus_input_events.last() == ElementEvent{ kind: .tap, id: 'composite' }
		on_event(&gg.Event{ typ: .key_down, key_code: .tab, modifiers: u32(gg.Modifier.shift) }, app)
		assert focused_id() == 'button'
	}

	fn test_custom_focus_restoration_preserves_selection_edit_buffer_scroll_and_composition() {
		previous_app := g_gg_app
		previous := activate_custom_window_state(new_custom_window_state())
		defer {
			activate_custom_window_state(previous)
			g_gg_app = previous_app
		}
		g_gg_app = &GgApp{}
		root := focus_input_root()
		mount_focus_fixture(root)
		focus('edit')
		set_text('edit', 'local áéñ')
		mut editor := g_text_editors['edit'] or { panic('missing editor') }
		editor.selection = TextSelection{ anchor: 2, caret: 5 }
		replace_text_editor('edit', editor)
		g_scroll_offsets['unrelated'] = 37
		g_active_scrolls['unrelated'] = true
		g_gg_app.composition.update('edit', editor, 'ñ', 1, 0, -1, 0)
		composition := g_gg_app.composition
		// An unrelated declaration update leaves the active editor and IME owner intact.
		update_custom_focus_tree(Element{ ...root, box: BoxStyle{ bg: 0xeeeeee } })
		sync_mounted_focus_controls(root, 'root')
		assert g_text_editors['edit'] or { TextEditor{} } == editor
		assert g_gg_app.composition == composition
		assert focused_id() == 'edit' && g_scroll_offsets['unrelated'] == 37
		assert enter_focus_scope('scope')
		assert focused_id() == 'composite'
		assert g_gg_app.composition.field_id == ''
		assert !g_focus_navigation.can_focus('edit')
		assert leave_focus_scope()
		assert focused_id() == 'edit'
		assert g_text_editors['edit'] or { TextEditor{} } == editor
		set_text('edit', 'replacement ñ')
		assert text('edit') == 'replacement ñ'
		assert (g_text_editors['edit'] or { TextEditor{} }).selection == editor.selection
		assert g_gg_app.composition.field_id == ''
	}

	fn test_custom_culled_inputs_keep_edit_state_and_focus_reveals_destination() {
		previous_app := g_gg_app
		previous := activate_custom_window_state(new_custom_window_state())
		defer {
			activate_custom_window_state(previous)
			g_gg_app = previous_app
		}
		g_gg_app = &GgApp{}
		root := screen(0xffffff, [scroll('pane', rect(10, 20, 200, 100), 0xffffff, [
			Element{ kind: .text_field, id: 'below', text: 'declared', frame: rect(0, 500, 180, 30) },
		])])
		mount_focus_fixture(root)
		set_text('below', 'local ñ')
		mount_focus_fixture(root)
		assert text('below') == 'local ñ'
		assert 'below' in g_active_fields
		assert focus_next() && focused_id() == 'below'
		assert scroll_offset('pane') == 430
		mount_focus_fixture(root)
		assert text('below') == 'local ñ' && focused_id() == 'below'
		assert scroll_offset('pane') == 430
		mount_focus_fixture(screen(0xffffff, []))
		assert focused_id() == '' && 'below' !in g_text_editors
	}

	fn test_custom_nested_scroll_reveals_target_inside_a_taller_inner_viewport() {
		previous_app := g_gg_app
		previous := activate_custom_window_state(new_custom_window_state())
		defer {
			activate_custom_window_state(previous)
			g_gg_app = previous_app
		}
		g_gg_app = &GgApp{}
		mount_focus_fixture(screen(0xffffff, [scroll('outer', rect(0, 0, 100, 100), 0xffffff, [
			scroll('inner', rect(0, 0, 80, 300), 0xffffff, [Element{kind: .button, id: 'below', frame: rect(0, 250, 40, 30)}]),
		])]))
		assert focus_next() && focused_id() == 'below'
		assert scroll_offset('inner') == 0 && scroll_offset('outer') == 180
		assert (semantic_node('below') or { panic('missing button') }).frame == rect(0, 70, 40, 30)
	}

	fn test_custom_automatic_scope_restoration_reveals_its_mounted_destination() {
		previous_app := g_gg_app
		previous := activate_custom_window_state(new_custom_window_state())
		defer {
			activate_custom_window_state(previous)
			g_gg_app = previous_app
		}
		g_gg_app = &GgApp{}
		root := screen(0xffffff, [
			scroll('pane', rect(0, 0, 100, 100), 0xffffff, [Element{kind: .button, id: 'restore', frame: rect(0, 500, 80, 30)}]),
			Element{kind: .view, id: 'scope', focus_scope: true, children: [Element{kind: .button, id: 'inside'}]},
		])
		mount_focus_fixture(root)
		focus('restore')
		assert enter_focus_scope('scope')
		g_scroll_offsets[named_scroll_state_id('pane')] = 0
		mount_focus_fixture(screen(0xffffff, [root.children[0]]))
		assert active_focus_scope() == '' && focused_id() == 'restore'
		assert scroll_offset('pane') == 430
	}

	fn test_custom_hidden_disabled_ancestor_cancels_focus_and_semantic_actions() {
		previous_app := g_gg_app
		previous := activate_custom_window_state(new_custom_window_state())
		defer {
			activate_custom_window_state(previous)
			g_gg_app = previous_app
		}
		g_gg_app = &GgApp{}
		for hide in [false, true] {
			root := focus_input_root()
			mount_focus_fixture(root)
			focus('composite')
			changed := Element{ ...root.children[2], hidden: hide, enabled: hide }
			mount_focus_fixture(Element{
				...root
				children: [root.children[0], root.children[1], changed]
			})
			assert focused_id() == ''
			assert !perform_semantic_action('composite', .activate)
			assert (semantic_node('composite') or { panic('missing semantics') }).actions.len == 0
		}
	}

	fn test_custom_navigation_state_is_owned_and_discarded_per_window() {
		previous_app := g_gg_app
		first := new_custom_window_state()
		second := new_custom_window_state()
		previous := activate_custom_window_state(first)
		defer {
			activate_custom_window_state(previous)
			g_gg_app = previous_app
		}
		g_gg_app = &GgApp{}
		mount_focus_fixture(focus_input_root())
		focus('edit')
		assert enter_focus_scope('scope')
		activate_custom_window_state(second)
		assert active_focus_scope() == '' && focused_id() == ''
		mount_focus_fixture(focus_input_root())
		focus('button')
		activate_custom_window_state(first)
		assert active_focus_scope() == 'scope' && focused_id() == 'composite'
		discard_custom_window_state(second)
		assert active_focus_scope() == 'scope'
		activate_custom_window_state(second)
		assert g_focus_navigation.nodes.len == 0 && active_focus_scope() == ''
	}
}

$if ( android || linux || ( ( macos || windows ) && ui2_custom_rendering ?) ) && !ui2_headless ? {
	fn test_custom_dropdown_tab_and_slider_keys_keep_control_meanings() {
		previous_app := g_gg_app
		previous := activate_custom_window_state(new_custom_window_state())
		defer {
			activate_custom_window_state(previous)
			g_gg_app = previous_app
		}
		g_gg_app = &GgApp{}
		mount_focus_fixture(screen(0xffffff, [
			Element{ kind: .text_field, id: 'before' },
			dropdown('choice', 'one', ['one', 'two'], rect(0, 40, 120, 30), BoxStyle{}, TextStyle{}),
			slider(id: 'volume', min: 0, max: 100, step: 10, value: 20),
		]))
		focus('choice')
		assert perform_semantic_action('choice', .activate)
		assert focused_id() == 'choice' && g_open_dropdown == 'choice'
		assert (semantic_node('choice') or { panic('missing dropdown') }).state.expanded
		assert handle_focus_key(KeyEvent{ code: .tab }, false)
		assert focused_id() == 'volume' && g_open_dropdown == ''
		assert handle_focus_key(KeyEvent{ code: .right }, false)
		assert handle_focus_key(KeyEvent{ code: .right }, true)
		assert slider_value('volume') == 40
		assert handle_focus_key(KeyEvent{ code: .left }, false)
		assert slider_value('volume') == 30 && focused_id() == 'volume'
	}

	fn test_custom_semantic_snapshot_owns_live_edit_text() {
		previous_app := g_gg_app
		previous := activate_custom_window_state(new_custom_window_state())
		defer {
			activate_custom_window_state(previous)
			g_gg_app = previous_app
		}
		g_gg_app = &GgApp{}
		mount_focus_fixture(focus_input_root())
		set_text('edit', 'owned snapshot ñ')
		snapshot := semantic_node('edit') or { panic('missing editor') }
		set_text('edit', 'changed')
		assert snapshot.value == 'owned snapshot ñ'
		assert (semantic_node('edit') or { panic('missing editor') }).value == 'changed'
	}

	fn test_custom_explicit_semantic_value_does_not_replace_live_control_state() {
		previous_app := g_gg_app
		previous := activate_custom_window_state(new_custom_window_state())
		defer {
			activate_custom_window_state(previous)
			g_gg_app = previous_app
		}
		g_gg_app = &GgApp{}
		mount_focus_fixture(screen(0xffffff, [Element{ kind: .text_field, id: 'edit', text: 'secret model', accessibility_value: 'public summary' }]))
		set_text('edit', 'local edit')
		assert (semantic_node('edit') or { panic('missing editor') }).value == 'public summary'
		assert text('edit') == 'local edit'
	}

	fn test_custom_mounted_editor_actions_do_not_depend_on_painted_hit_targets() {
		previous_app := g_gg_app
		previous := activate_custom_window_state(new_custom_window_state())
		defer {
			activate_custom_window_state(previous)
			g_gg_app = previous_app
		}
		g_gg_app = &GgApp{}
		mount_focus_fixture(screen(0xffffff, [Element{ kind: .text_field, id: 'edit', text: 'café', on_event: focus_input_event }]))
		focus('edit')
		g_hit_targets.clear()
		focus_input_events.clear()
		handle_char_input(`ñ`)
		handle_key_down(.enter, 0)
		assert focus_input_events == [ElementEvent{ kind: .change, id: 'edit', text: 'caféñ' }, ElementEvent{ kind: .submit, id: 'edit', text: 'caféñ' }]
		assert focused_id() == '' && g_focus_navigation.current == ''
	}
}

$if ( android || linux || ( ( macos || windows ) && ui2_custom_rendering ?) ) && !ui2_headless ? {
	fn test_custom_hidden_mounted_inputs_retain_edits_but_cannot_take_focus() {
		previous_app := g_gg_app
		previous := activate_custom_window_state(new_custom_window_state())
		defer {
			activate_custom_window_state(previous)
			g_gg_app = previous_app
		}
		g_gg_app = &GgApp{}
		root := screen(0xffffff, [view('parent', rect(0, 0, 200, 100), BoxStyle{}, [Element{ kind: .text_field, id: 'edit', text: 'declared' }])])
		mount_focus_fixture(root)
		focus('edit')
		set_text('edit', 'retained ñ')
		mount_focus_fixture(Element{ ...root, children: [Element{ ...root.children[0], hidden: true }] })
		assert focused_id() == '' && text('edit') == 'retained ñ'
		focus('edit')
		assert focused_id() == ''
		mount_focus_fixture(root)
		focus('edit')
		assert focused_id() == 'edit' && text('edit') == 'retained ñ'
	}
}

$if ( android || linux || ( ( macos || windows ) && ui2_custom_rendering ?) ) && !ui2_headless ? {
	fn test_custom_tab_with_only_programmatic_targets_is_consumed_without_moving() {
		previous_app := g_gg_app
		previous := activate_custom_window_state(new_custom_window_state())
		defer {
			activate_custom_window_state(previous)
			g_gg_app = previous_app
		}
		g_gg_app = &GgApp{}
		mount_focus_fixture(screen(0xffffff, [Element{ kind: .text_field, id: 'edit', text: 'ñ', tab_index: -1 }]))
		focus('edit')
		assert !focus_next()
		assert handle_focus_key(KeyEvent{ code: .tab }, false)
		assert handle_focus_key(KeyEvent{ code: .tab, shift: true }, true)
		assert focused_id() == 'edit' && text('edit') == 'ñ'
	}

	fn test_custom_background_and_dropdown_focus_changes_release_composition_owner() {
		previous_app := g_gg_app
		previous := activate_custom_window_state(new_custom_window_state())
		defer {
			activate_custom_window_state(previous)
			g_gg_app = previous_app
		}
		g_gg_app = &GgApp{}
		mount_focus_fixture(screen(0xffffff, [
			Element{ kind: .text_field, id: 'edit', text: 'niño' },
			dropdown('choice', 'one', ['one', 'two'], rect(0, 40, 120, 30), BoxStyle{}, TextStyle{}),
		]))
		focus('edit')
		editor := g_text_editors['edit'] or { panic('missing editor') }
		g_gg_app.composition.update('edit', editor, 'ñ', 1, 0, -1, 0)
		target := custom_focus_target(g_focus_navigation.node('choice') or { panic('missing dropdown') })
		open_dropdown(target)
		assert focused_id() == 'choice' && g_gg_app.composition.field_id == ''
		close_dropdown()
		focus('edit')
		g_gg_app.composition.update('edit', editor, 'ñ', 1, 0, -1, 0)
		g_hit_targets.clear()
		handle_touch_down(300, 300)
		handle_touch_up(300, 300)
		assert focused_id() == '' && g_focus_navigation.current == ''
		assert g_gg_app.composition.field_id == ''
	}

	fn test_custom_replacing_editor_with_dropdown_releases_editor_and_ime_state() {
		previous_app := g_gg_app
		previous := activate_custom_window_state(new_custom_window_state())
		defer {
			activate_custom_window_state(previous)
			g_gg_app = previous_app
		}
		g_gg_app = &GgApp{}
		mount_focus_fixture(screen(0xffffff, [Element{ kind: .text_field, id: 'choice', text: 'niño' }]))
		focus('choice')
		set_text('choice', 'local café')
		editor := g_text_editors['choice'] or { panic('missing editor') }
		g_gg_app.composition.update('choice', editor, 'ñ', 1, 0, -1, 0)
		mount_focus_fixture(screen(0xffffff, [dropdown('choice', 'one', ['one', 'two'], rect(0, 0, 120, 30), BoxStyle{}, TextStyle{})]))
		assert focused_id() == 'choice'
		assert g_gg_app.composition.field_id == ''
		handle_char_input(`x`)
		handle_key_down(.backspace, 0)
		assert text('choice') == 'one'
		assert 'choice' !in g_text_editors
		set_text('choice', 'two')
		handle_char_input(`x`)
		assert text('choice') == 'two'
		assert 'choice' !in g_text_editors
		mount_focus_fixture(screen(0xffffff, [Element{ kind: .text_field, id: 'choice', text: 'fresh ñ' }]))
		handle_char_input(`é`)
		assert text('choice') == 'fresh ñé'
	}
}
