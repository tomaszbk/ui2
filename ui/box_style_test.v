module ui2

import math

fn test_sparse_interaction_overrides_preserve_zero_false_and_state_precedence() {
	el := Element{
		box:               BoxStyle{ bg: 0xffffff, transparent: true, radius: 8, border_left: 2, border_color: 0x123456 }
		interaction_style: InteractionStyle{
			hover:    BoxStylePatch{ bg: u32(0), transparent: false }
			focus:    BoxStylePatch{ border_color: u32(0x0000ff), border_left: f64(0) }
			pressed:  BoxStylePatch{ bg: u32(0x00ff00) }
			disabled: BoxStylePatch{ bg: u32(0xcccccc) }
		}
	}
	assert interaction_box(el, false, false, false) == el.box
	hover := interaction_box(el, true, false, false)
	assert hover.bg == 0
	assert !hover.transparent
	assert hover.radius == 8
	focus := interaction_box(el, true, true, false)
	assert focus.bg == 0
	assert focus.border_color == 0x0000ff
	assert focus.border_left == 0
	assert interaction_box(el, true, true, true).bg == 0x00ff00
	disabled := interaction_box(Element{ ...el, enabled: false }, true, true, true)
	assert disabled.bg == 0xcccccc
	assert disabled.transparent
}

fn triangle_area(t BorderTriangle) f64 {
	return math.abs((t.b.x - t.a.x) * (t.c.y - t.a.y) -
		(t.c.x - t.a.x) * (t.b.y - t.a.y)) / 2
}

fn test_border_ring_sharp_area_and_edge_colors_are_independent_of_fill() {
	frame := rect(10, 20, 100, 60)
	box := BoxStyle{
		transparent:        true
		border_left:        2
		border_top:         3
		border_right:       4
		border_bottom:      5
		border_color:       0xabcdef
		border_left_color:  u32(0)
		border_top_color:   u32(0xff0000)
		border_right_color: u32(0x00ff00)
	}
	mut area := 0.0
	mut colors := map[u32]bool{}
	for t in box_border_triangles(frame, box) {
		area += triangle_area(t)
		if triangle_area(t) > 0.001 { colors[t.color] = true }
		for point in [t.a, t.b, t.c] {
			assert point.x >= frame.x && point.x <= frame.x + frame.width
			assert point.y >= frame.y && point.y <= frame.y + frame.height
		}
	}
	assert math.abs(area - (100 * 60 - 94 * 52)) < 0.000001
	assert colors.len == 4
	assert u32(0) in colors
	assert u32(0xff0000) in colors
	assert u32(0x00ff00) in colors
	assert u32(0xabcdef) in colors
}

fn test_rounded_border_ring_matches_analytic_area_and_stays_inside_bounds() {
	box := BoxStyle{ radius: 12, border_left: 2, border_top: 2, border_right: 2, border_bottom: 2 }
	mut area := 0.0
	for t in box_border_triangles(rect(0, 0, 100, 60), box) { area += triangle_area(t) }
	// Difference between two rounded-rectangle areas; polygon tolerance is
	// bounded by the independent analytic result rather than adapter output.
	expected := (6000.0 - (4 - math.pi) * 144) - (96 * 56 - (4 - math.pi) * 100)
	assert math.abs(area - expected) < 0.25
	assert box_border_triangles(rect(0, 0, 0, 60), box).len == 0
}

fn test_dashed_border_has_gaps_and_clamps_excessive_widths() {
	base := BoxStyle{ border_top: 2, border_right: 2, border_bottom: 2, border_left: 2 }
	mut solid := 0.0
	mut dashed := 0.0
	for t in box_border_triangles(rect(0, 0, 100, 60), base) { solid += triangle_area(t) }
	for t in box_border_triangles(rect(0, 0, 100, 60), BoxStyle{ ...base, border_pattern: .dashed }) {
		dashed += triangle_area(t)
	}
	assert dashed > solid * 0.5 && dashed < solid * 0.7
	mut thick := 0.0
	for t in box_border_triangles(rect(0, 0, 10, 10), BoxStyle{ border_left: 30, border_right: 30 }) {
		thick += triangle_area(t)
	}
	assert math.abs(thick - 100) < 0.000001
}

fn test_vml_border_colors_and_interaction_patches_keep_omitted_values_unset() {
	el := compiled_box_style_1(rect(0, 0, 100, 60))
	assert box_edge_color(el.box, 3) == 0
	assert box_edge_color(el.box, 0) == 0xaabbcc
	assert el.box.border_pattern == .dashed
	assert interaction_box(el, true, false, false).bg == 0
	assert interaction_box(el, true, true, false).border_top == 0
	assert el.interaction_style.hover.radius == none
	assert !interaction_box(el, true, true, true).transparent
}

fn test_focus_outline_is_outside_without_changing_frame_or_hit_bounds() {
	el := compiled_box_style_0(rect(10, 20, 80, 40))
	assert interaction_text_style(el, true, false, false).color == 0
	assert interaction_text_style(el, false, false, false) == el.text_style
	box := interaction_box(el, false, true, false)
	outer, outline := box_outline_geometry(el.frame, box)
	assert outer == rect(4, 14, 92, 52)
	assert outline.border_top == 3
	assert outline.border_color == 0x2563eb
	assert el.frame == rect(10, 20, 80, 40)
	assert !box_contains_point(el.frame, 8, 20)
	assert interaction_box(el, false, false, false).outline_width == 0
}

fn test_rounded_single_edge_keeps_its_color_through_both_corner_halves() {
	for side in 0 .. 4 {
		widths := [if side == 0 { 4.0 } else { 0.0 }, if side == 1 { 4.0 } else { 0.0 },
			if side == 2 { 4.0 } else { 0.0 }, if side == 3 { 4.0 } else { 0.0 }]
		box := BoxStyle{
			radius:              12
			border_top:          widths[0]
			border_right:        widths[1]
			border_bottom:       widths[2]
			border_left:         widths[3]
			border_color:        0xff0000
			border_top_color:    if side == 0 { ?u32(0x0000ff) } else { none }
			border_right_color:  if side == 1 { ?u32(0x0000ff) } else { none }
			border_bottom_color: if side == 2 { ?u32(0x0000ff) } else { none }
			border_left_color:   if side == 3 { ?u32(0x0000ff) } else { none }
		}
		for triangle in box_border_triangles(rect(0, 0, 100, 60), box) {
			if triangle_area(triangle) > 0.000001 {
				assert triangle.color == 0x0000ff
			}
		}
	}
}

fn test_fractional_rounded_border_retains_subunit_outer_and_inner_corners() {
	frame := rect(10, 20, 10, 10)
	mesh := box_border_triangles(frame, BoxStyle{ radius: 0.75, border_left: 0.25, border_top: 0.25, border_right: 0.25, border_bottom: 0.25 })
	mut contains_outer_arc := false
	mut contains_inner_arc := false
	for triangle in mesh {
		for p in [triangle.a, triangle.b, triangle.c] {
			// The top-left arc occupies the open corner square; a sharp ring
			// instead has vertices only on the straight edges.
			if p.x > 10 && p.x < 10.25 && p.y > 20 && p.y < 20.75 { contains_outer_arc = true }
			if p.x > 10.25 && p.x < 10.75 && p.y > 20.25 && p.y < 20.75 {
				contains_inner_arc = true
			}
		}
	}
	assert contains_outer_arc
	assert contains_inner_arc
}

fn compiled_box_style_0(frame Rect) Element {
	return $vml('fixtures/box_style_0.vml', frame)
}

fn compiled_box_style_1(frame Rect) Element {
	return $vml('fixtures/box_style_1.vml', frame)
}
