module ui2

fn v_absolute(node &VNode, frame Rect) !Element {
	children := v_children(node, rect(0, 0, frame.width, frame.height))!
	config := AbsoluteConfig{ id: node.id, frame: frame, box: v_box(node), children: children }
	preferred := absolute_preferred_size(config)!
	actual := rect(frame.x, frame.y,
		if node.prop('width').len == 0 {
			layout_max(frame.width, preferred.width)
		} else {
			frame.width
		},
		if node.prop('height').len == 0 {
			layout_max(frame.height, preferred.height)
		} else {
			frame.height
		})
	return absolute(AbsoluteConfig{ ...config, frame: actual })!
}

fn v_absolute_resolve_extent(mut node VNode, available Rect) ! {
	mut children := []Element{}
	local := rect(0, 0, available.width, available.height)
	for child in node.children {
		if !v_is_layout_metadata(child) { children << Element{ frame: v_frame(child, local) } }
	}
	preferred := absolute_preferred_size(AbsoluteConfig{ frame: available, children: children })!
	if node.prop('width').len == 0 {
		node.props['width'] = layout_max(available.width, preferred.width).str()
	}
	if node.prop('height').len == 0 {
		node.props['height'] = layout_max(available.height, preferred.height).str()
	}
}
