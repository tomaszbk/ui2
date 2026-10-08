module ui2

pub enum SemanticAction {
	focus
	activate
	increment
	decrement
}

pub struct SemanticState {
pub:
	hidden   bool
	disabled bool
	focused  bool
	checked  bool
	selected bool
	readonly bool
	expanded bool
	secure   bool
}

// Portable semantic hooks, not a promise of an OS accessibility bridge.
// path/parent retain tree structure even for elements without public ids.
pub struct SemanticNode {
pub:
	id      string
	path    string
	parent  string
	role    string
	name    string
	label   string
	value   string
	frame   Rect
	state   SemanticState
	actions []SemanticAction
}

fn semantic_role(el Element) string {
	if el.accessibility_role.len > 0 { return el.accessibility_role }
	return match el.kind {
		.button { 'button' }
		.view {
			if el.button_behavior { 'button' } else { 'group' }
		}
		.checkbox { 'checkbox' }
		.switch_control { 'switch' }
		.toggle_button { 'button' }
		.text_field, .text_area { 'textbox' }
		.dropdown { 'combobox' }
		.slider { 'slider' }
		.label { 'text' }
		.image { 'image' }
		.scroll { 'scroll' }
		.screen { 'window' }
	}
}

fn semantic_activatable(el Element) bool {
	return el.kind in [.button, .checkbox, .switch_control, .toggle_button, .dropdown]
		|| (el.kind == .view && el.button_behavior)
}

fn (manager &FocusManager) semantics() []SemanticNode {
	mut result := []SemanticNode{cap: manager.nodes.len}
	for node in manager.nodes {
		el := node.el
		semantic_label := if el.accessibility_label.len > 0 {
			el.accessibility_label
		} else if el.kind in [.text_field, .text_area] {
			el.placeholder
		} else if el.button_behavior {
			button_behavior_label(el)
		} else {
			el.text
		}
		name := if el.accessibility_name.len > 0 {
			el.accessibility_name
		} else if el.kind in [.text_field, .text_area] {
			if el.accessibility_label.len > 0 { el.accessibility_label } else { el.placeholder }
		} else {
			semantic_label
		}
		value := if el.secure {
			''
		} else if el.accessibility_value.len > 0 {
			el.accessibility_value
		} else if el.kind == .slider {
			el.value.str()
		} else if el.kind in [.checkbox, .switch_control, .toggle_button] {
			if el.checked { 'checked' } else { 'unchecked' }
		} else if el.kind in [.text_field, .text_area, .dropdown] {
			el.text
		} else {
			''
		}
		mut actions := []SemanticAction{}
		if node.eligible && manager.in_scope(node) { actions << .focus }
		if !node.hidden && node.enabled && manager.in_scope(node) && el.id.len > 0 {
			if semantic_activatable(el) && (el.on_event != unsafe { nil } || el.kind in [
				.checkbox,
				.switch_control,
				.toggle_button,
				.dropdown,
			]) {
				actions << .activate
			}
			if el.kind == .slider {
				actions << .increment
				actions << .decrement
			}
		}
		result << SemanticNode{
			id:      el.id
			path:    node.path
			parent:  node.parent
			role:    semantic_role(el)
			name:    name
			label:   semantic_label
			value:   value
			frame:   node.frame
			state:   SemanticState{
				hidden:   node.hidden
				disabled: !node.enabled
				focused:  manager.current == el.id && el.id.len > 0
				checked:  el.checked
				selected: el.kind == .toggle_button && el.checked
				readonly: el.readonly
				secure:   el.secure
			}
			actions: actions
		}
	}
	return result
}

fn semantic_slider_step(value f64, spec SliderSpec, action SemanticAction) f64 {
	step := if spec.step > 0 { spec.step } else { (spec.max - spec.min) / 100 }
	next := value + if action == .increment { step } else { -step }
	return slider_value_from_normalized(slider_value_normalized(next, spec.min, spec.max), spec.min, spec.max, spec.step)
}
