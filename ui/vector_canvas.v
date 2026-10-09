module ui2

pub struct VectorCanvasConfig {
pub:
	id              string
	key             string
	frame           Rect
	shapes          []VectorShape
	hit_mode        VectorHitMode
	on_event        ElementCallback = unsafe { nil }
	clickable       bool
	button_behavior bool
	draggable       bool
	tooltip         string
}

// VectorCanvas is a transparent retained View with local prepared shapes.
// Paint and hits are clipped to its frame and the existing ancestor clip.
pub fn vector_canvas(config VectorCanvasConfig) !Element {
	validate_layout_frame(config.frame)!
	for shape in config.shapes {
		if !shape.prepared { return error('vector canvas needs prepare_vector_shape geometry') }
	}
	return Element{
		kind:            .view
		id:              config.id
		key:             config.key
		frame:           config.frame
		box:             BoxStyle{ transparent: true }
		is_vector_canvas: true
		vector_shapes:   config.shapes.clone()
		vector_hit_mode: config.hit_mode
		on_event:        config.on_event
		clickable:       config.clickable
		button_behavior: config.button_behavior
		draggable:       config.draggable
		tooltip:         config.tooltip
	}
}

fn vector_shapes_contain(shapes []VectorShape, x f64, y f64, mode VectorHitMode) bool {
	for shape in shapes { if shape.contains(x, y, mode) { return true } }
	return false
}

fn vector_element_contains(el Element, area Rect, x f64, y f64) bool {
	return (!el.is_vector_canvas && el.vector_shapes.len == 0) || vector_shapes_contain(el.vector_shapes, x - area.x, y - area.y, el.vector_hit_mode)
}
