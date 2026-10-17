@[has_globals]
module ui2

$if (android || ios || linux || macos || windows) && !ui2_headless ? && !ui2_document_library ? {
	fn set_checkbox_checked(mut w Window, id string, checked bool) {
		if id !in w.active_checkboxes {
			return
		}
		w.checkbox_values[id] = checked
		w.invalidate_custom_paint()
	}

	__global custom_control_test_events = []ElementEvent{}
	fn capture_custom_control_event(event ElementEvent) { custom_control_test_events << event }

	fn custom_test_key_handler(mut _ Window, _key string) {}
	fn custom_test_key_event_handler(_event KeyEvent) {}

	fn custom_test_drop_handler(_event DropEvent) {}

	fn test_custom_desktop_backend_defaults() {
		mut w := &Window{}
		assert w.bounds() == Rect{
			width:  800
			height: 600
		}
		assert control_support(.button) == .supported
		assert control_support(.text_field) == .supported
		assert control_support(.dropdown) == .partial
		assert control_support(.text_area) == .partial
	}

	fn test_custom_desktop_backend_exposes_desktop_hooks() {
		mut w := &Window{}
		w.on_key(custom_test_key_handler)
		w.on_key_event(custom_test_key_event_handler)
		w.on_drop(custom_test_drop_handler)
		w.request_refresh()
		w.refresh_element('missing', Element{})
		w.insert_text_area_text('missing', 'text')
		w.scroll_to_rect('missing', 0, 0, 10, 10)
		assert w.scroll_offset('missing') == 0
		assert w.text_area_runs('missing').len == 0
		assert text_area_format_state('missing') == TextFormatState{}
		assert !clipboard_has_image()
		assert !save_clipboard_image_png('unused.png')
		w.quit()
	}

	fn test_custom_text_editor_replaces_owned_state_after_caret_moves() {
		mut w := &Window{}
		defer {
			w.forget_text_state('field')
		}
		root := screen(0xffffff, [Element{ kind: .text_field, id: 'field', text: 'abc' }])
		w.update_custom_focus_tree(root)
		w.sync_mounted_focus_controls(root, 'root')
		w.focus('field')
		w.handle_key_down(.left, 0)
		w.handle_key_down(.backspace, 0)
		w.handle_char_input(`x`)
		assert w.text('field') == 'axc'
	}

	fn test_custom_pointer_callbacks_receive_typed_coordinates() {
		mut w := &Window{}
		custom_control_test_events = []ElementEvent{}
		target := HitTarget{ id: 'surface', on_event: capture_custom_control_event }
		w.fire_pointer_event(.pointer_down, target, 20, 30)
		w.fire_pointer_event(.pointer_drag, target, 40, 50)
		w.fire_pointer_event(.pointer_up, target, 40, 50)
		assert custom_control_test_events == [
			ElementEvent{ window: w, kind: .pointer_down, id: 'surface', x: 20, y: 30 },
			ElementEvent{ window: w, kind: .pointer_drag, id: 'surface', x: 40, y: 50 },
			ElementEvent{ window: w, kind: .pointer_up, id: 'surface', x: 40, y: 50 },
		]
	}

	fn test_custom_button_images_match_native_arrangements() {
		image_only := button_image_layout(30, 28, '', 'symbol:gearshape')
		assert image_only.visible
		assert image_only.image == rect(6, 5, 18, 18)
		assert image_only.text.width == 0

		compact_image_only := button_image_layout(20, 17, '', 'symbol:scissors')
		assert compact_image_only.image == rect(3.5, 2, 13, 13)

		tall_image_only := button_image_layout(44, 58, '', '/tmp/paste.png')
		assert tall_image_only.image == rect(6, 13, 32, 32)

		compact := button_image_layout(100, 24, 'Open', '/tmp/open.png')
		assert compact.image == rect(5, 5.5, 13, 13)
		assert compact.text == rect(22, 0, 74, 24)
		assert compact.has_title_area()

		narrow_compact := button_image_layout(26, 24, 'Open', '/tmp/open.png')
		assert narrow_compact.text.width == 0
		assert !narrow_compact.has_title_area()

		tall := button_image_layout(60, 62, 'Paste', '/tmp/paste.png')
		assert tall.image == rect(14, 4, 32, 32)
		assert tall.text == rect(2, 39, 56, 20)

		text_only := button_image_layout(80, 28, 'Normal', '')
		assert !text_only.visible
		assert text_only.text == rect(0, 0, 80, 28)
	}

	fn test_custom_renderer_has_portable_system_symbol_fallbacks() {
		assert symbol_glyph('arrow.uturn.backward') == ''
		assert symbol_glyph('gearshape') == ''
		assert symbol_glyph('magnifyingglass') == ''
		assert symbol_glyph('xmark') == ''
		assert symbol_glyph('future.symbol') == symbol_unknown_glyph
	}

	fn test_custom_text_navigation_uses_the_platform_primary_modifier() {
		assert !text_navigation_primary_modifier(false, false, false)
		$if macos {
			assert !text_navigation_primary_modifier(true, false, false)
			assert text_navigation_primary_modifier(false, false, true)
			assert text_navigation_word_modifier(false, true)
			assert !text_navigation_word_modifier(true, false)
			assert text_navigation_boundary_modifier(true)
		} $else {
			assert text_navigation_primary_modifier(true, false, false)
			assert !text_navigation_primary_modifier(true, true, false)
			assert text_navigation_word_modifier(true, false)
			assert !text_navigation_word_modifier(true, true)
			assert !text_navigation_boundary_modifier(true)
		}
	}

	fn test_custom_slider_pointer_value_uses_range_step_and_orientation() {
		mut w := &Window{}
		horizontal := HitTarget{
			slider:         true
			slider_frame:   rect(10, 20, 120, 30)
			slider_padding: 10
			slider_spec:    SliderSpec{
				min:  -20
				max:  80
				step: 5
			}
		}
		assert w.slider_target_value(horizontal, 70, 35) == 30

		vertical := HitTarget{
			...horizontal
			slider_frame: rect(10, 20, 30, 120)
			slider_spec:  SliderSpec{
				...horizontal.slider_spec
				orientation: .vertical
			}
		}
		assert w.slider_target_value(vertical, 25, 30) == 80
		assert w.slider_target_value(vertical, 25, 130) == -20
	}

	fn test_custom_slider_value_api_only_updates_mounted_controls() {
		mut w := &Window{}
		w.slider_values = map[string]f64{}
		w.slider_specs = map[string]SliderSpec{
			'volume': SliderSpec{
				min: -20
				max: 80
			}
		}
		w.active_sliders = map[string]bool{
			'volume': true
		}
		w.set_slider_value('volume', 120)
		w.set_slider_value('missing', 40)
		assert w.slider_value('volume') == 80
		assert w.slider_value('missing') == 0
		w.slider_values = map[string]f64{}
		w.slider_specs = map[string]SliderSpec{}
		w.active_sliders = map[string]bool{}
	}

	fn test_custom_slider_change_payload_uses_committed_value_and_suppresses_duplicates() {
		mut w := &Window{}
		previous_values := w.slider_values.clone()
		defer { w.slider_values = previous_values.clone() }
		w.slider_values = {
			'volume': -20.0
		}
		custom_control_test_events = []ElementEvent{}
		target := HitTarget{
			id:             'volume'
			on_event:       capture_custom_control_event
			slider:         true
			slider_frame:   rect(10, 20, 120, 30)
			slider_padding: 10
			slider_spec:    SliderSpec{ min: -20, max: 80, step: 5 }
		}
		w.commit_slider(target, 70, 35)
		w.commit_slider(target, 70, 35)
		assert w.slider_value('volume') == 30
		assert custom_control_test_events == [ElementEvent{ window: w, kind: .change, id: 'volume', value: 30 }]
	}

	fn test_custom_text_field_callback_receives_committed_change_and_submit_text() {
		mut w := &Window{}
		defer {
			w.forget_text_state('editor')
		}
		root := screen(0xffffff, [Element{ kind: .text_field, id: 'editor', text: 'café:', on_event: capture_custom_control_event }])
		w.update_custom_focus_tree(root)
		w.sync_mounted_focus_controls(root, 'root')
		w.focus('editor')
		mut editor := w.text_editors['editor'] or { panic('missing editor') }
		editor.set_caret(editor.text.runes().len)
		w.replace_text_editor('editor', editor)
		custom_control_test_events = []ElementEvent{}
		w.handle_char_input(u32(`ñ`))
		w.handle_key_down(.enter, 0)
		assert custom_control_test_events == [
			ElementEvent{ window: w, kind: .change, id: 'editor', text: 'café:ñ' },
			ElementEvent{ window: w, kind: .submit, id: 'editor', text: 'café:ñ' },
		]
		assert w.focused_id() == ''
	}

	fn test_custom_switch_tap_and_drag_update_live_state() {
		mut w := &Window{}
		custom_control_test_events = []ElementEvent{}
		w.switch_values = map[string]bool{
			'network': false
		}
		w.active_switches = map[string]bool{
			'network': true
		}
		target := HitTarget{
			id:             'network'
			on_event:       capture_custom_control_event
			x:              10
			y:              20
			w:              80
			h:              32
			switch_control: true
		}
		w.hit_targets = [target]
		w.handle_touch_down(20, 30)
		w.handle_touch_up(20, 30)
		assert w.switch_active('network')
		w.set_switch_active('network', false)
		w.handle_touch_down(20, 30)
		w.handle_touch_move(80, 30)
		w.handle_touch_up(80, 30)
		assert w.switch_active('network')
		w.set_switch_active('network', false)
		assert !w.switch_active('network')
		w.set_switch_active('network', true)
		w.set_switch_active('missing', true)
		assert w.switch_active('network')
		assert !w.switch_active('missing')
		assert custom_control_test_events == [
			ElementEvent{ window: w, kind: .change, id: 'network', checked: true },
			ElementEvent{ window: w, kind: .change, id: 'network', checked: true },
		]
		w.switch_values = map[string]bool{}
		w.switch_declared = map[string]bool{}
		w.active_switches = map[string]bool{}
		w.hit_targets = []HitTarget{}
		w.touch = TouchState{}
	}

	fn test_custom_checkbox_tap_updates_live_checked_state() {
		mut w := &Window{}
		custom_control_test_events = []ElementEvent{}
		w.checkbox_values = map[string]bool{
			'newsletter': false
		}
		w.active_checkboxes = map[string]bool{
			'newsletter': true
		}
		w.hit_targets = [HitTarget{
			id:       'newsletter'
			on_event: capture_custom_control_event
			x:        10
			y:        20
			w:        120
			h:        28
			checkbox: true
		}]
		w.handle_touch_down(20, 30)
		w.handle_touch_up(20, 30)
		assert w.checkbox_checked('newsletter')
		set_checkbox_checked(mut w, 'newsletter', false)
		set_checkbox_checked(mut w, 'missing', true)
		assert !w.checkbox_checked('newsletter')
		assert !w.checkbox_checked('missing')
		assert custom_control_test_events == [ElementEvent{ window: w, kind: .change, id: 'newsletter', checked: true }]
		w.checkbox_values = map[string]bool{}
		w.checkbox_declared = map[string]bool{}
		w.active_checkboxes = map[string]bool{}
		w.hit_targets = []HitTarget{}
		w.touch = TouchState{}
	}

	fn test_custom_checkbox_drag_preserves_scrolling_without_toggling() {
		mut w := &Window{}
		w.checkbox_values = map[string]bool{
			'newsletter': false
		}
		w.active_checkboxes = map[string]bool{
			'newsletter': true
		}
		w.hit_targets = [HitTarget{
			id:       'newsletter'
			x:        10
			y:        60
			w:        120
			h:        28
			checkbox: true
		}]
		w.scroll_areas = map[string]Rect{
			named_scroll_state_id('form'): rect(0, 0, 160, 160)
		}
		w.scroll_viewports = map[string]Rect{
			named_scroll_state_id('form'): rect(0, 0, 160, 160)
		}
		w.scroll_order = [named_scroll_state_id('form')]
		w.scroll_content_h = map[string]f64{
			named_scroll_state_id('form'): 320
		}
		w.scroll_offsets = map[string]f64{}
		w.handle_touch_down(20, 70)
		w.handle_touch_move(20, 20)
		w.handle_touch_up(20, 20)
		assert w.scroll_offset('form') == 50
		assert !w.checkbox_checked('newsletter')
		w.checkbox_values = map[string]bool{}
		w.checkbox_declared = map[string]bool{}
		w.active_checkboxes = map[string]bool{}
		w.hit_targets = []HitTarget{}
		w.reset_scroll_frame()
		w.scroll_content_h = map[string]f64{}
		w.scroll_offsets = map[string]f64{}
		w.touch = TouchState{}
	}

	fn test_custom_toggle_button_updates_live_pressed_state() {
		mut w := &Window{}
		custom_control_test_events = []ElementEvent{}
		w.toggle_values = map[string]bool{
			'bold': false
		}
		w.active_toggles = map[string]bool{
			'bold': true
		}
		w.toggle_groups = map[string]string{
			'bold': ''
		}
		w.toggle_allow_no_selection = map[string]bool{
			'bold': true
		}
		w.hit_targets = [HitTarget{
			id:            'bold'
			on_event:      capture_custom_control_event
			x:             10
			y:             20
			w:             80
			h:             32
			toggle_button: true
		}]
		w.handle_touch_down(20, 30)
		w.handle_touch_up(20, 30)
		assert w.toggle_button_pressed('bold')
		w.set_toggle_button_pressed('bold', false)
		w.set_toggle_button_pressed('missing', true)
		assert !w.toggle_button_pressed('bold')
		assert !w.toggle_button_pressed('missing')
		assert custom_control_test_events == [ElementEvent{ window: w, kind: .change, id: 'bold', checked: true }]
		w.toggle_values = map[string]bool{}
		w.toggle_declared = map[string]bool{}
		w.toggle_groups = map[string]string{}
		w.toggle_allow_no_selection = map[string]bool{}
		w.active_toggles = map[string]bool{}
		w.hit_targets = []HitTarget{}
		w.touch = TouchState{}
	}

	fn test_custom_toggle_button_groups_are_exclusive() {
		mut w := &Window{}
		w.toggle_values = map[string]bool{
			'left':  true
			'right': false
		}
		w.toggle_groups = map[string]string{
			'left':  'alignment'
			'right': 'alignment'
		}
		w.toggle_allow_no_selection = map[string]bool{
			'left':  false
			'right': false
		}
		w.active_toggles = map[string]bool{
			'left':  true
			'right': true
		}
		w.commit_toggle_button(HitTarget{
			id:                        'right'
			toggle_button:             true
			toggle_group:              'alignment'
			toggle_allow_no_selection: false
		})
		assert !w.toggle_button_pressed('left')
		assert w.toggle_button_pressed('right')
		w.commit_toggle_button(HitTarget{
			id:                        'right'
			toggle_button:             true
			toggle_group:              'alignment'
			toggle_allow_no_selection: false
		})
		assert w.toggle_button_pressed('right')
		w.commit_toggle_button(HitTarget{
			id:                        'right'
			toggle_button:             true
			toggle_group:              'alignment'
			toggle_allow_no_selection: true
		})
		assert !w.toggle_button_pressed('left')
		assert !w.toggle_button_pressed('right')
		w.set_toggle_button_pressed('left', true)
		assert w.toggle_button_pressed('left')
		assert !w.toggle_button_pressed('right')
		mut members := w.toggle_button_group_members('left')
		members.sort()
		assert members == ['left', 'right']
		w.toggle_values = map[string]bool{}
		w.toggle_declared = map[string]bool{}
		w.toggle_groups = map[string]string{}
		w.toggle_allow_no_selection = map[string]bool{}
		w.active_toggles = map[string]bool{}
	}

	fn test_custom_dropdown_popup_opens_below_its_control() {
		row_height := dropdown_row_height(TextStyle{})
		assert row_height == 28
		frame := dropdown_popup_frame(rect(16, 40, 200, 42), 3, row_height, rect(0, 0, 320, 400))
		assert frame.x == 16
		assert frame.y == 86
		assert frame.width == 200
		assert frame.height == 3 * row_height + 8
	}

	fn test_custom_dropdown_popup_flips_above_when_more_rows_fit() {
		frame := dropdown_popup_frame(rect(16, 150, 200, 30), 4, 28, rect(0, 0, 320, 220))
		assert frame.height == 4 * 28 + 8
		assert frame.y == 26
	}

	fn test_custom_dropdown_popup_shows_whole_rows_inside_the_window() {
		frame := dropdown_popup_frame(rect(150, 60, 120, 30), 6, 28, rect(0, 0, 200, 160))
		assert frame.height == 28 + 8
		assert frame.y == 94
		assert frame.x == 76
	}

	fn test_custom_dropdown_scroll_reveals_the_selected_row() {
		mut w := &Window{}
		w.dropdown_popup = DropdownPopup{
			id:         'menu'
			options:    ['a', 'b', 'c', 'd', 'e', 'f']
			row_height: 28
			height:     2 * 28 + 8
			max_scroll: 4 * 28
			selected:   5
		}
		w.dropdown_scroll = 0
		w.reveal_dropdown_row(5)
		assert w.dropdown_scroll == 4 * 28
		w.reveal_dropdown_row(0)
		assert w.dropdown_scroll == 0
		assert w.clamped_dropdown_scroll(1000) == 4 * 28
		assert w.clamped_dropdown_scroll(-10) == 0
		w.close_dropdown()
		assert w.dropdown_scroll == 0
		assert w.dropdown_popup.options.len == 0
	}

	fn test_custom_dropdown_click_opens_a_list_instead_of_cycling() {
		mut w := &Window{}
		mount_custom_test_dropdown(mut w, 'menu-click')
		custom_control_test_events = []ElementEvent{}
		w.close_dropdown()
		target := HitTarget{
			id:       'menu-click'
			on_event: capture_custom_control_event
			dropdown: true
			options:  ['One', 'Two', 'Three']
		}
		w.open_dropdown(target)
		assert w.dropdown_id == 'menu-click'
		assert w.text('menu-click') == ''
		w.select_dropdown_option(HitTarget{
			...target
			dropdown_option: true
			option_index:    2
		})
		assert w.dropdown_id == ''
		assert w.text('menu-click') == 'Three'
		assert custom_control_test_events == [ElementEvent{ window: w, kind: .change, id: 'menu-click', text: 'Three' }]
	}

	fn test_custom_dropdown_without_an_id_only_reports_the_tap() {
		mut w := &Window{}
		custom_control_test_events = []ElementEvent{}
		w.close_dropdown()
		w.open_dropdown(HitTarget{
			on_event: capture_custom_control_event
			dropdown: true
			options:  ['One']
		})
		assert w.dropdown_id == ''
		assert custom_control_test_events == [ElementEvent{ window: w, kind: .click }]
	}

	fn test_custom_dropdown_keys_move_the_highlight_and_commit() {
		mut w := &Window{}
		custom_control_test_events = []ElementEvent{}
		w.close_dropdown()
		w.dropdown_id = 'menu-keys'
		w.dropdown_popup = DropdownPopup{
			id:         'menu-keys'
			on_event:   capture_custom_control_event
			options:    ['One', 'Two', 'Three']
			row_height: 28
			height:     3 * 28 + 8
			mounted:    true
		}
		assert w.handle_dropdown_key(.down)
		assert w.dropdown_hover == 0
		assert w.handle_dropdown_key(.up)
		assert w.dropdown_hover == 2
		assert w.handle_dropdown_key(.tab) == false
		assert w.handle_dropdown_key(.enter)
		assert w.dropdown_id == ''
		assert w.text('menu-keys') == 'Three'
		assert custom_control_test_events == [ElementEvent{ window: w, kind: .change, id: 'menu-keys', text: 'Three' }]
	}

	// The control sits at 32,70 296x42 and the list rows the popup registers on
	// the next frame start at y 120, matching the dropdown example's layout.
	fn mount_custom_test_dropdown(mut w Window, id string) {
		root := screen(0xffffff, [Element{
			kind:     .dropdown
			id:       id
			on_event: capture_custom_control_event
			frame:    rect(32, 70, 296, 42)
			menu:     [MenuEntry{ title: 'One' }, MenuEntry{ title: 'Two' },
				MenuEntry{ title: 'Three' }]
		}])
		w.update_custom_focus_tree(root)
		w.sync_mounted_focus_controls(root, 'root')
	}

	fn custom_test_dropdown_targets(id string) []HitTarget {
		options := ['One', 'Two', 'Three']
		mut targets := [
			HitTarget{
				kind:     .dropdown
				id:       id
				on_event: capture_custom_control_event
				x:        32
				y:        70
				w:        296
				h:        42
				dropdown: true
				options:  options
			},
		]
		for index in 0 .. options.len {
			targets << HitTarget{
				kind:            .dropdown
				id:              id
				on_event:        capture_custom_control_event
				x:               32
				y:               120 + f64(index) * 28
				w:               296
				h:               28
				dropdown_option: true
				option_index:    index
				options:         options
			}
		}
		return targets
	}

	fn test_custom_dropdown_pointer_flow_picks_a_row_from_the_list() {
		mut w := &Window{}
		mount_custom_test_dropdown(mut w, 'menu-pick')
		custom_control_test_events = []ElementEvent{}
		w.close_dropdown()
		targets := custom_test_dropdown_targets('menu-pick')
		w.hit_targets = [targets[0]]
		w.handle_touch_down(100, 90)
		w.handle_touch_up(100, 90)
		assert w.dropdown_id == 'menu-pick'
		assert w.text('menu-pick') == ''
		w.hit_targets = targets.clone()
		w.handle_touch_down(100, 160)
		assert w.dropdown_hover == 1
		w.handle_touch_up(100, 160)
		assert w.dropdown_id == ''
		assert w.text('menu-pick') == 'Two'
		assert custom_control_test_events == [ElementEvent{ window: w, kind: .change, id: 'menu-pick', text: 'Two' }]
		w.hit_targets = []HitTarget{}
	}

	fn test_custom_dropdown_pointer_flow_dismisses_on_an_outside_click() {
		mut w := &Window{}
		mount_custom_test_dropdown(mut w, 'menu-dismiss')
		w.close_dropdown()
		targets := custom_test_dropdown_targets('menu-dismiss')
		w.hit_targets = [targets[0]]
		w.handle_touch_down(100, 90)
		w.handle_touch_up(100, 90)
		assert w.dropdown_id == 'menu-dismiss'
		w.hit_targets = targets.clone()
		w.handle_touch_down(100, 300)
		assert w.dropdown_hover == -1
		w.handle_touch_up(100, 300)
		assert w.dropdown_id == ''
		assert w.text('menu-dismiss') == ''
		w.hit_targets = [targets[0]]
		w.handle_touch_down(100, 90)
		w.handle_touch_up(100, 90)
		assert w.dropdown_id == 'menu-dismiss'
		w.handle_touch_down(100, 90)
		w.handle_touch_up(100, 90)
		assert w.dropdown_id == ''
		assert w.text('menu-dismiss') == ''
		w.hit_targets = []HitTarget{}
	}

	fn test_custom_dropdown_escape_closes_the_list() {
		mut w := &Window{}
		w.close_dropdown()
		w.dropdown_id = 'menu-escape'
		w.dropdown_popup = DropdownPopup{
			id:         'menu-escape'
			options:    ['One', 'Two']
			row_height: 28
			height:     2 * 28 + 8
			mounted:    true
		}
		assert w.handle_dropdown_key(.escape)
		assert w.dropdown_id == ''
		assert w.text('menu-escape') == ''
	}

	fn test_custom_button_press_state_follows_the_pointer() {
		mut w := &Window{}
		w.touch = TouchState{}
		assert !w.touch_is_held_inside(10, 10, 100, 30)
		w.touch = TouchState{
			down:      true
			start_x:   20
			start_y:   20
			current_x: 20
			current_y: 20
		}
		assert w.touch_is_held_inside(10, 10, 100, 30)
		// Held down, but dragged off the button.
		w.touch.current_x = 300
		assert !w.touch_is_held_inside(10, 10, 100, 30)
		// A press that began elsewhere does not light up what it passes over.
		w.touch = TouchState{
			down:      true
			start_x:   300
			start_y:   20
			current_x: 20
			current_y: 20
		}
		assert !w.touch_is_held_inside(10, 10, 100, 30)
		w.touch = TouchState{}
	}
}

fn test_text_field_selection_text_uses_rune_offsets() {
	$if (android || ios) && !ui2_headless ? {
		before, selected := text_field_selection_text('a🙂bc', TextSelection{
			anchor: 4
			caret:  1
		})
		assert before == 'a'
		assert selected == '🙂bc'
	}
}

fn test_text_field_selection_origin_respects_text_alignment() {
	$if (android || ios || linux || macos || windows) && !ui2_headless ? {
		assert text_field_aligned_text_origin(10, 100, 40, .left) == 10
		assert text_field_aligned_text_origin(10, 100, 40, .center) == 40
		assert text_field_aligned_text_origin(10, 100, 40, .right) == 70
	}
}
