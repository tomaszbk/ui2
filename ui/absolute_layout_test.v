module ui2

import math

fn test_absolute_keeps_parent_local_fractional_geometry_and_identity() {
	config := AbsoluteConfig{
		id:       'canvas'
		frame:    rect(80, 120, 200, 150)
		children: [
			Element{ id: 'mark', key: 'one', frame: rect(10.25, 20.5, 30.75, 40.125) },
			Element{ id: 'overflow', key: 'two', frame: rect(-5, 130, 100, 50) },
		]
	}
	canvas := absolute(config)!
	assert absolute_frames(config)! == [rect(10.25, 20.5, 30.75, 40.125), rect(-5, 130, 100, 50)]
	assert canvas.frame == rect(80, 120, 200, 150)
	assert canvas.children == config.children
	validate_element_tree(canvas)!
}

fn test_absolute_rejects_nonfinite_and_negative_sizes() {
	for config in [AbsoluteConfig{ frame: rect(0, 0, 10, -1) },
		AbsoluteConfig{ frame: rect(math.nan(), 0, 10, 10) },
		AbsoluteConfig{ frame: rect(0, 0, 10, 10), children: [Element{ frame: rect(0, 0, -1, 10) }] },
		AbsoluteConfig{ frame: rect(0, 0, 10, 10), children: [Element{ frame: rect(math.inf(1), 0, 1, 1) }] }] {
		if _ := absolute(config) {
			assert false, 'invalid absolute geometry must fail'
		}
	}
}

fn test_vml_absolute_preserves_nested_parent_local_geometry() {
	direct := compiled_absolute_layout_4(rect(120, 150, 200, 180))
	assert direct.children[0].frame == rect(12.5, 17.25, 30, 40)
	assert direct.children[1].children[0].frame == rect(7.25, 9.5, 10, 15)
}

struct AbsoluteScrollItem {
pub:
	id int
}

pub struct AbsoluteScrollModel {
pub:
	items []AbsoluteScrollItem
}

fn test_absolute_omitted_dimensions_fill_parent_and_expose_repeated_scroll_content() {
	plain := compiled_absolute_layout_2(rect(0, 0, 200, 100))
	assert plain.children[0].frame == rect(0, 0, 200, 100)

	mut model := AbsoluteScrollModel{
		items: [AbsoluteScrollItem{ id: 1 }, AbsoluteScrollItem{ id: 2 }, AbsoluteScrollItem{ id: 3 }]
	}
	root := compiled_absolute_layout_1(mut model, rect(0, 0, 200, 100))
	assert root.kind == .scroll
	assert root.frame.height == 100
	assert root.children[0].frame == rect(0, 0, 200, 170)
	assert root.children[0].children.map(it.frame) == [rect(10, 0, 180, 50), rect(10, 60, 180, 50),
		rect(10, 120, 180, 50)]
	assert root.children[0].children.map(it.key) == ['1', '2', '3']
	assert root.children[0].frame.y + root.children[0].frame.height - root.frame.height == 70
	explicit := compiled_absolute_layout_0(rect(0, 0, 200, 100))
	assert explicit.frame == rect(0, 0, 80, 40)
}

fn test_absolute_extent_rejects_arithmetic_overflow() {
	if _ := absolute_preferred_size(AbsoluteConfig{ frame: rect(0, 0, 100, 100), children: [Element{ frame: rect(1e308, 0, 1e308, 10) }] }) {
		assert false, 'finite inputs with infinite extent must fail'
	}
}

fn compiled_absolute_layout_0(frame Rect) Element {
	return $vml('fixtures/absolute_layout_0.vml', frame)
}

fn compiled_absolute_layout_1(mut app AbsoluteScrollModel, frame Rect) Element {
	return $vml('fixtures/absolute_layout_1.vml', frame)
}

fn compiled_absolute_layout_2(frame Rect) Element {
	return $vml('fixtures/absolute_layout_2.vml', frame)
}

fn compiled_absolute_layout_4(frame Rect) Element {
	return $vml('fixtures/absolute_layout_4.vml', frame)
}
