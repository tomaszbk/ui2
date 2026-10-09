module ui2

import math

fn assert_transform_point(p Point, x f64, y f64) {
	assert math.abs(p.x - x) < 1e-8
	assert math.abs(p.y - y) < 1e-8
}

fn test_affine_composition_has_independent_hand_derived_coordinates() {
	// T(10,20) * clockwise R90 * S(2,2): (3,4) -> (-8,6) -> (2,26).
	outer := ContentTransform{ x: 10, y: 20 }
	rotate := VisualTransform{ rotation: 90 }.matrix(Rect{})!
	scale := ContentTransform{ xx: 2, yy: 2 }
	t := outer.compose(rotate).compose(scale)
	assert_transform_point(t.point(3, 4), 2, 26)
	x, y := t.inverse(2, 26)
	assert_transform_point(Point{x, y}, 3, 4)
	assert_transform_point(t.vector(3, 4), -8, 6)
	// Nested nonuniform scale/reflection: inner(1,2)->(-2,6), R90->(-6,-2).
	reflected := outer.compose(rotate).compose(ContentTransform{ xx: -2, yy: 3 })
	assert_transform_point(reflected.point(1, 2), 4, 18)
	assert_transform_point(reflected.inverse_vector(-6, -2), 1, 2)
	inv := reflected.inverted()!
	assert_transform_point(inv.point(4, 18), 1, 2)
}

fn test_pivot_scaled_content_and_device_dpi_do_not_change_layout() {
	frame := rect(10.125, 20.375, 100.25, 50.75)
	visual := VisualTransform{ rotation: 90, origin_x: 50, origin_y: 25, translate_x: 10 }.matrix(frame)!
	// Pivot (60.125,45.375) moves only by translation; top-left -> (95.125,-4.625).
	assert_transform_point(visual.point(60.125, 45.375), 70.125, 45.375)
	assert_transform_point(visual.point(frame.x, frame.y), 95.125, -4.625)
	fit := contain_content(rect(0, 0, 640, 480), 1280, 720)!
	combined := fit.compose(visual)
	assert_transform_point(combined.point(frame.x, frame.y), 47.5625, 57.6875)
	for dpi in [1.0, 1.25, 1.5, 2.0] {
		p := combined.point(frame.x, frame.y)
		assert_transform_point(Point{p.x * dpi, p.y * dpi}, 47.5625 * dpi, 57.6875 * dpi)
		assert visual.rounded_local_rect(frame, dpi) == frame
		assert frame == rect(10.125, 20.375, 100.25, 50.75)
	}
}

fn test_rotated_clip_rejects_aabb_corner_and_nested_intersection() {
	frame := rect(0, 0, 100, 100)
	t := VisualTransform{ rotation: 45, origin_x: 50, origin_y: 50 }.matrix(frame)!
	clip := transformed_clip(frame, t)
	// Bounds are [-20.71..120.71]^2, but (-10,-10) is outside the diamond.
	assert box_contains_point(clip.bounds(), -10, -10)
	assert !clip.contains(-10, -10)
	assert clip.contains(50, 50)
	assert clip.contains(50, 50 - math.sqrt(5000))
	assert !transformed_contains(frame, t, clip, -10, -10)
	nested := clip.intersect(transformed_clip(rect(0, 0, 100, 50), ContentTransform{}))
	assert nested.contains(50, 25)
	assert !nested.contains(50, 75)
	assert !nested.contains(0, 0)
	reflected := transformed_clip(frame, ContentTransform{ xx: -1, x: 100 })
	assert reflected.contains(25, 25)
	assert !reflected.contains(125, 25)
	assert clip.intersect(transformed_clip(rect(200, 200, 20, 20), ContentTransform{})).points.len == 0
	// A retained parent snapshot is unchanged by an intersected child.
	assert clip.contains(50, 75)
}

fn test_clip_interpolates_textured_vertices_and_colors_exactly() {
	clip := transformed_clip(rect(25, 0, 50, 100), ContentTransform{})
	source := [PaintVertex{ x: 0, y: 0, u: 0, r: 0 }, PaintVertex{ x: 100, y: 0, u: 1, r: 200 },
		PaintVertex{ x: 100, y: 100, u: 1, v: 1, r: 200 },
		PaintVertex{ x: 0, y: 100, u: 0, v: 1, r: 0 }]
	result := clip.clip_polygon(source)
	assert result.len == 4
	for v in result {
		assert math.abs(v.x - 25) < 1e-8 || math.abs(v.x - 75) < 1e-8
		assert math.abs(v.u - v.x / 100) < 1e-9
		assert math.abs(v.r - v.x * 2) < 1e-9
		assert clip.contains(v.x, v.y)
	}
}

fn test_pan_zoom_preserves_parent_and_window_pointer_anchor() {
	camera := PanZoom{ x: 10, y: 20, zoom: 2 }
	next := camera.zoom_at(3, Point{70, 80})!
	assert next == PanZoom{ x: -20, y: -10, zoom: 3 }
	before := camera.transform().matrix(Rect{})!
	after := next.transform().matrix(Rect{})!
	// Anchor sees content (30,30) both times.
	assert_transform_point(before.point(30, 30), 70, 80)
	assert_transform_point(after.point(30, 30), 70, 80)
	outer := ContentTransform{ x: 100, y: 50 }.compose(VisualTransform{ rotation: 90 }.matrix(Rect{})!).compose(ContentTransform{ xx: 0.5, yy: 0.5 })
	assert_transform_point(outer.compose(before).point(30, 30), 60, 85)
	assert_transform_point(outer.compose(after).point(30, 30), 60, 85)
	delta := outer.inverse_vector(-5, 10)
	moved := next.pan(delta.x, delta.y)!
	assert_transform_point(outer.compose(moved.transform().matrix(Rect{})!).point(30, 30), 55, 95)
}

fn test_zoom_anchor_in_offset_layout_under_rotated_scaled_parent() {
	// Camera layout origin (90,294), camera shift (10,20), zoom 2.
	// Parent pointer (160,374) observes content (120,324), i.e. relative (30,30).
	frame := rect(90, 294, 450, 240)
	camera := PanZoom{ x: 10, y: 20, zoom: 2 }
	next := camera.zoom_at(3, Point{70, 80})!
	outer := ContentTransform{ xx: 0, xy: -0.5, yx: 0.5, yy: 0, x: 100, y: 50 }
	before := outer.compose(camera.transform().matrix(frame)!)
	after := outer.compose(next.transform().matrix(frame)!)
	assert_transform_point(before.point(120, 324), -87, 130)
	assert_transform_point(after.point(120, 324), -87, 130)
	parent_x, parent_y := outer.inverse(-87, 130)
	assert_transform_point(Point{parent_x - frame.x, parent_y - frame.y}, 70, 80)
}

fn test_invalid_transforms_reject_and_have_no_hits() {
	for t in [VisualTransform{ scale_x: 0 }, VisualTransform{ scale_y: 0 },
		VisualTransform{ rotation: math.nan() }, VisualTransform{ translate_x: math.inf(1) }] {
		if _ := t.matrix(Rect{}) {
			assert false
		}
	}
	singular := ContentTransform{ xx: 1, xy: 2, yx: 2, yy: 4 }
	assert !singular.invertible()
	assert !transformed_contains(rect(0, 0, 100, 100), singular, ClipRegion{}, 10, 10)
	if _ := singular.inverted() {
		assert false
	}
	if _ := PanZoom{}.zoom_at(0, Point{}) {
		assert false
	}
	if _ := PanZoom{ zoom: math.nan() }.pan(1, 2) {
		assert false
	}
	if _ := PanZoom{ zoom: math.inf(1) }.zoom_at(1, Point{}) {
		assert false
	}
}

fn test_native_diagnoses_visual_presentation_including_rotation() {
	$if !( android || linux || ( ( macos || windows ) && ui2_custom_rendering ?) ) && !ui2_headless ? {
		for t in [VisualTransform{ rotation: 10 }, VisualTransform{ translate_x: 1 },
			VisualTransform{ scale_y: 2 }] {
			root := with_transform(view('v', rect(0, 0, 100, 100), BoxStyle{}, []Element{}), t)
			if _ := validate_element_tree(root) {
				assert false
			} else {
				assert err.msg().contains('visual transforms require the custom renderer')
			}
		}
	}
}

fn test_vml_transform_numbers_are_typed_and_singular_values_reject() {
	for source in ['View { translate_x: "12" }', 'View { translate_y: true }', 'View { scale_x: 0 }'] {
		if _ := element_from_vml(source, rect(0, 0, 100, 100)) {
			assert false, source
		}
	}
	el := element_from_vml('View { translate_x: 10 scale_x: 2 scale_y: -1 rotation: 90 origin_x: 50 }', rect(0, 0, 100, 100))!
	assert el.visual_transform() == VisualTransform{ translate_x: 10, scale_x: 2, scale_y: -1, rotation: 90, origin_x: 50 }
	assert el.frame == rect(0, 0, 100, 100)
}

struct TransformNumberModel {
pub:
	offset        f64
	string_offset string
	bool_offset   bool
}

fn test_vml_model_transform_bindings_reject_implicit_coercion() {
	model := TransformNumberModel{ offset: 12, string_offset: '12', bool_offset: true }
	for source in ['View { translate_x: app.string_offset }', 'View { translate_x: app.bool_offset }'] {
		template := parse_vml(source)!
		if _ := v_validate_template(template, model) {
			assert false, source
		} else {
			assert err.msg().contains('requires a number')
		}
	}
	template := parse_vml('View { translate_x: app.offset }')!
	v_validate_template(template, model)!
	resolved, _ := v_evaluate_template(template, model, rect(0, 0, 100, 100))!
	el := element_from_vnode(resolved, rect(0, 0, 100, 100))!
	assert el.translate_x == 12
	if _, _ := v_evaluate_template(template, TransformNumberModel{ offset: math.inf(1) }, rect(0, 0, 100, 100)) {
		assert false
	}
}

fn test_inverse_roundoff_keeps_the_independently_derived_rotated_boundary() {
	frame := rect(0, 0, 100, 100)
	t := VisualTransform{ rotation: 45, scale_x: 1.1, scale_y: 0.8, origin_x: 50, origin_y: 50 }.matrix(frame)!
	// Local (0,100) relative to pivot: (-55,40), then R45 -> (-95,-15)/sqrt(2).
	p := Point{50 - 95 / math.sqrt(2), 50 - 15 / math.sqrt(2)}
	assert presentation_bounds_contains(t.project(frame), p.x, p.y)
	assert transformed_contains(frame, t, transformed_clip(frame, t), p.x, p.y)
	assert !transformed_contains(frame, t, ClipRegion{}, p.x - 0.01, p.y)
}
