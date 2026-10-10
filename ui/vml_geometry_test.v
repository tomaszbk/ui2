module ui2

pub struct GeometryModel {
pub:
	width f64   = 77.5
	rows  []int = [1, 2]
}

fn test_view_replaces_rectangle() {
	el := compiled_vml_geometry_5(rect(0, 0, 100, 100))
	assert el.kind == .view
	assert el.frame == rect(0, 0, 20.5, 40.25)
}

fn test_geometry_references_require_absolute_but_model_dimensions_do_not() {
	mut app := GeometryModel{}
	el := $vml('fixtures/geometry_model_dimension.vml', rect(0, 0, 100, 100))
	assert el.children[0].frame.width == 100
	assert el.children[0].frame.height == 20
}

fn test_viewport_predicates_do_not_author_geometry() {
	root := compiled_vml_geometry_4(rect(0, 0, 100, 100))
	assert !root.children[0].hidden
	wide := compiled_vml_geometry_3(rect(0, 0, 200, 100))
	assert wide.children[0].hidden
}

fn test_screen_absolute_viewport_expression_does_not_become_a_layout_parameter() {
	root := compiled_vml_geometry_2(rect(0, 0, 200, 100))
	assert root.children[0].children[0].frame.x == 10
}

fn test_absolute_geometry_is_parent_local_fractional_and_nested() {
	el := compiled_vml_geometry_1(rect(0, 0, 200, 100))
	panel := el.children[0].children[0]
	child := panel.children[0].children[0]
	assert panel.frame == rect(12.5, 9.25, 175, 80)
	assert child.frame == rect(3.25, 4.5, 87.5, 10.25)
}

fn test_repeaters_use_the_containing_layout_context() {
	mut fixture_model_1 := GeometryModel{}
	el := compiled_vml_geometry_0(mut fixture_model_1, rect(0, 0, 100, 100))
	assert el.children.len == 2
	assert el.children[0].frame == rect(0, 3.25, 10, 12)
	assert el.children[1].frame == rect(20.5, 3.25, 10, 12)
	assert el.children[0].key != el.children[1].key
}

fn test_allocated_flex_grid_and_stack_coordinates_are_valid() {
	frame := rect(0, 0, 100, 100)
	row := $vml('fixtures/geometry_allocated_row.vml', frame)
	grid := $vml('fixtures/geometry_allocated_grid.vml', frame)
	layers := $vml('fixtures/geometry_allocated_stack.vml', frame)
	assert row.children[1].frame == rect(24, 0, 20, 100)
	assert grid.children.map(it.frame) == [rect(0, 0, 50, 100), rect(50, 0, 50, 100)]
	assert layers.children[0].frame == rect(80, 90, 20, 10)
}

fn compiled_vml_geometry_0(mut app GeometryModel, frame Rect) Element {
	return $vml('fixtures/vml_geometry_0.vml', frame)
}

fn compiled_vml_geometry_1(frame Rect) Element {
	return $vml('fixtures/vml_geometry_1.vml', frame)
}

fn compiled_vml_geometry_2(frame Rect) Element {
	return $vml('fixtures/vml_geometry_2.vml', frame)
}

fn compiled_vml_geometry_3(frame Rect) Element {
	return $vml('fixtures/vml_geometry_3.vml', frame)
}

fn compiled_vml_geometry_4(frame Rect) Element {
	return $vml('fixtures/vml_geometry_4.vml', frame)
}

fn compiled_vml_geometry_5(frame Rect) Element {
	return $vml('fixtures/vml_geometry_5.vml', frame)
}
