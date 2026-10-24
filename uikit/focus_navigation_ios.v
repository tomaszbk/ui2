@[has_globals]
module ui2

$if ios && !ui2_custom_rendering ? && !ui2_headless ? && !ui2_document_library ? {

import macos


fn (mut w Window) focus_manager() &FocusManager { return w.ios_navigation }

fn (mut w Window) ios_focus_offsets(el Element, path string, native_path string, mut offsets map[string]f64, mut offsets_x map[string]f64) {
	// Shared focus starts at root; UIKit mounts root.children at the empty
	// parent key. Use the renderer's reconciliation keys for every Scroll.
	w.ios_navigation_paths[path] = native_path
	if el.kind == .scroll {
		if native := w.nodes[native_path] {
			offset := scroll_content_offset(native)
			offsets[path] = offset.y
			offsets_x[path] = offset.x
		}
	}
	for i, child in el.children {
		w.ios_focus_offsets(child, reconciliation_child_key(path, i, child), reconciliation_child_key(native_path, i, child), mut offsets, mut offsets_x)
	}
}

fn (mut w Window) sync_focus_navigation() {
	mut offsets := map[string]f64{}
	mut offsets_x := map[string]f64{}
	w.ios_navigation_paths.clear()
	w.ios_focus_offsets(w.ios_navigation.root, 'root', '', mut offsets, mut offsets_x)
	w.ios_navigation.update_mounted_axes(w.ios_navigation.root, offsets, offsets_x, w.bounds(), ContentTransform{})
}

fn (mut w Window) live_semantic_nodes(nodes []SemanticNode) []SemanticNode {
	mut result := []SemanticNode{cap: nodes.len}
	for node in nodes {
		el := w.ios_navigation.path_node(node.path) or {
			result << node
			continue
		}
		key := w.ios_navigation_paths[node.path] or {
			result << node
			continue
		}
		native := w.nodes[key] or {
			result << node
			continue
		}
		mut value := node.value
		mut checked := node.state.checked
		mut actions := node.actions.clone()
		if el.el.kind == .dropdown && !ios_can_activate_dropdown(native) {
			actions = actions.filter(it != .activate)
		}
		if el.el.kind in [.text_field, .text_area, .dropdown] && !el.el.secure && el.el.accessibility_value.len == 0 {
			value = macos.utf8_string(macos.msg_id(native, if el.el.kind == .dropdown { 'currentTitle' } else { 'text' }))
		}
		if el.el.kind == .slider && el.el.accessibility_value.len == 0 { value = native_snap_slider_value(native, slider_spec(el.el)).str() }
		if el.el.kind == .switch_control { checked = macos.msg_bool(native, 'isOn') }
		if el.el.kind in [.checkbox, .toggle_button] {
			checked = macos.msg_bool(native, 'isSelected')
		}
		if el.el.kind in [.checkbox, .switch_control, .toggle_button] {
			if el.el.accessibility_value.len == 0 { value = if checked { 'checked' } else { 'unchecked' } }
		}
		result << SemanticNode{
			...node
			actions: actions
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

fn (mut w Window) activate_semantic_control(id string, action SemanticAction) bool {
	node := w.ios_navigation.node(id) or { return false }
	if node.hidden || !node.enabled || !w.ios_navigation.in_scope(node) { return false }
	native := w.views[id] or { return false }
	if !ios_interaction_available(native) { return false }
	if action in [.increment, .decrement] && node.el.kind == .slider {
		before := w.slider_value(id)
		value := semantic_slider_step(before, slider_spec(node.el), action)
		w.set_slider_value(id, value)
		if value != before {
			w.ios_emit_callback(ios_binding(node.el, .change), ElementEvent{ kind: .change, value: value })
		}
		return true
	}
	if action != .activate || !semantic_activatable(node.el) { return false }
	if node.el.kind == .view {
		return w.ios_emit_callback(ios_binding(node.el, .click), ElementEvent{ kind: .click })
	}
	if node.el.kind == .dropdown {
		if !ios_can_activate_dropdown(native) { return false }
		// Menu selection is a later UICommand, not a pointer release. A stale
		// touch capture must not redirect that command to an old callback.
		w.control_captures.delete(u64(native))
		macos.msg_void(native, 'performPrimaryAction')
		return true
	}
	if node.el.kind == .switch_control { w.set_switch_active(id, !w.switch_active(id)) }
	w.commit_ios_button_activation(native, node.el.kind)
	// Semantic actions commit live state once, then emit the current optional
	// callback. Pointer input keeps its independent captured-release binding.
	binding := ios_binding(node.el, if node.el.kind == .button { .click } else { .change })
	w.ios_emit_callback(binding, ios_control_event(native, binding))
	return true
}

fn ios_can_activate_dropdown(native View) bool {
	// UIControl.performPrimaryAction is public since iOS 17.4 and presents a
	// UIButton's menu when showsMenuAsPrimaryAction is enabled.
	return macos.responds_to(native, 'performPrimaryAction')
		&& macos.msg_bool(native, 'showsMenuAsPrimaryAction')
		&& !objc_is_nil(macos.msg_id(native, 'menu'))
}

}
