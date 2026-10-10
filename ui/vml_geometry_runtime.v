module ui2

// Geometry can precede its Element so a child can observe its parent's frame.
// The Element later adopts this exact source.
pub fn (mut component CompiledVmlComponent) geometry(id string, initial Rect) !&Signal[Rect] {
	component.require_alive()!
	key := 'geometry:' + id
	if pointer := component.values[key] {
		return unsafe { &Signal[Rect](pointer) }
	}
	value := new_signal(mut component.scope, initial,
		name:   '@frame:' + id
		equals: fn (left Rect, right Rect) bool { return left == right }
	)!
	component.values[key] = voidptr(value)
	component.value_types[key] = 'Rect'
	return value
}

// Geometry refs observe resolved logical frames independently of authored
// dimensions. A layout pass publishes them together, before dependent effects.
pub fn (node &CompiledVmlNode) frame() !Rect {
	node.component.require_alive()!
	mut value := node.frame_value
	return value.get()!
}

// Explicit authored geometry changes retain the declaration and its owner.
pub fn (mut node CompiledVmlNode) set_frame(frame Rect) ! {
	node.component.require_alive()!
	validate_layout_frame(frame)!
	if node.declaration.frame == frame { return }
	replacement := Element{
		...node.source_element()
		frame:        frame
		layout_input: if node.declaration.layout_input != none { frame } else { none }
	}
	validate_element_tree(replacement)!
	node.component.runtime.batch(fn [mut node, replacement, frame] () ! {
		node.replace_property(replacement)!
		node.frame_value.set(frame)!
	})!
}

// Only omitted root dimensions follow a window viewport. Explicit dimensions
// and embedded templates retain their authored sizing contract.
pub fn (mut node CompiledVmlNode) follow_viewport(width bool, height bool) {
	node.viewport_width = width
	node.viewport_height = height
}

pub fn (mut node CompiledVmlNode) update_viewport(viewport Rect) ! {
	if !node.viewport_width && !node.viewport_height { return }
	current := node.declaration.frame
	node.set_frame(Rect{
		...current
		width:  if node.viewport_width { viewport.width } else { current.width }
		height: if node.viewport_height { viewport.height } else { current.height }
	})!
}

fn compiled_vml_record_geometry(element Element) ! {
	// Hidden allocation is excluded from layout, rather than a logical resize.
	// Keep the retained frame of the entire subtree for its effects and refs.
	if element.hidden { return }
	if element.compiled_node != unsafe { nil } && !element.compiled_node.component.is_disposed() {
		mut value := element.compiled_node.frame_value
		value.set(element.frame)!
	}
	for child in element.children { compiled_vml_record_geometry(child)! }
}

fn compiled_vml_sync_geometry(element Element) ![]Element {
	mut updates := []Element{}
	if element.compiled_node != unsafe { nil } {
		if element.compiled_node.component.is_disposed() { return updates }
		before := element.compiled_node.element()
		element.compiled_node.component.runtime.batch(fn [element] () ! {
			compiled_vml_record_geometry(element)!
		})!
		after := element.compiled_node.element()
		if !vml_declaration_equal(before, after) { updates << after }
	} else {
		for child in element.children { updates << compiled_vml_sync_geometry(child)! }
	}
	return updates
}
