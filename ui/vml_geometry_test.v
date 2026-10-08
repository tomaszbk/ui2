module ui2

struct GeometryModel {
pub:
	width f64   = 77.5
	rows  []int = [1, 2]
}

fn test_view_replaces_rectangle() {
	if _ := parse_vml('Rectangle { width: 20 }') {
		assert false
	}
	el := element_from_vml('View { width: 20.5 height: 40.25 }', rect(0, 0, 100, 100))!
	assert el.kind == .view
	assert el.frame == rect(0, 0, 20.5, 40.25)
}

fn test_authored_positions_require_absolute_even_when_zero() {
	for source in ['View { x: 0 }', 'Screen { Label { y: 0 } }', 'Column { View { x: 12 } }',
		'Stack { View { x: 1 } }', 'Grid { columns: 1 View { y: 2 } }'] {
		if _ := parse_vml(source) {
			assert false, source
		}
	}
	if _ := element_from_vnode(&VNode{
		tag:   'View'
		props: {
			'x': '0'
		}
	}, rect(0, 0, 100, 100)) {
		assert false
	}
}

fn test_geometry_references_require_absolute_but_model_dimensions_do_not() {
	for source in ['Screen { id: root View { width: root.width - 32 } }',
		'Column { id: panel View { height: panel.height / 2 } }',
		'Column { id: root gap: root.width / 10 View {} }',
		'Grid { id: root columns: 2 padding: root.height / 20 View {} }',
		'Row { id: root View { min_width: root.width / 2 } }'] {
		if _ := parse_vml(source) {
			assert false, source
		}
	}
	if _ := element_from_vnode(&VNode{
		tag:   'View'
		props: {
			'width': 'root.width - 32'
		}
	}, rect(0, 0, 100, 100)) {
		assert false
	}
	el := element_from_vml_model('Column { View { width: app.width height: 20 } }', GeometryModel{}, rect(0, 0, 100, 100))!
	assert el.children[0].frame.width == 100
	assert el.children[0].frame.height == 20
}

fn test_viewport_predicates_do_not_author_geometry() {
	root := element_from_vml_model('Column { id: root
		property bool compact: root.width < 150
		View { hidden: !root.compact height: 20 }
	}', GeometryModel{}, rect(0, 0, 100, 100))!
	assert !root.children[0].hidden
	wide := element_from_vml_model('Column { id: root
		property bool compact: root.width < 150
		View { hidden: !root.compact height: 20 }
	}', GeometryModel{}, rect(0, 0, 200, 100))!
	assert wide.children[0].hidden
}

fn test_computed_data_property_named_gap_is_not_a_screen_layout_parameter() {
	root := element_from_vml_model('Screen { id: root
		property f64 gap: root.width / 20
		Absolute { View { x: root.gap width: 20 height: 20 } }
	}', GeometryModel{}, rect(0, 0, 200, 100))!
	assert root.children[0].children[0].frame.x == 10
}

fn test_absolute_geometry_is_parent_local_fractional_and_nested() {
	el := element_from_vml_model('Screen { id: root Absolute { View { id: panel x: 12.5 y: 9.25 width: root.width - 25 height: 80 Absolute { View { id: child x: 3.25 y: 4.5 width: panel.width / 2 height: 10.25 } } } } }', GeometryModel{}, rect(0, 0, 200, 100))!
	panel := el.children[0].children[0]
	child := panel.children[0].children[0]
	assert panel.frame == rect(12.5, 9.25, 175, 80)
	assert child.frame == rect(3.25, 4.5, 87.5, 10.25)
}

fn test_repeaters_use_the_containing_layout_context() {
	if _ := parse_vml('Column { Repeater { model: app.rows View { x: 2 } } }') {
		assert false
	}
	el := element_from_vml_model('Absolute { Repeater { model: app.rows key: item View { x: index * 20.5 y: 3.25 width: 10 height: 12 } } }', GeometryModel{}, rect(0, 0, 100, 100))!
	assert el.children.len == 2
	assert el.children[0].frame == rect(0, 3.25, 10, 12)
	assert el.children[1].frame == rect(20.5, 3.25, 10, 12)
	assert el.children[0].key != el.children[1].key
}

fn test_allocated_flex_grid_and_stack_coordinates_are_valid() {
	for source in [
		'Row { gap: 4 View { width: 20 height: 10 } View { width: 20 height: 10 } }',
		'Grid { columns: 2 View {} View {} }',
		'Stack { align_x: end align_y: end View { width: 20 height: 10 } }',
	] {
		resolved, _ := v_evaluate_template(parse_vml(source)!, GeometryModel{}, rect(0, 0, 100, 100))!
		el := element_from_vnode(resolved, rect(0, 0, 100, 100))!
		assert el.children.len > 0
	}
}
