@[has_globals]
module ui2

import macos

__global g_ios_navigation = &FocusManager{}

fn focus_manager() &FocusManager { return g_ios_navigation }

fn ios_focus_offsets(el Element, path string, mut offsets map[string]f64) {
	if el.kind == .scroll {
		if native := g_views[el.id] { offsets[path] = scroll_content_offset_y(native) }
	}
	for i, child in el.children {
		ios_focus_offsets(child, reconciliation_child_key(path, i, child), mut offsets)
	}
}

fn sync_focus_navigation() {
	mut offsets := map[string]f64{}
	ios_focus_offsets(g_ios_navigation.root, 'root', mut offsets)
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
	if node.el.kind == .switch_control { set_switch_active(id, !switch_active(id)) }
	if node.el.kind == .toggle_button { set_toggle_button_pressed(id, !toggle_button_pressed(id)) }
	vui_button_tap(unsafe { nil }, unsafe { nil }, native)
	return true
}
