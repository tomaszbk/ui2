@[has_globals]
module ui2

$if (android || ios || linux || macos || windows) && !ui2_headless ? {
	import gg
	import sokol.sapp

	__global focus_input_events = []ElementEvent{}
	fn focus_input_event(event ElementEvent) { focus_input_events << event }
	fn focus_input_move_to_editor(event ElementEvent) {
		mut w := event.window
		focus_input_events << event
		w.focus('edit')
	}

	fn activation_editor_root() Element {
		return screen(0xffffff, [
			Element{ kind: .button, id: 'button', on_event: focus_input_move_to_editor, frame: rect(0, 0, 100, 30) },
			Element{ kind: .text_area, id: 'edit', text: 'seed', frame: rect(0, 40, 180, 60) },
		])
	}

	fn test_custom_consumed_activation_and_repeats_do_not_edit_callback_destination() {
		mut w := &Window{}
		for key in [gg.KeyCode.space, .enter, .kp_enter] {
			root := activation_editor_root()
			mount_focus_fixture(mut w, root)
			w.set_text('edit', 'seed')
			w.focus('button')
			focus_input_events = []ElementEvent{}
			character := if key == .space { u32(` `) } else { u32(`\r`) }
			on_event(&gg.Event{ typ: .key_down, key_code: key }, mut w)
			assert w.focused_id() == 'edit'
			on_event(&gg.Event{ typ: .char, char_code: character }, mut w)
			assert w.text('edit') == 'seed'
			// Unrelated reconciliation preserves physical press ownership.
			mount_focus_fixture(mut w, Element{ ...root, box: BoxStyle{ bg: 0xeeeeee } })
			for _ in 0 .. 3 {
				on_event(&gg.Event{ typ: .key_down, key_code: key, key_repeat: true }, mut w)
				on_event(&gg.Event{ typ: .char, char_code: character, key_repeat: true }, mut w)
				assert w.text('edit') == 'seed'
			}
			assert focus_input_events == [ElementEvent{ window: w, kind: .click, id: 'button' }]
			// Another physical key and scan-less UTF-8 text remain editable while
			// the activation key is still held.
			on_event(&gg.Event{ typ: .key_down, key_code: .n }, mut w)
			on_event(&gg.Event{ typ: .char, char_code: `ñ` }, mut w)
			on_event(&gg.Event{ typ: .char, char_code: `é` }, mut w)
			assert w.text('edit') == 'seedñé'
			on_event(&gg.Event{ typ: .key_up, key_code: .n }, mut w)
			on_event(&gg.Event{ typ: .key_down, key_code: key, key_repeat: true }, mut w)
			on_event(&gg.Event{ typ: .char, char_code: character, key_repeat: true }, mut w)
			assert w.text('edit') == 'seedñé'
			on_event(&gg.Event{ typ: .key_up, key_code: key }, mut w)
			// A new press now belongs to the editor, including normal newline.
			on_event(&gg.Event{ typ: .key_down, key_code: key }, mut w)
			on_event(&gg.Event{ typ: .char, char_code: character }, mut w)
			assert w.text('edit') == 'seedñé' + if key == .space { ' ' } else { '\n' }
			on_event(&gg.Event{ typ: .key_up, key_code: key }, mut w)
			assert focus_input_events.len == 1
		}
	}

	fn test_custom_character_consumption_is_one_delivery_and_window_owned() {
		mut first := &Window{}
		mut second := &Window{}
		mount_focus_fixture(mut first, activation_editor_root())
		first.focus('button')
		on_event(&gg.Event{ typ: .key_down, key_code: .space }, mut first)
		// The key held in the first window does not consume the second's text.
		mount_focus_fixture(mut second, activation_editor_root())
		second.focus('edit')
		on_event(&gg.Event{ typ: .char, char_code: ` ` }, mut second)
		assert second.text('edit') == 'seed '
		on_event(&gg.Event{ typ: .char, char_code: ` ` }, mut first)
		assert first.text('edit') == 'seed'
		// Consuming the associated CHAR cannot swallow a later synthesized one.
		on_event(&gg.Event{ typ: .char, char_code: ` ` }, mut first)
		assert first.text('edit') == 'seed '
		for lifecycle in [sapp.EventType.unfocused, .suspended, .iconified] {
			first.focus('button')
			on_event(&gg.Event{ typ: .key_down, key_code: .space }, mut first)
			on_event(&gg.Event{ typ: lifecycle }, mut first)
			on_event(&gg.Event{ typ: .char, char_code: ` ` }, mut first)
			on_event(&gg.Event{ typ: .key_down, key_code: .space, key_repeat: true }, mut first)
			on_event(&gg.Event{ typ: .char, char_code: ` `, key_repeat: true }, mut first)
		}
		assert first.text('edit') == 'seed       '
		assert second.text('edit') == 'seed '
		// A window that closes takes its held key with it.
		second.focus('button')
		on_event(&gg.Event{ typ: .key_down, key_code: .space }, mut second)
		on_cleanup(mut second)
		mut replacement := &Window{}
		mount_focus_fixture(mut replacement, activation_editor_root())
		replacement.focus('edit')
		on_event(&gg.Event{ typ: .char, char_code: ` ` }, mut replacement)
		assert replacement.text('edit') == 'seed '
		on_event(&gg.Event{ typ: .key_down, key_code: .space, key_repeat: true }, mut replacement)
		on_event(&gg.Event{ typ: .char, char_code: ` `, key_repeat: true }, mut replacement)
		assert replacement.text('edit') == 'seed  '
	}

	fn test_public_stateful_semantic_actions_commit_once_and_respect_group_policy() {
		mut w := &Window{}
		for kind in [Kind.checkbox, .toggle_button, .switch_control] {
			for has_handler in [true, false] {
				callback := if has_handler {
					ElementCallback(focus_input_event)
				} else {
					ElementCallback(unsafe { nil })
				}
				mount_focus_fixture(mut w, screen(0xffffff, [Element{ kind: kind, id: 'control', on_event: callback }]))
				focus_input_events = []ElementEvent{}
				for expected in [true, false] {
					assert w.perform_semantic_action('control', .activate)
					node := w.semantic_node('control') or { panic('missing control') }
					assert node.state.checked == expected
					assert node.state.selected == (kind == .toggle_button && expected)
					assert node.value == if expected { 'checked' } else { 'unchecked' }
				}
				assert focus_input_events == if has_handler {
					[
						ElementEvent{ window: w, kind: .change, id: 'control', checked: true },
						ElementEvent{ window: w, kind: .change, id: 'control', checked: false },
					]
				} else {
					[]ElementEvent{}
				}
				mount_focus_fixture(mut w, screen(0xffffff, []))
			}
		}
		for allow_empty in [true, false] {
			for has_handler in [true, false] {
				callback := if has_handler {
					ElementCallback(focus_input_event)
				} else {
					ElementCallback(unsafe { nil })
				}
				root := screen(0xffffff, [
					Element{ kind: .toggle_button, id: 'a', checked: true, toggle: &ToggleSpec{ group: 'group', allow_no_selection: allow_empty }, on_event: callback },
					Element{ kind: .toggle_button, id: 'b', toggle: &ToggleSpec{ group: 'group', allow_no_selection: allow_empty }, on_event: callback },
				])
				mount_focus_fixture(mut w, root)
				focus_input_events = []ElementEvent{}
				assert w.perform_semantic_action('a', .activate)
				assert w.toggle_button_pressed('a') == !allow_empty
				assert w.perform_semantic_action('b', .activate)
				assert !w.toggle_button_pressed('a') && w.toggle_button_pressed('b')
				assert w.perform_semantic_action('b', .activate)
				assert w.toggle_button_pressed('b') == !allow_empty
				assert focus_input_events == if has_handler {
					[
						ElementEvent{ window: w, kind: .change, id: 'a', checked: !allow_empty },
						ElementEvent{ window: w, kind: .change, id: 'b', checked: true },
						ElementEvent{ window: w, kind: .change, id: 'b', checked: !allow_empty },
					]
				} else {
					[]ElementEvent{}
				}
				for hidden in [true, false] {
					mount_focus_fixture(mut w, screen(0xffffff, [Element{ kind: .view, hidden: hidden, enabled: hidden, children: root.children }]))
					before := focus_input_events.len
					assert !w.perform_semantic_action('a', .activate)
					assert focus_input_events.len == before
				}
				mount_focus_fixture(mut w, screen(0xffffff, []))
				assert !w.perform_semantic_action('a', .activate)
			}
		}
	}

	fn test_custom_dropdown_activation_repeat_does_not_select_the_new_menu() {
		mut w := &Window{}
		w.ctx = &DrawContext{ width: 320, height: 240 }
		control := Element{ kind: .dropdown, id: 'choice', text: 'A', on_event: focus_input_event, menu: [
			MenuEntry{ title: 'A' },
			MenuEntry{ title: 'B' },
		], frame: rect(0, 0, 140, 32) }
		mount_focus_fixture(mut w, screen(0xffffff, [control]))
		focus_input_events = []ElementEvent{}
		w.focus('choice')
		on_event(&gg.Event{ typ: .key_down, key_code: .enter }, mut w)
		// Run the actual painter's popup projection/cache step between native
		// events, without opening a GPU surface or inventing a popup snapshot.
		w.track_dropdown_popup(control, 0, 0, ['A', 'B'], w.text('choice'))
		assert (w.semantic_node('choice') or { panic('missing dropdown') }).state.expanded
		for _ in 0 .. 3 {
			on_event(&gg.Event{ typ: .key_down, key_code: .enter, key_repeat: true }, mut w)
		}
		assert (w.semantic_node('choice') or { panic('missing dropdown') }).state.expanded
		assert w.text('choice') == 'A' && focus_input_events.len == 0
		on_event(&gg.Event{ typ: .key_up, key_code: .enter }, mut w)
		on_event(&gg.Event{ typ: .key_down, key_code: .down }, mut w)
		on_event(&gg.Event{ typ: .key_down, key_code: .enter }, mut w)
		assert !(w.semantic_node('choice') or { panic('missing dropdown') }).state.expanded
		assert w.text('choice') == 'B'
		assert focus_input_events == [ElementEvent{ window: w, kind: .change, id: 'choice', text: 'B' }]
	}

	fn mount_focus_fixture(mut w Window, root Element) {
		mut tree := LayoutTree{}
		tree.replace(root) or { panic(err) }
		resolved := tree.resolve(LayoutConstraints{}, measure_layout_text, LayoutEnvironment{}) or { panic(err) }
		w.active_fields.clear()
		w.active_sliders.clear()
		w.active_switches.clear()
		w.active_checkboxes.clear()
		w.active_toggles.clear()
		w.active_scrolls.clear()
		w.update_custom_focus_tree(resolved)
		w.sync_mounted_focus_controls(resolved, 'root')
		w.prune_unmounted_state()
	}

	fn test_nested_scroll_notification_revalidates_each_focus_reveal_continuation() {
		// The inner A notification calls B; B can invalidate the outer A reveal.
		// The normal case proves nested notifications do not suppress that reveal.
		for mode in 0 .. 6 {
			mut w := &Window{ ctx: &DrawContext{ width: 320, height: 180 } }
			mut events := &[]string{}
			inner_callback := fn [mut w, mut events] (event ElementEvent) {
				events << 'inner:${event.value}'
				w.scroll_to_offset('b', 42)
			}
			outer_callback := fn [mut events] (event ElementEvent) {
				events << 'outer:${event.value}'
			}
			b_callback := fn [mode, mut w, mut events] (event ElementEvent) {
				events << 'b:${event.value}'
				match mode {
					1 {
						w.update_custom_focus_tree(screen(0xffffff, [Element{ kind: .button, id: 'replacement' }]))
					}
					2 { w.scheduler = new_frame_coordinator() }
					3 { w.ctx = &DrawContext{ width: 640, height: 360 } }
					4 { w.ctx.destroyed = true }
					5 { w.scheduler.close() }
					else {}
				}
			}
			inner := Element{
				kind:     .scroll
				id:       'inner'
				frame:    rect(0, 300, 100, 100)
				children: [Element{ kind: .button, id: 'restore', frame: rect(0, 500, 80, 30) }]
			}
			outer := Element{ kind: .scroll, id: 'outer', frame: rect(0, 0, 100, 100), children: [inner] }
			b := Element{
				kind:     .scroll
				id:       'b'
				frame:    rect(180, 0, 100, 100)
				children: [Element{ kind: .label, frame: rect(0, 300, 80, 30) }]
			}
			mount_focus_fixture(mut w, screen(0xffffff, [outer, b, Element{
				kind:        .view
				id:          'scope'
				focus_scope: true
				children:    [Element{ kind: .button, id: 'inside' }]
			}]))
			w.focus('restore')
			assert w.scroll_offset('inner') == 430 && w.scroll_offset('outer') == 300
			assert w.enter_focus_scope('scope')
			w.scroll_to_offset('inner', 0)
			w.scroll_to_offset('outer', 0)
			current_inner := Element{ ...inner, on_event: inner_callback }
			current_outer := Element{ ...outer, on_event: outer_callback, children: [current_inner] }
			w.update_custom_focus_tree(screen(0xffffff, [current_outer,
				Element{ ...b, on_event: b_callback }]))
			assert *events == if mode == 0 {
				['inner:430.0', 'b:42.0', 'outer:300.0']
			} else {
				['inner:430.0', 'b:42.0']
			}
			if mode == 0 {
				assert w.focused_id() == 'restore' && w.scroll_offset('outer') == 300
			}
			eprintln('nested scroll continuation mode=${mode} passed')
		}
	}

	fn focus_input_root() Element {
		return screen(0xffffff, [
			Element{ kind: .text_field, id: 'edit', text: 'café ñ', on_event: focus_input_event, frame: rect(0, 0, 160, 30) },
			Element{ kind: .button, id: 'button', on_event: focus_input_event, frame: rect(0, 50, 100, 30) },
			Element{ kind: .view, id: 'scope', focus_scope: true, children: [Element{ kind: .view, id: 'composite', button_behavior: true, on_event: focus_input_event, frame: rect(120, 50, 100, 30) }] },
		])
	}

	fn test_custom_real_event_pipeline_consumes_tab_and_activates_once_per_press() {
		mut w := &Window{}
		focus_input_events = []ElementEvent{}
		mount_focus_fixture(mut w, focus_input_root())
		w.focus('edit')
		on_event(&gg.Event{ typ: .key_down, key_code: .tab }, mut w)
		assert w.focused_id() == 'button'
		// A direction with no destination is still consumed by navigation.
		assert w.handle_focus_key(KeyEvent{ code: .left }, false)
		assert w.focused_id() == 'button'
		on_event(&gg.Event{ typ: .key_down, key_code: .enter }, mut w)
		on_event(&gg.Event{ typ: .key_down, key_code: .enter, key_repeat: true }, mut w)
		on_event(&gg.Event{ typ: .key_down, key_code: .space }, mut w)
		on_event(&gg.Event{ typ: .char, char_code: ` ` }, mut w)
		on_event(&gg.Event{ typ: .key_down, key_code: .space, key_repeat: true }, mut w)
		assert focus_input_events == [
			ElementEvent{ window: w, kind: .click, id: 'button' },
			ElementEvent{ window: w, kind: .click, id: 'button' },
		]
		assert w.text('edit') == 'café ñ'
		on_event(&gg.Event{ typ: .key_down, key_code: .tab, key_repeat: true }, mut w)
		assert w.focused_id() == 'composite'
		on_event(&gg.Event{ typ: .key_down, key_code: .space }, mut w)
		assert focus_input_events.last() == ElementEvent{ window: w, kind: .click, id: 'composite' }
		on_event(&gg.Event{ typ: .key_down, key_code: .tab, modifiers: u32(gg.Modifier.shift) }, mut w)
		assert w.focused_id() == 'button'
	}

	fn test_custom_focus_restoration_preserves_selection_edit_buffer_scroll_and_composition() {
		mut w := &Window{}
		root := focus_input_root()
		mount_focus_fixture(mut w, root)
		w.focus('edit')
		w.set_text('edit', 'local áéñ')
		mut editor := w.text_editors['edit'] or { panic('missing editor') }
		editor.selection = TextSelection{ anchor: 2, caret: 5 }
		w.replace_text_editor('edit', editor)
		w.scroll_offsets['unrelated'] = 37
		w.active_scrolls['unrelated'] = true
		w.composition.update('edit', editor, 'ñ', 1, 0, -1, 0)
		composition := w.composition
		// An unrelated declaration update leaves the active editor and IME owner intact.
		w.update_custom_focus_tree(Element{ ...root, box: BoxStyle{ bg: 0xeeeeee } })
		w.sync_mounted_focus_controls(root, 'root')
		assert w.text_editors['edit'] or { TextEditor{} } == editor
		assert w.composition == composition
		assert w.focused_id() == 'edit' && w.scroll_offsets['unrelated'] == 37
		assert w.enter_focus_scope('scope')
		assert w.focused_id() == 'composite'
		assert w.composition.field_id == ''
		assert !w.navigation.can_focus('edit')
		assert w.leave_focus_scope()
		assert w.focused_id() == 'edit'
		assert w.text_editors['edit'] or { TextEditor{} } == editor
		w.set_text('edit', 'replacement ñ')
		assert w.text('edit') == 'replacement ñ'
		assert (w.text_editors['edit'] or { TextEditor{} }).selection == editor.selection
		assert w.composition.field_id == ''
	}

	fn test_custom_culled_inputs_keep_edit_state_and_focus_reveals_destination() {
		mut w := &Window{}
		root := screen(0xffffff, [scroll('pane', rect(10, 20, 200, 100), 0xffffff, [
			Element{ kind: .text_field, id: 'below', text: 'declared', frame: rect(0, 500, 180, 30) },
		])])
		mount_focus_fixture(mut w, root)
		w.set_text('below', 'local ñ')
		mount_focus_fixture(mut w, root)
		assert w.text('below') == 'local ñ'
		assert 'below' in w.active_fields
		assert w.focus_next() && w.focused_id() == 'below'
		assert w.scroll_offset('pane') == 430
		mount_focus_fixture(mut w, root)
		assert w.text('below') == 'local ñ' && w.focused_id() == 'below'
		assert w.scroll_offset('pane') == 430
		mount_focus_fixture(mut w, screen(0xffffff, []))
		assert w.focused_id() == '' && 'below' !in w.text_editors
	}

	fn test_custom_nested_scroll_reveals_target_inside_a_taller_inner_viewport() {
		mut w := &Window{}
		mount_focus_fixture(mut w, screen(0xffffff, [scroll('outer', rect(0, 0, 100, 100), 0xffffff, [
			scroll('inner', rect(0, 0, 80, 300), 0xffffff, [Element{ kind: .button, id: 'below', frame: rect(0, 250, 40, 30) }]),
		])]))
		assert w.focus_next() && w.focused_id() == 'below'
		assert w.scroll_offset('inner') == 0 && w.scroll_offset('outer') == 180
		assert (w.semantic_node('below') or { panic('missing button') }).frame == rect(0, 70, 40, 30)
	}

	fn test_custom_automatic_scope_restoration_reveals_its_mounted_destination() {
		mut w := &Window{}
		root := screen(0xffffff, [
			scroll('pane', rect(0, 0, 100, 100), 0xffffff, [Element{ kind: .button, id: 'restore', frame: rect(0, 500, 80, 30) }]),
			Element{ kind: .view, id: 'scope', focus_scope: true, children: [Element{ kind: .button, id: 'inside' }] },
		])
		mount_focus_fixture(mut w, root)
		w.focus('restore')
		assert w.enter_focus_scope('scope')
		w.scroll_offsets[named_scroll_state_id('pane')] = 0
		mount_focus_fixture(mut w, screen(0xffffff, [root.children[0]]))
		assert w.active_focus_scope() == '' && w.focused_id() == 'restore'
		assert w.scroll_offset('pane') == 430
	}

	fn test_custom_hidden_disabled_ancestor_cancels_focus_and_semantic_actions() {
		mut w := &Window{}
		for hide in [false, true] {
			root := focus_input_root()
			mount_focus_fixture(mut w, root)
			w.focus('composite')
			changed := Element{ ...root.children[2], hidden: hide, enabled: hide }
			mount_focus_fixture(mut w, Element{
				...root
				children: [root.children[0], root.children[1], changed]
			})
			assert w.focused_id() == ''
			assert !w.perform_semantic_action('composite', .activate)
			assert (w.semantic_node('composite') or { panic('missing semantics') }).actions.len == 0
		}
	}

	fn test_custom_navigation_state_is_owned_and_discarded_per_window() {
		mut first := &Window{}
		mut second := &Window{}
		mount_focus_fixture(mut first, focus_input_root())
		first.focus('edit')
		assert first.enter_focus_scope('scope')
		assert second.active_focus_scope() == '' && second.focused_id() == ''
		mount_focus_fixture(mut second, focus_input_root())
		second.focus('button')
		assert first.active_focus_scope() == 'scope' && first.focused_id() == 'composite'
		on_cleanup(mut second)
		assert first.active_focus_scope() == 'scope'
		assert second.navigation.nodes.len == 0 && second.active_focus_scope() == ''
	}
}

$if (android || ios || linux || macos || windows) && !ui2_headless ? {
	fn test_custom_dropdown_tab_and_slider_keys_keep_control_meanings() {
		mut w := &Window{}
		mount_focus_fixture(mut w, screen(0xffffff, [
			Element{ kind: .text_field, id: 'before' },
			dropdown('choice', 'one', ['one', 'two'], rect(0, 40, 120, 30), BoxStyle{}, TextStyle{}),
			slider(id: 'volume', min: 0, max: 100, step: 10, value: 20),
		]))
		w.focus('choice')
		assert w.perform_semantic_action('choice', .activate)
		assert w.focused_id() == 'choice' && w.dropdown_id == 'choice'
		assert (w.semantic_node('choice') or { panic('missing dropdown') }).state.expanded
		assert w.handle_focus_key(KeyEvent{ code: .tab }, false)
		assert w.focused_id() == 'volume' && w.dropdown_id == ''
		assert w.handle_focus_key(KeyEvent{ code: .right }, false)
		assert w.handle_focus_key(KeyEvent{ code: .right }, true)
		assert w.slider_value('volume') == 40
		assert w.handle_focus_key(KeyEvent{ code: .left }, false)
		assert w.slider_value('volume') == 30 && w.focused_id() == 'volume'
	}

	fn test_custom_semantic_snapshot_owns_live_edit_text() {
		mut w := &Window{}
		mount_focus_fixture(mut w, focus_input_root())
		w.set_text('edit', 'owned snapshot ñ')
		snapshot := w.semantic_node('edit') or { panic('missing editor') }
		w.set_text('edit', 'changed')
		assert snapshot.value == 'owned snapshot ñ'
		assert (w.semantic_node('edit') or { panic('missing editor') }).value == 'changed'
	}

	fn test_custom_explicit_semantic_value_does_not_replace_live_control_state() {
		mut w := &Window{}
		mount_focus_fixture(mut w, screen(0xffffff, [Element{ kind: .text_field, id: 'edit', text: 'secret model', accessibility_value: 'public summary' }]))
		w.set_text('edit', 'local edit')
		assert (w.semantic_node('edit') or { panic('missing editor') }).value == 'public summary'
		assert w.text('edit') == 'local edit'
	}

	fn test_custom_mounted_editor_actions_do_not_depend_on_painted_hit_targets() {
		mut w := &Window{}
		mount_focus_fixture(mut w, screen(0xffffff, [Element{ kind: .text_field, id: 'edit', text: 'café', on_event: focus_input_event }]))
		w.focus('edit')
		w.hit_targets.clear()
		focus_input_events.clear()
		w.handle_char_input(`ñ`)
		w.handle_key_down(.enter, 0)
		assert focus_input_events == [
			ElementEvent{ window: w, kind: .change, id: 'edit', text: 'caféñ' },
			ElementEvent{ window: w, kind: .submit, id: 'edit', text: 'caféñ' },
		]
		assert w.focused_id() == '' && w.navigation.current == ''
	}
}

$if (android || ios || linux || macos || windows) && !ui2_headless ? {
	fn test_custom_hidden_mounted_inputs_retain_edits_but_cannot_take_focus() {
		mut w := &Window{}
		root := screen(0xffffff, [view('parent', rect(0, 0, 200, 100), BoxStyle{}, [Element{ kind: .text_field, id: 'edit', text: 'declared' }])])
		mount_focus_fixture(mut w, root)
		w.focus('edit')
		w.set_text('edit', 'retained ñ')
		mount_focus_fixture(mut w, Element{ ...root, children: [Element{ ...root.children[0], hidden: true }] })
		assert w.focused_id() == '' && w.text('edit') == 'retained ñ'
		w.focus('edit')
		assert w.focused_id() == ''
		mount_focus_fixture(mut w, root)
		w.focus('edit')
		assert w.focused_id() == 'edit' && w.text('edit') == 'retained ñ'
	}
}

$if (android || ios || linux || macos || windows) && !ui2_headless ? {
	fn test_custom_tab_with_only_programmatic_targets_is_consumed_without_moving() {
		mut w := &Window{}
		mount_focus_fixture(mut w, screen(0xffffff, [Element{ kind: .text_field, id: 'edit', text: 'ñ', tab_index: -1 }]))
		w.focus('edit')
		assert !w.focus_next()
		assert w.handle_focus_key(KeyEvent{ code: .tab }, false)
		assert w.handle_focus_key(KeyEvent{ code: .tab, shift: true }, true)
		assert w.focused_id() == 'edit' && w.text('edit') == 'ñ'
	}

	fn test_custom_background_and_dropdown_focus_changes_release_composition_owner() {
		mut w := &Window{}
		mount_focus_fixture(mut w, screen(0xffffff, [
			Element{ kind: .text_field, id: 'edit', text: 'niño' },
			dropdown('choice', 'one', ['one', 'two'], rect(0, 40, 120, 30), BoxStyle{}, TextStyle{}),
		]))
		w.focus('edit')
		editor := w.text_editors['edit'] or { panic('missing editor') }
		w.composition.update('edit', editor, 'ñ', 1, 0, -1, 0)
		target := w.custom_focus_target(w.navigation.node('choice') or { panic('missing dropdown') })
		w.open_dropdown(target)
		assert w.focused_id() == 'choice' && w.composition.field_id == ''
		w.close_dropdown()
		w.focus('edit')
		w.composition.update('edit', editor, 'ñ', 1, 0, -1, 0)
		w.hit_targets.clear()
		w.handle_touch_down(300, 300)
		w.handle_touch_up(300, 300)
		assert w.focused_id() == '' && w.navigation.current == ''
		assert w.composition.field_id == ''
	}

	fn test_custom_replacing_editor_with_dropdown_releases_editor_and_ime_state() {
		mut w := &Window{}
		mount_focus_fixture(mut w, screen(0xffffff, [Element{ kind: .text_field, id: 'choice', text: 'niño' }]))
		w.focus('choice')
		w.set_text('choice', 'local café')
		editor := w.text_editors['choice'] or { panic('missing editor') }
		w.composition.update('choice', editor, 'ñ', 1, 0, -1, 0)
		mount_focus_fixture(mut w, screen(0xffffff, [dropdown('choice', 'one', ['one', 'two'], rect(0, 0, 120, 30), BoxStyle{}, TextStyle{})]))
		assert w.focused_id() == 'choice'
		assert w.composition.field_id == ''
		w.handle_char_input(`x`)
		w.handle_key_down(.backspace, 0)
		assert w.text('choice') == 'one'
		assert 'choice' !in w.text_editors
		w.set_text('choice', 'two')
		w.handle_char_input(`x`)
		assert w.text('choice') == 'two'
		assert 'choice' !in w.text_editors
		mount_focus_fixture(mut w, screen(0xffffff, [Element{ kind: .text_field, id: 'choice', text: 'fresh ñ' }]))
		w.handle_char_input(`é`)
		assert w.text('choice') == 'fresh ñé'
	}
}
