@[has_globals]
module ui2

import macos

__global g_ios_navigation = &FocusManager{}
__global g_ios_navigation_paths = map[string]string{}

fn focus_manager() &FocusManager { return g_ios_navigation }

fn ios_focus_offsets(el Element, path string, native_path string, mut offsets map[string]f64) {
	// Shared focus starts at root; UIKit mounts root.children at the empty
	// parent key. Use the renderer's reconciliation keys for every Scroll.
	g_ios_navigation_paths[path] = native_path
	if el.kind == .scroll {
		if native := g_nodes[native_path] { offsets[path] = scroll_content_offset_y(native) }
	}
	for i, child in el.children {
		ios_focus_offsets(child, reconciliation_child_key(path, i, child), reconciliation_child_key(native_path, i, child), mut offsets)
	}
}

fn sync_focus_navigation() {
	mut offsets := map[string]f64{}
	g_ios_navigation_paths.clear()
	ios_focus_offsets(g_ios_navigation.root, 'root', '', mut offsets)
	g_ios_navigation.update(g_ios_navigation.root, offsets)
}

fn live_semantic_nodes(nodes []SemanticNode) []SemanticNode {
	mut result := []SemanticNode{cap: nodes.len}
	for node in nodes {
		el := g_ios_navigation.node(node.id) or {
			result << node
			continue
		}
		native := g_views[node.id] or {
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
			value = text(node.id)
		}
		if el.el.kind == .slider && el.el.accessibility_value.len == 0 { value = slider_value(node.id).str() }
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

fn activate_semantic_control(id string, action SemanticAction) bool {
	node := g_ios_navigation.node(id) or { return false }
	if node.hidden || !node.enabled || !g_ios_navigation.in_scope(node) { return false }
	native := g_views[id] or { return false }
	if !ios_interaction_available(native) { return false }
	if action in [.increment, .decrement] && node.el.kind == .slider {
		before := slider_value(id)
		value := semantic_slider_step(before, slider_spec(node.el), action)
		set_slider_value(id, value)
		if value != before {
			ios_emit_callback(ios_binding(node.el, .change), ElementEvent{ kind: .change, value: value })
		}
		return true
	}
	if action != .activate || !semantic_activatable(node.el) { return false }
	if node.el.kind == .view {
		return ios_emit_callback(ios_binding(node.el, .tap), ElementEvent{ kind: .tap })
	}
	if node.el.kind == .dropdown {
		if !ios_can_activate_dropdown(native) { return false }
		// Menu selection is a later UICommand, not a pointer release. A stale
		// touch capture must not redirect that command to an old callback.
		g_control_captures.delete(u64(native))
		macos.msg_void(native, 'performPrimaryAction')
		return true
	}
	if node.el.kind == .switch_control { set_switch_active(id, !switch_active(id)) }
	commit_ios_button_activation(native, node.el.kind)
	// Semantic actions commit live state once, then emit the current optional
	// callback. Pointer input keeps its independent captured-release binding.
	binding := ios_binding(node.el, if node.el.kind == .button { .tap } else { .change })
	ios_emit_callback(binding, ios_control_event(native, binding))
	return true
}

fn ios_can_activate_dropdown(native View) bool {
	// UIControl.performPrimaryAction is public since iOS 17.4 and presents a
	// UIButton's menu when showsMenuAsPrimaryAction is enabled.
	return macos.responds_to(native, 'performPrimaryAction')
		&& macos.msg_bool(native, 'showsMenuAsPrimaryAction')
		&& !objc_is_nil(macos.msg_id(native, 'menu'))
}
