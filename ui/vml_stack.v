module ui2

fn v_stack_config(node &VNode, frame Rect, children []StackChild) !StackConfig {
	padding := node.prop_or('padding', '0').f64()
	return StackConfig{
		id:       node.id
		frame:    frame
		box:      v_box(node)
		padding:  LayoutPadding{
			left:   node.prop_or('padding_left', padding.str()).f64()
			top:    node.prop_or('padding_top', padding.str()).f64()
			right:  node.prop_or('padding_right', padding.str()).f64()
			bottom: node.prop_or('padding_bottom', padding.str()).f64()
		}
		align_x:  layout_alignment(node.prop_or('align_x', 'start'))!
		align_y:  layout_alignment(node.prop_or('align_y', 'start'))!
		children: children
	}
}

fn v_stack_child(node &VNode, preferred Rect) !StackChild {
	return StackChild{
		element: Element{ frame: preferred }
		align_x: layout_alignment(node.prop_or('align_self_x', 'auto'))!
		align_y: layout_alignment(node.prop_or('align_self_y', 'auto'))!
	}
}

fn v_stack(node &VNode, frame Rect) !Element {
	if node.prop_bool('__layout_resolved') {
		return view(node.id, frame, v_box(node), v_children(node, rect(0, 0, frame.width, frame.height))!)
	}
	local := rect(0, 0, frame.width, frame.height)
	config := v_stack_config(node, local, []StackChild{})!
	available := rect(0, 0, layout_max(0, frame.width - config.padding.left - config.padding.right),
		layout_max(0, frame.height - config.padding.top - config.padding.bottom))
	mut cache := VLayoutMeasureCache{}
	mut children := []StackChild{}
	mut visible := []&VNode{}
	for child in node.children {
		if v_is_layout_metadata(child) { continue }
		visible << child
		children << v_stack_child(child, v_layout_preferred(child, available, mut cache)!)!
	}
	frames := stack_frames(StackConfig{ ...config, children: children })!
	mut elements := []Element{cap: children.len}
	for index, child in visible {
		elements << node_to_element(v_layout_node_at(child, frames[index]), frames[index])!
	}
	return view(node.id, frame, v_box(node), elements)
}
