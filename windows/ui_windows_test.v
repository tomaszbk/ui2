module ui2

$if !ui2_custom_rendering ? {
	// Import the clipboard alongside ui2's native backend.
	// V's Windows clipboard module declares C.DestroyWindow(HWND).  The native
	// backend must not declare that symbol with a different V signature; it uses
	// the ui2_win_destroy(voidptr) wrapper instead.
	import clipboard

	__global windows_accessibility_events = []string{}

	fn capture_windows_accessibility_event(event ElementEvent) {
		assert event.kind == .tap
		windows_accessibility_events << event.id
	}

	fn test_windows_backend_compiles_with_clipboard() {
		mut system_clipboard := clipboard.new()
		assert system_clipboard != unsafe { nil }
		system_clipboard.free()
	}

	fn test_windows_font_presentation_uses_logical_size_and_device_dpi() {
		// Independently specified rounded physical em heights for an 18.25-unit font.
		for index, dpi in [u32(96), 120, 144, 192] {
			assert C.ui2_win_logical_font_height(18.25, dpi) == [-18, -23, -27, -37][index]
		}
		assert C.ui2_win_logical_font_height(0, 96) == -15
		assert C.ui2_win_logical_font_height(0.25, 96) == -1
		assert C.ui2_win_logical_font_height(18.25, 0) == -18
	}

	fn test_windows_virtual_keys_map_to_portable_key_codes() {
		assert windows_key_code(0x4e) == .n
		assert windows_key_code(0xbc) == .comma
		assert windows_key_code(0x71) == .f2
		assert windows_key_code(0xffff) == .invalid
	}

	fn test_windows_widget_kind_mapping_covers_every_native_control() {
		assert windows_widget_kind(.screen) == 0
		assert windows_widget_kind(.view) == 1
		assert windows_widget_kind(.scroll) == 2
		assert windows_widget_kind(.label) == 3
		assert windows_widget_kind(.image) == 4
		assert windows_widget_kind(.button) == 5
		assert windows_widget_kind(.checkbox) == 9
		assert windows_widget_kind(.dropdown) == 6
		assert windows_widget_kind(.text_field) == 7
		assert windows_widget_kind(.text_area) == 8
		assert windows_widget_kind(.slider) == 10
		assert windows_widget_kind(.switch_control) == 11
		assert windows_widget_kind(.toggle_button) == 12
	}

	fn test_windows_structural_transitions_recreate_controls() {
		plain := Element{
			kind: .text_field
		}
		secure := Element{
			kind:   .text_field
			secure: true
		}
		assert windows_structural_signature(plain) != windows_structural_signature(secure)

		area := Element{
			kind: .text_area
		}
		area_without_scroll := Element{
			kind:           .text_area
			disable_scroll: true
		}
		assert windows_structural_signature(area) != windows_structural_signature(area_without_scroll)

		styled_button := Element{
			kind:         .button
			native_style: true
		}
		plain_button := Element{
			kind: .button
		}
		assert windows_structural_signature(styled_button) != windows_structural_signature(plain_button)

		horizontal_slider := Element{
			kind: .slider
		}
		vertical_slider := Element{
			kind:        .slider
			orientation: .vertical
		}
		assert windows_structural_signature(horizontal_slider) != windows_structural_signature(vertical_slider)
	}

	fn test_windows_scroll_content_height_uses_child_extent() {
		children := [
			Element{
				kind:  .label
				frame: rect(0, 10, 50, 20)
			},
			Element{
				kind:  .button
				frame: rect(0, 80, 50, 35)
			},
		]
		assert windows_content_height(children) == 115
	}

	fn test_windows_composite_button_release_requires_current_registration() {
		captured := WindowsPointerBinding{ id: 'original', on_event: capture_windows_accessibility_event, button_behavior: true }
		current := WindowsPointerBinding{ id: 'replacement', on_event: capture_windows_accessibility_event, button_behavior: true }
		assert windows_button_behavior_available(captured, current, false, false, true)
		assert !windows_button_behavior_available(captured, WindowsPointerBinding{}, false, false, true)
		assert !windows_button_behavior_available(captured, WindowsPointerBinding{ on_event: capture_windows_accessibility_event, clickable: true }, false, false, true)
		assert !windows_button_behavior_available(captured, WindowsPointerBinding{ button_behavior: true }, false, false, true)
		assert !windows_button_behavior_available(captured, current, true, false, true)
		assert !windows_button_behavior_available(captured, current, false, true, true)
		assert !windows_button_behavior_available(captured, current, false, false, false)
		assert windows_button_behavior_accessibility_available(current, true)
		assert !windows_button_behavior_accessibility_available(WindowsPointerBinding{}, true)
		assert !windows_button_behavior_accessibility_available(WindowsPointerBinding{ on_event: capture_windows_accessibility_event, clickable: true }, true)
		assert !windows_button_behavior_accessibility_available(current, false)
		assert windows_button_accessibility_caption('Save & close') == 'Save && close'
		// Registration, not a nonempty id, makes an anonymous composite actionable.
		anonymous := WindowsPointerBinding{ on_event: capture_windows_accessibility_event, button_behavior: true }
		assert windows_button_behavior_available(anonymous, anonymous, false, false, true)
		windows_accessibility_events = []string{}
		if windows_button_behavior_available(captured, current, false, false, true) {
			windows_emit_callback(captured.on_event, ElementEvent{ id: captured.id, kind: .tap })
		}
		assert windows_accessibility_events == ['original']
		windows_accessibility_events = []string{}
	}

	fn test_windows_composite_button_exposes_native_accessibility_and_invoke() {
		assert C.ui2_win_register_classes() != 0
		title := 'accessibility test'.to_wide()
		root := C.ui2_win_create_main_window(title, 320, 200)
		unsafe { free(title) }
		assert root != unsafe { nil }
		empty := ''.to_wide()
		button := C.ui2_win_create_widget(windows_widget_kind(.view), root, 0, 0, 200,
			48, empty, 0, 0, 0, 0, 0)
		field := C.ui2_win_create_widget(windows_widget_kind(.text_field), root, 0, 56,
			200, 32, empty, 0, 0, 0, 0, 0)
		child_label := C.ui2_win_create_widget(windows_widget_kind(.label), button, 8, 8,
			184, 32, empty, 0, 0, 0, 0, 0)
		unsafe { free(empty) }
		assert button != unsafe { nil }
		assert field != unsafe { nil }
		assert child_label != unsafe { nil }

		mut st := windows_state()
		old_bindings := st.pointer_bindings.clone()
		defer {
			st.pointer_bindings = old_bindings
			windows_accessibility_events = []string{}
			C.ui2_win_destroy(root)
			C.ui2_win_shutdown_accessibility()
		}

		label := 'Save & close'
		caption := windows_button_accessibility_caption(label).to_wide()
		C.ui2_win_configure_accessible_button(button, caption, 1)
		unsafe { free(caption) }
		assert C.ui2_win_is_accessible_button(button) != 0
		assert C.ui2_win_widget_style(button) & usize(0x00010000) != 0

		expected_name := label.to_wide()
		info := C.ui2_win_accessible_button_info(button, expected_name)
		unsafe { free(expected_name) }
		assert info & u32(1) != 0 // ROLE_SYSTEM_PUSHBUTTON
		assert info & u32(2) != 0 // literal accessible name
		assert info & u32(4) != 0 // Press/default action
		assert info & u32(8) != 0 // keyboard focusable

		// A composite remains in the flattened tab order even though its container
		// also exposes children through WS_EX_CONTROLPARENT.
		C.ui2_win_show(root, 1)
		mut navigation := FocusManager{}
		navigation.update(Element{kind: .screen, children: [
			Element{kind: .view, id: 'save', button_behavior: true},
			Element{kind: .text_field, id: 'edit'},
		]}, map[string]f64{})
		assert navigation.set_focus('edit')
		assert navigation.traverse(false) && navigation.current == 'save'
		C.ui2_win_focus(button)
		assert C.ui2_win_focus_handle() == button
		assert navigation.traverse(false) && navigation.current == 'edit'
		C.ui2_win_focus(field)
		assert C.ui2_win_focus_handle() == field
		C.ui2_win_show(root, 0)

		windows_accessibility_events = []string{}
		st.pointer_bindings[windows_handle_id(button)] = WindowsPointerBinding{
			id:              'save'
			button_behavior: true
		}
		assert ui2_windows_accessibility_activate(button) == 0
		st.pointer_bindings[windows_handle_id(button)] = WindowsPointerBinding{
			id:              'save'
			on_event:        capture_windows_accessibility_event
			button_behavior: true
		}
		assert C.ui2_win_accessible_button_invoke(button) != 0
		C.ui2_win_dispatch_pending_messages()
		assert windows_accessibility_events == ['save']

		st.pointer_bindings[windows_handle_id(button)] = WindowsPointerBinding{
			id:              'replacement'
			on_event:        capture_windows_accessibility_event
			button_behavior: true
		}
		C.ui2_win_click(button)
		assert windows_accessibility_events == ['save', 'replacement']

		st.pointer_bindings.delete(windows_handle_id(button))
		C.ui2_win_enable(button, 0)
		disabled_name := label.to_wide()
		disabled_info := C.ui2_win_accessible_button_info(button, disabled_name)
		unsafe { free(disabled_name) }
		assert disabled_info & u32(16) != 0 // STATE_SYSTEM_UNAVAILABLE
		C.ui2_win_click(button)
		assert windows_accessibility_events == ['save', 'replacement']

		empty_caption := ''.to_wide()
		C.ui2_win_configure_accessible_button(button, empty_caption, 0)
		unsafe { free(empty_caption) }
		assert C.ui2_win_is_accessible_button(button) == 0
		assert C.ui2_win_widget_style(button) & usize(0x00010000) == 0
	}

	fn test_windows_transparent_push_buttons_use_custom_painting() {
		transparent := BoxStyle{
			transparent: true
		}
		assert windows_uses_transparent_button_paint(.button, transparent)
		assert windows_uses_transparent_button_paint(.toggle_button, transparent)
		assert !windows_uses_transparent_button_paint(.button, BoxStyle{})
		assert !windows_uses_transparent_button_paint(.checkbox, transparent)
	}

	fn test_windows_labels_never_paint_a_background_of_their_own() {
		// The default box is opaque white, so a label carrying it must still be
		// left alone: the view holding one paints what a label paints, and a label
		// given a border or a tooltip cannot come out white on a coloured parent.
		assert windows_draws_no_background(.label, BoxStyle{})
		assert windows_draws_no_background(.checkbox, BoxStyle{})
		assert windows_draws_no_background(.label, BoxStyle{
			border_left: 1
		})
		assert !windows_draws_no_background(.view, BoxStyle{})
		assert !windows_draws_no_background(.button, BoxStyle{})
		assert windows_draws_no_background(.view, BoxStyle{
			transparent: true
		})
	}

	fn windows_test_font_family(font voidptr) string {
		mut buffer := []u16{len: 32}
		C.ui2_win_font_family(font, unsafe { &buffer[0] }, buffer.len)
		return unsafe { string_from_wide(&buffer[0]) }
	}

	fn test_windows_font_glyph_key_only_tracks_characters_that_may_need_a_fallback() {
		assert windows_font_glyph_key('Bond, James') == ''
		assert windows_font_glyph_key('Andr\u00e9') == ''
		assert windows_font_glyph_key('\u2713 Bond, James') == '2713'
		assert windows_font_glyph_key('\u2713\u2713') == '2713'
		assert windows_font_glyph_key('\U0001f642\u2713') == '2713.1f642'
	}

	fn test_windows_font_text_covers_every_string_a_control_draws() {
		field := Element{
			kind:        .text_field
			text:        'Andr\u00e9'
			placeholder: 'Name'
		}
		assert windows_font_text(field) == 'Andr\u00e9Name'

		dropdown := Element{
			kind: .dropdown
			text: 'one'
			menu: [MenuEntry{
				id:    'two'
				title: '\u2713 two'
			}]
		}
		assert windows_font_text(dropdown) == 'one\u2713 two'

		// Context menu entries are drawn by the menu, not by the control font.
		button := Element{
			kind: .button
			text: 'Create'
			menu: [MenuEntry{
				id:    'copy'
				title: 'Copy'
			}]
		}
		assert windows_font_text(button) == 'Create'
	}

	fn test_windows_fonts_fall_back_to_a_family_that_has_the_glyphs() {
		default_family := ''.to_wide()
		plain := 'Bond, James'.to_wide()
		symbols := '\u2713 Bond, James'.to_wide()
		plain_font := C.ui2_win_create_font(unsafe { nil }, 13, default_family, 0, 0, 0,
			0, plain)
		symbol_font := C.ui2_win_create_font(unsafe { nil }, 13, default_family, 0, 0, 0,
			0, symbols)
		assert plain_font != unsafe { nil }
		assert symbol_font != unsafe { nil }
		// Text the UI font can draw keeps the UI font.
		assert windows_test_font_family(plain_font) == 'Segoe UI'
		assert C.ui2_win_font_missing_glyphs(plain_font, plain) == 0
		// A check mark is not in Segoe UI, so it must come from another family.
		assert C.ui2_win_font_missing_glyphs(symbol_font, symbols) == 0
		C.ui2_win_delete_object(plain_font)
		C.ui2_win_delete_object(symbol_font)
		unsafe {
			free(default_family)
			free(plain)
			free(symbols)
		}
	}

	fn test_windows_native_buttons_keep_the_system_font_until_glyphs_are_missing() {
		assert C.ui2_win_register_classes() != 0
		title := 'font test'.to_wide()
		root := C.ui2_win_create_main_window(title, 320, 200)
		unsafe {
			free(title)
		}
		assert root != unsafe { nil }
		defer {
			C.ui2_win_destroy(root)
			C.ui2_win_shutdown_accessibility()
		}

		plain := 'Bond, James'.to_wide()
		symbols := '\u2713 Bond, James'.to_wide()
		button := C.ui2_win_create_widget(windows_widget_kind(.button), root, 0, 0, 200,
			30, plain, 0, 0, 0, 0, 0)
		assert button != unsafe { nil }
		system_font := C.ui2_win_widget_font(button)
		C.ui2_win_apply_text_font(button, plain)
		assert C.ui2_win_widget_font(button) == system_font

		C.ui2_win_apply_text_font(button, symbols)
		assert C.ui2_win_font_missing_glyphs(C.ui2_win_widget_font(button), symbols) == 0
		unsafe {
			free(plain)
			free(symbols)
		}
	}

	fn test_windows_native_controls_keep_compact_text_layout() {
		assert C.ui2_win_register_classes() != 0
		assert C.ui2_win_visual_styles_enabled() != 0
		title := 'layout test'.to_wide()
		root := C.ui2_win_create_main_window(title, 320, 200)
		unsafe {
			free(title)
		}
		assert root != unsafe { nil }
		defer {
			C.ui2_win_destroy(root)
			C.ui2_win_shutdown_accessibility()
		}

		empty := ''.to_wide()
		field := C.ui2_win_create_widget(windows_widget_kind(.text_field), root, 0, 0, 200, 32, empty, 0, 0, 0, 0, 0)
		placeholder := 'First name'.to_wide()
		C.ui2_win_set_edit_options(field, placeholder, 0, 12)
		assert C.ui2_win_placeholder_matches(field, placeholder) != 0

		label := C.ui2_win_create_widget(windows_widget_kind(.label), root, 0, 40, 200, 32, empty, 0, 0, 0, 0, 0)
		checkbox := C.ui2_win_create_widget(windows_widget_kind(.checkbox), root, 0, 80, 210, 30, empty, 0, 0, 0, 0, 0)
		switch_view := C.ui2_win_create_widget(windows_widget_kind(.switch_control), root, 0, 120, 60, 32, empty, 0, 0, 0, 0, 0)
		// A label is placed by measuring it now, so it no longer asks the control to
		// centre a line on its behalf: SS_CENTERIMAGE is gone and SS_NOTIFY remains.
		assert C.ui2_win_widget_style(label) & usize(0x0200) == 0
		assert C.ui2_win_widget_style(label) & usize(0x0100) != 0
		measured_text := 'measured label'.to_wide()
		measured := C.ui2_win_create_widget(windows_widget_kind(.label), root, 0, 160,
			200, 32, measured_text, 0, 0, 0, 0, 0)
		unsafe {
			free(measured_text)
		}
		// One line is the font's own height; a budget of several lines wraps and is
		// capped to that budget rather than growing with the text.
		single := C.ui2_win_label_content_height(measured, 200, 1)
		assert single > 0
		assert C.ui2_win_label_content_height(measured, 40, 3) <= single * 3
		assert C.ui2_win_label_content_height(measured, 40, 3) >= single
		assert C.ui2_win_widget_style(checkbox) & usize(0x2000) == 0
		assert C.ui2_win_widget_style(switch_view) & usize(0x1000) != 0
		C.ui2_win_set_checked(switch_view, 1)
		assert C.ui2_win_get_checked(switch_view) != 0

		unsafe {
			free(empty)
			free(placeholder)
		}
	}

	__global windows_control_test_handlers = []string{}
	__global windows_control_test_events = []ElementEvent{}

	fn capture_windows_control_a(event ElementEvent) {
		windows_control_test_handlers << 'a'
		windows_control_test_events << event
	}

	fn capture_windows_control_b(event ElementEvent) {
		windows_control_test_handlers << 'b'
		windows_control_test_events << event
	}

	fn test_windows_ordinary_control_press_keeps_callback_and_cancels_without_current_registration() {
		first := WindowsCallbackBinding{ id: 'same', on_event: capture_windows_control_a, kind: .button, event: .tap }
		second := WindowsCallbackBinding{ ...first, on_event: capture_windows_control_b }
		windows_control_test_handlers = []string{}
		windows_control_test_events = []ElementEvent{}
		selected := windows_control_release_binding(first, second, true) or { panic('eligible native control must activate') }
		assert windows_emit_callback(selected.on_event, ElementEvent{ id: selected.id, kind: selected.event })
		assert windows_control_test_handlers == ['a']
		assert windows_control_test_events[0].id == 'same'
		if _ := windows_control_release_binding(first, second, false) {
			assert false, 'disabled/hidden/cancelled native control must cancel'
		}
		if _ := windows_control_release_binding(first, WindowsCallbackBinding{}, true) {
			assert false, 'removed native control must cancel'
		}
		if _ := windows_control_release_binding(WindowsCallbackBinding{}, second, true) {
			assert false, 'callback installed after press cannot take over'
		}
	}
	fn test_windows_cancelled_pointer_does_not_swallow_later_keyboard_activation() {
		first := WindowsCallbackBinding{ id: 'same', on_event: capture_windows_control_a, kind: .button, event: .tap }
		current := WindowsCallbackBinding{ ...first, on_event: capture_windows_control_b }
		cancelled := WindowsControlCapture{ binding: first, cancelled: true }
		if _ := windows_control_dispatch_binding(current, cancelled, true, true, false) {
			assert false, 'cancelled pointer action must remain cancelled'
		}
		windows_control_test_handlers = []string{}
		selected := windows_control_dispatch_binding(current, cancelled, true, true, true) or {
			panic('independent keyboard action must use current callback')
		}
		assert windows_emit_callback(selected.on_event, ElementEvent{ id: selected.id, kind: .tap })
		assert windows_control_test_handlers == ['b']
		if _ := windows_control_dispatch_binding(current, cancelled, true, false, true) {
			assert false, 'disabled/deleted control cannot receive a keyboard action'
		}
	}

	fn test_windows_control_destruction_releases_capture_and_nested_keyboard_transport_state() {
		mut st := windows_state()
		old_captures := st.control_captures.clone()
		old_activations := st.control_native_activations.clone()
		defer {
			st.control_captures = old_captures
			st.control_native_activations = old_activations
		}
		hwnd := voidptr(usize(0x1234))
		handle := windows_handle_id(hwnd)
		st.control_captures[handle] = WindowsControlCapture{
			binding: WindowsCallbackBinding{ on_event: capture_windows_control_a }
		}
		ui2_windows_control_tracking(hwnd, 4)
		ui2_windows_control_tracking(hwnd, 4)
		assert st.control_native_activations[handle] == 2
		ui2_windows_control_tracking(hwnd, 5)
		assert st.control_native_activations[handle] == 1
		ui2_windows_control_tracking(hwnd, 6)
		assert handle !in st.control_captures
		assert handle !in st.control_native_activations
		ui2_windows_control_tracking(hwnd, 5)
		assert handle !in st.control_native_activations
	}

	fn test_windows_scroll_notification_uses_current_element_callback_and_logical_offset() {
		mut st := windows_state()
		old_callbacks := st.scroll_callbacks.clone()
		defer { st.scroll_callbacks = old_callbacks }
		hwnd := voidptr(usize(0x4567))
		handle := windows_handle_id(hwnd)
		st.scroll_callbacks[handle] = WindowsCallbackBinding{ id: 'list', on_event: capture_windows_control_a, kind: .scroll, event: .scroll }
		windows_control_test_handlers = []string{}
		windows_control_test_events = []ElementEvent{}
		assert windows_emit_scroll(hwnd, 63)
		assert windows_control_test_events[0].kind == .scroll
		assert windows_control_test_events[0].id == 'list'
		assert windows_control_test_events[0].value == 63
		st.scroll_callbacks[handle] = WindowsCallbackBinding{ on_event: capture_windows_control_b, kind: .scroll, event: .scroll }
		assert windows_emit_scroll(hwnd, 72)
		assert windows_control_test_handlers == ['a', 'b']
		assert windows_control_test_events[1].id == ''
		st.scroll_callbacks.delete(handle)
		assert !windows_emit_scroll(hwnd, 90)
	}
}

$if windows && !ui2_custom_rendering ? {
	fn test_windows_shared_tab_is_consumed_once_per_control_key_event() {
		assert C.ui2_win_register_classes() != 0
		title := 'focus traversal fixture'.to_wide()
		root := C.ui2_win_create_main_window(title, 320, 200)
		unsafe { free(title) }
		empty := ''.to_wide()
		field := C.ui2_win_create_widget(windows_widget_kind(.text_field), root, 0, 0, 100, 30, empty, 0, 0, 0, 0, 0)
		button := C.ui2_win_create_widget(windows_widget_kind(.button), root, 0, 40, 100, 30, empty, 0, 0, 0, 0, 0)
		last := C.ui2_win_create_widget(windows_widget_kind(.button), root, 0, 80, 100, 30, empty, 0, 0, 0, 0, 0)
		unsafe { free(empty) }
		mut st := windows_state()
		previous := *st
		unsafe { *st = WindowsState{} }
		st.root = root
		defer { C.ui2_win_destroy(root); unsafe { *st = previous } }
		st.views = {'edit': field, 'button': button, 'last': last}
		st.handle_keys = {windows_handle_id(field): 'i:0', windows_handle_id(button): 'i:1', windows_handle_id(last): 'i:2'}
		st.node_ids = {'i:0': 'edit', 'i:1': 'button', 'i:2': 'last'}
		st.node_kinds = {'i:0': Kind.text_field, 'i:1': Kind.button, 'i:2': Kind.button}
		st.navigation.update(screen(0xffffff, [
			Element{kind: .text_field, id: 'edit'}, Element{kind: .button, id: 'button'}, Element{kind: .button, id: 'last'},
		]), map[string]f64{})
		C.ui2_win_show(root, 1)
		focus('edit')
		assert focused_id() == 'edit'
		assert ui2_windows_control_key(field, 0x09, 0, 0x0f) == 1
		assert focused_id() == 'button'
		assert ui2_windows_control_char(9, 0x0f) == 1
		// Held Tab consumes only its own WM_CHAR, even after focus changes.
		assert ui2_windows_control_char(97, 0x1e) == 0
		assert ui2_windows_control_char(0x00f1, 0) == 0
		assert ui2_windows_control_key_up(0x09) == 1
		assert ui2_windows_control_char(97, 0x1e) == 0
		assert ui2_windows_control_key(button, 0x09, 1, 0x0f) == 1
		assert focused_id() == 'last'
		assert ui2_windows_control_key(last, 0x09, 0, 0x0f) == 1
		assert focused_id() == 'edit'
		assert handle_focus_key(KeyEvent{code: .tab, shift: true}, false)
		assert focused_id() == 'last'
	}
}
