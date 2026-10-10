module ui2

import math

fn test_contain_fixed_composition_geometry() {
	small := contain_content(rect(0, 0, 640, 480), 1280, 720)!
	assert small == ContentTransform{ xx: 0.5, yy: 0.5, x: 0, y: 60 }
	large := contain_content(rect(0, 0, 1920, 1080), 1280, 720)!
	assert large == ContentTransform{ xx: 1.5, yy: 1.5 }
	wide := contain_content(rect(0, 0, 1440, 900), 1280, 720)!
	assert wide == ContentTransform{ xx: 1.125, yy: 1.125, x: 0, y: 45 }
	logical := rect(72, 64, 1136, 592)
	assert small.project(logical) == rect(36, 92, 568, 296)
	assert small.inverse_rect(small.project(logical)) == logical
}

fn test_nested_content_transforms_and_rounding() {
	outer := ContentTransform{ xx: 0.5, yy: 0.5, x: 10, y: 20 }
	inner := ContentTransform{ xx: 1.5, yy: 1.5, x: 30, y: 40 }
	nested := outer.compose(inner)
	assert nested == ContentTransform{ xx: 0.75, yy: 0.75, x: 25, y: 40 }
	x, y := nested.inverse(100, 115)
	assert x == 100 && y == 100
	for dpi in [1.0, 1.25, 1.5, 2.0] {
		left := presentation_rect(nested.project(rect(0, 0, 100.0 / 3, 50)), dpi)
		right := presentation_rect(nested.project(rect(100.0 / 3, 0, 100.0 / 3, 50)), dpi)
		assert math.abs(left.x + left.width - right.x) < 0.00001
	}
}

fn test_contain_rejects_empty_dimensions() {
	for width in [0.0, -1.0] {
		if _ := contain_content(rect(0, 0, 640, 480), width, 720) {
			assert false
		}
	}
	if _ := contain_content(rect(0, 0, 0, 480), 1280, 720) {
		assert false
	}
}

fn test_vml_scaled_content_keeps_child_layout_on_resize() {
	small := compiled_scaled_content_1(rect(0, 0, 640, 360))
	large := compiled_scaled_content_0(rect(0, 0, 1440, 900))
	assert small.children[0].frame.width == 640
	assert large.children[0].frame.width == 1440
	assert small.children[0].children[0].frame == large.children[0].children[0].frame
	assert small.children[0].children[0].frame.width == 1280
	assert small.children[0].children[0].children[0].frame.height == 42
	assert small.children[1].frame.width == 44
}

fn compiled_scaled_content_0(frame Rect) Element {
	return $vml('fixtures/scaled_content_0.vml', frame)
}

fn compiled_scaled_content_1(frame Rect) Element {
	return $vml('fixtures/scaled_content_1.vml', frame)
}
