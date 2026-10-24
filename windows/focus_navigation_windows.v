module ui2

$if windows && !ui2_custom_rendering ? && !ui2_headless ? && !ui2_document_library ? {
	fn (mut w Window) focus_manager() &FocusManager { return w.navigation }

	fn (mut w Window) windows_focus_offsets(el Element, path string, native_path string, mut offsets map[string]f64, mut offsets_x map[string]f64) {
		w.navigation_paths[path] = native_path
		if el.kind == .scroll {
			offsets[path] = f64(w.scroll_positions[native_path] or { 0 })
			offsets_x[path] = f64(w.scroll_positions_x[native_path] or { 0 })
		}
		for i, child in el.children {
			w.windows_focus_offsets(child, reconciliation_child_key(path, i, child), reconciliation_child_key(native_path, i, child), mut offsets, mut offsets_x)
		}
	}

	fn (mut w Window) sync_focus_navigation() {
		mut offsets := map[string]f64{}
		mut offsets_x := map[string]f64{}
		w.navigation_paths.clear()
		native_path := if w.navigation.root.kind == .screen {
			''
		} else {
			reconciliation_child_key('', 0, w.navigation.root)
		}
		w.windows_focus_offsets(w.navigation.root, 'root', native_path, mut offsets, mut offsets_x)
		w.navigation.update_mounted_axes(w.navigation.root, offsets, offsets_x, w.bounds(), ContentTransform{})
	}

	fn (mut w Window) reconcile_windows_focus(root Element, previous string) {
		w.navigation.set_root(root)
		w.navigation.current = previous
		w.sync_focus_navigation()
		if w.navigation.current.len > 0 {
			if w.focused_id() != w.navigation.current { w.focus(w.navigation.current) }
		} else if previous.len > 0 {
			C.ui2_win_clear_focus(w.root)
		}
	}

	fn (mut w Window) reveal_windows_focus(id string) {
		for request in w.navigation.reveals(id) {
			key := w.navigation_paths[request.path] or { continue }
			hwnd := w.nodes[key] or { continue }
			position := C.ui2_win_scroll_to_rect(hwnd, int(request.rect.y), int(request.rect.y + request.rect.height), 0)
			w.scroll_positions[key] = position
			if key in w.scroll_positions_x {
				w.scroll_positions_x[key] = C.ui2_win_scroll_to_rect(hwnd, int(request.rect.x), int(request.rect.x + request.rect.width), 1)
			}
			w.windows_reposition_scroll_children(key)
		}
		w.sync_focus_navigation()
	}

	fn (mut w Window) activate_semantic_control(id string, action SemanticAction) bool {
		node := w.navigation.node(id) or { return false }
		if node.hidden || !node.enabled || !w.navigation.in_scope(node) { return false }
		hwnd := w.views[id] or { return false }
		if action in [.increment, .decrement] && node.el.kind == .slider {
			spec := slider_spec(node.el)
			before := w.slider_value(id)
			value := semantic_slider_step(before, spec, action)
			w.set_slider_value(id, value)
			if value != before { w.windows_emit_control_action(hwnd) }
			return true
		}
		if action != .activate || !semantic_activatable(node.el) { return false }
		if node.el.kind == .view {
			binding := w.pointer_bindings[windows_handle_id(hwnd)] or { return false }
			return w.windows_emit_button_behavior(hwnd, binding)
		}
		if node.el.kind == .dropdown {
			C.ui2_win_open_dropdown(hwnd)
			return true
		}
		C.ui2_win_click(hwnd)
		return true
	}

	fn (mut w Window) live_semantic_nodes(nodes []SemanticNode) []SemanticNode {
		mut result := []SemanticNode{cap: nodes.len}
		for node in nodes {
			el := w.navigation.path_node(node.path) or {
				result << node
				continue
			}
			key := w.navigation_paths[node.path] or {
				result << node
				continue
			}
			hwnd := w.nodes[key] or {
				result << node
				continue
			}
			mut value := node.value
			mut checked := node.state.checked
			if el.el.kind in [.text_field, .text_area, .dropdown] && !el.el.secure && el.el.accessibility_value.len == 0 {
				value = windows_native_text(hwnd)
			}
			if el.el.kind == .slider && el.el.accessibility_value.len == 0 { value = windows_snap_slider_value(hwnd, slider_spec(el.el)).str() }
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

	@[export: 'ui2_windows_focus_changed']
	fn ui2_windows_focus_changed(hwnd voidptr) {
		mut w := windows_window_for(hwnd) or { return }
		key := w.handle_keys[windows_handle_id(hwnd)] or { return }
		id := w.node_ids[key] or { return }
		if w.navigation.can_focus(id) {
			w.navigation.set_focus(id)
			return
		}
		if w.navigation.current.len > 0 {
			w.focus(w.navigation.current)
		} else {
			C.ui2_win_clear_focus(w.root)
		}
	}

	@[export: 'ui2_windows_control_key_up']
	fn ui2_windows_control_key_up(virtual_key u32, scan_code u32) int {
		mut w := windows_focus_window() or { return 0 }
		physical := windows_physical_key(virtual_key, scan_code)
		consumed := physical in w.suppressed_keys || (w.activation_keys[physical] or { false })
		w.suppressed_keys.delete(physical)
		w.activation_keys.delete(physical)
		if consumed { w.keyboard_generation++ }
		return windows_bool(consumed)
	}

	@[export: 'ui2_windows_control_char']
	fn ui2_windows_control_char(character u32, scan_code u32) int {
		mut w := windows_focus_window() or { return 0 }
		return windows_bool(character == 9 || consumed_key_character(scan_code, w.suppressed_keys))
	}
}
