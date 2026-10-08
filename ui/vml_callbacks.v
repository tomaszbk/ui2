module ui2

struct VmlCallback {
	on_event ElementCallback = unsafe { nil }
}

const vml_event_properties = ['on_tap', 'on_change', 'on_active', 'on_state', 'on_submit', 'on_select',
	'on_toggle', 'on_dismiss', 'on_scroll', 'on_pointer_down', 'on_pointer_drag', 'on_pointer_up',
	'on_long_press', 'on_swipe_left', 'on_link']

fn v_node_callback(node &VNode, property string) ElementCallback {
	entry := node.callbacks[property] or { return unsafe { nil } }
	return entry.on_event
}

fn v_node_events(node &VNode) ElementCallback {
	if node.callbacks.len == 0 { return unsafe { nil } }
	callbacks := node.callbacks.clone()
	tag := node.tag
	return fn [callbacks, tag] (event ElementEvent) {
		properties := match event.kind {
			.change {
				if tag == 'Switch' {
					['on_active', 'on_change', 'on_tap']
				} else if tag == 'ToggleButton' {
					['on_state', 'on_change', 'on_tap']
				} else {
					['on_change', 'on_tap']
				}
			}
			.submit { ['on_submit'] }
			.scroll { ['on_scroll'] }
			.pointer_down { ['on_pointer_down', 'on_tap'] }
			.pointer_drag { ['on_pointer_drag', 'on_tap'] }
			.pointer_up { ['on_pointer_up', 'on_tap'] }
			.long_press { ['on_long_press', 'on_tap'] }
			.swipe_left { ['on_swipe_left', 'on_tap'] }
			.link { ['on_link', 'on_tap'] }
			else { ['on_tap'] }
		}
		for property in properties {
			entry := callbacks[property] or { continue }
			if voidptr(entry.on_event) != unsafe { nil } { entry.on_event(event) }
			return
		}
	}
}

fn v_attach_named_callbacks(mut node VNode, callbacks map[string]ElementCallback) {
	for property in vml_event_properties {
		callback := callbacks[node.prop(property)] or { continue }
		node.callbacks[property] = VmlCallback{ on_event: callback }
	}
	for mut child in node.children { v_attach_named_callbacks(mut child, callbacks) }
}

// Explicit event names in a static document select callbacks; element ids only
// identify retained state. Undeclared callbacks stay inert.
pub fn element_from_vml_with_callbacks(source string, frame Rect, callbacks map[string]ElementCallback) !Element {
	mut node := parse_vml(source)!
	v_attach_named_callbacks(mut node, callbacks)
	return element_from_vnode(node, frame)!
}

pub fn element_from_vml_model_with_callbacks[T](source string, model T, frame Rect, callbacks map[string]ElementCallback) !Element {
	template := parse_vml(source)!
	v_validate_template[T](template, model)!
	mut resolved, _ := v_evaluate_template(template, model, frame)!
	v_attach_named_callbacks(mut resolved, callbacks)
	element := element_from_vnode(resolved, frame)!
	validate_element_tree(element)!
	return element
}

fn vml_record_accepts(tag string, property string, record VmlEvent, event ElementEvent) bool {
	// A named callback receives gestures through the default on_tap entry.
	// A boolean control activates by changing its state. Its default action
	// receives that semantic change; a view still requires an explicit gesture.
	if property == 'on_tap' && record.binding == none {
		return event.kind == .tap || (event.kind == .change && tag in ['Checkbox', 'Switch',
			'ToggleButton'])
	}
	return true
}

fn vml_apply_event[T](mut model T, record VmlEvent, event ElementEvent) ! {
	if binding := record.binding {
		value := match binding.property {
			'checked', 'active', 'pressed' { v_bool(event.checked) }
			'value' { v_number(event.value, slider_number(event.value)) }
			else { v_string(event.text) }
		}
		vml_set_field[T](mut model, binding.target.all_after('app.'), value)!
		if binding.property == 'pressed' && value.truthy() {
			for peer in record.group_bindings {
				if peer.control == binding.control || peer.target == binding.target { continue }
				vml_set_field[T](mut model, peer.target.all_after('app.'), v_bool(false))!
			}
		}
	}
	if invocation := record.invocation { vml_dispatch[T](mut model, invocation)! }
	if assignment := record.assignment { vml_apply_assignment[T](mut model, assignment)! }
}
