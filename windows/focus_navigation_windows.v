module ui2

$if !ui2_custom_rendering ? {
	fn focus_manager() &FocusManager { return windows_state().navigation }

	fn windows_focus_offsets(el Element, path string, native_path string, mut offsets map[string]f64) {
		mut st := windows_state()
		st.navigation_paths[path] = native_path
		if el.kind == .scroll { offsets[path] = f64(st.scroll_positions[native_path] or { 0 }) }
		for i, child in el.children {
			windows_focus_offsets(child, reconciliation_child_key(path, i, child), reconciliation_child_key(native_path, i, child), mut offsets)
		}
	}

	fn sync_focus_navigation() {
		mut st := windows_state()
		mut offsets := map[string]f64{}
		st.navigation_paths.clear()
		native_path := if st.navigation.root.kind == .screen {
			''
		} else {
			reconciliation_child_key('', 0, st.navigation.root)
		}
		windows_focus_offsets(st.navigation.root, 'root', native_path, mut offsets)
		st.navigation.update(st.navigation.root, offsets)
	}

	fn reconcile_windows_focus(root Element, previous string) {
		mut st := windows_state()
		st.navigation.root = root
		st.navigation.current = previous
		sync_focus_navigation()
		if st.navigation.current.len > 0 {
			if focused_id() != st.navigation.current { focus(st.navigation.current) }
		} else if previous.len > 0 {
			C.ui2_win_clear_focus(st.root)
		}
	}

	fn reveal_windows_focus(id string) {
		mut st := windows_state()
		for request in st.navigation.reveals(id) {
			key := st.navigation_paths[request.path] or { continue }
			hwnd := st.nodes[key] or { continue }
			position := C.ui2_win_scroll_to_rect(hwnd, int(request.rect.y), int(request.rect.y + request.rect.height))
			st.scroll_positions[key] = position
			windows_reposition_scroll_children(key, position)
		}
		sync_focus_navigation()
	}

	fn activate_semantic_control(id string, action SemanticAction) bool {
		st := windows_state()
		node := st.navigation.node(id) or { return false }
		if node.hidden || !node.enabled || !st.navigation.in_scope(node) { return false }
		hwnd := st.views[id] or { return false }
		if action in [.increment, .decrement] && node.el.kind == .slider {
			spec := slider_spec(node.el)
			before := slider_value(id)
			value := semantic_slider_step(before, spec, action)
			set_slider_value(id, value)
			if value != before { windows_emit_control_action(hwnd) }
			return true
		}
		if action != .activate || !semantic_activatable(node.el) { return false }
		if node.el.kind == .view {
			binding := st.pointer_bindings[windows_handle_id(hwnd)] or { return false }
			return windows_emit_button_behavior(hwnd, binding)
		}
		if node.el.kind == .dropdown {
			C.ui2_win_open_dropdown(hwnd)
			return true
		}
		C.ui2_win_click(hwnd)
		return true
	}

	fn live_semantic_nodes(nodes []SemanticNode) []SemanticNode {
		st := windows_state()
		mut result := []SemanticNode{cap: nodes.len}
		for node in nodes {
			el := st.navigation.node(node.id) or {
				result << node
				continue
			}
			hwnd := st.views[node.id] or {
				result << node
				continue
			}
			mut value := node.value
			mut checked := node.state.checked
			if el.el.kind in [.text_field, .text_area, .dropdown] && !el.el.secure && el.el.accessibility_value.len == 0 {
				value = text(node.id)
			}
			if el.el.kind == .slider && el.el.accessibility_value.len == 0 { value = slider_value(node.id).str() }
			if el.el.kind in [.checkbox, .switch_control, .toggle_button] {
				checked = C.ui2_win_get_checked(hwnd) != 0
				if el.el.accessibility_value.len == 0 { value = if checked { 'checked' } else { 'unchecked' } }
			}
			result << SemanticNode{
				...node
				value: value
				state: SemanticState{
					...node.state
					checked:  checked
					selected: el.el.kind == .toggle_button && checked
				}
			}
		}
		return result
	}
}

$if !ui2_custom_rendering ? {
	@[export: 'ui2_windows_focus_changed']
	fn ui2_windows_focus_changed(hwnd voidptr) {
		st := windows_state()
		key := st.handle_keys[windows_handle_id(hwnd)] or { return }
		id := st.node_ids[key] or { return }
		if st.navigation.can_focus(id) {
			st.navigation.set_focus(id)
			return
		}
		if st.navigation.current.len > 0 {
			focus(st.navigation.current)
		} else {
			C.ui2_win_clear_focus(st.root)
		}
	}
}

$if !ui2_custom_rendering ? {
	@[export: 'ui2_windows_control_key_up']
	fn ui2_windows_control_key_up(virtual_key u32, scan_code u32) int {
		mut st := windows_state()
		physical := windows_physical_key(virtual_key, scan_code)
		consumed := physical in st.suppressed_keys || (st.activation_keys[physical] or { false })
		st.suppressed_keys.delete(physical)
		st.activation_keys.delete(physical)
		if consumed { st.keyboard_generation++ }
		return windows_bool(consumed)
	}

	@[export: 'ui2_windows_control_char']
	fn ui2_windows_control_char(character u32, scan_code u32) int {
		return windows_bool(character == 9 || consumed_key_character(scan_code, windows_state().suppressed_keys))
	}
}
