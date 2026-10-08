module main

import math
import ui2

fn joined_stroke(points []ui2.VectorPoint, cap ui2.VectorCap, closed bool, tolerance f64) ui2.VectorShape {
	mut path := ui2.VectorPath{}
	path.move_to(points[0].x, points[0].y)
	for point in points[1..] { path.line_to(point.x, point.y) }
	if closed { path.close() }
	return ui2.prepare_vector_shape(path, ui2.VectorStyle{ stroke: 0, stroke_width: 4, cap: cap, join: .round, tolerance: tolerance }) or { panic(err) }
}

fn rotated_sample(x f64, y f64, quarter_turns int, reflection f64) ui2.VectorPoint {
	mut dx := x - 10
	mut dy := (y - 10) * reflection
	for _ in 0 .. quarter_turns {
		dx, dy = -dy, dx
	}
	return ui2.vector_point(10 + dx, 10 + dy)
}

// Independent area decomposition checks the triangles submitted for painting,
// alongside the public hit API. Expectations below come from finite rectangles
// and circular sectors, including regions a whole join disk would overpaint.
fn triangle_area(a ui2.VectorPoint, b ui2.VectorPoint, c ui2.VectorPoint) f64 {
	return math.abs(a.x * (b.y - c.y) + b.x * (c.y - a.y) + c.x * (a.y - b.y)) / 2
}

fn painted_by_stroke_mesh(shape ui2.VectorShape, point ui2.VectorPoint) bool {
	for t in shape.stroke_mesh() {
		area := triangle_area(t.a, t.b, t.c)
		parts := triangle_area(point, t.b, t.c) + triangle_area(t.a, point, t.c) + triangle_area(t.a, t.b, point)
		if math.abs(parts - area) < 1e-8 { return true }
	}
	return false
}

fn stroke_sample(shape ui2.VectorShape, point ui2.VectorPoint, expected bool) {
	assert painted_by_stroke_mesh(shape, point) == expected, 'paint mesh at ${point}'
	assert shape.contains(point.x, point.y, .stroke) == expected, 'stroke hit at ${point}'
	assert shape.contains(point.x, point.y, .paint) == expected, 'paint hit at ${point}'
	assert !shape.contains(point.x, point.y, .fill)
}

fn test_collinear_vertices_preserve_straight_stroke_and_all_cap_boundaries() {
	for rotation in 0 .. 4 {
		for cap in [ui2.VectorCap.butt, .round, .square] {
			start := rotated_sample(10, 10, rotation, 1)
			end := rotated_sample(30, 10, rotation, 1)
			plain := joined_stroke([start, end], cap, false, 0.001)
			split := joined_stroke([start, rotated_sample(10.01, 10, rotation, 1),
				rotated_sample(11, 10, rotation, 1), rotated_sample(29.99, 10, rotation, 1), end], cap, false, 0.001)
			assert plain.paint_bounds() == split.paint_bounds()
			assert split.stroke_mesh().len == plain.stroke_mesh().len + 6 // three extra quads, no joins
			for i in 0 .. 49 {
				for j in 0 .. 13 {
					x := 8 + f64(i) * 0.5
					y := 7 + f64(j) * 0.5
					inside_body := x >= 10 && x <= 30 && math.abs(y - 10) <= 2
					inside_square := x >= 8 && x <= 32 && math.abs(y - 10) <= 2
					// Stay away from the circular chord approximation in this analytic grid.
					distance2 := math.pow(x - if x < 10 { 10.0 } else { 30.0 }, 2) + math.pow(y - 10, 2)
					if cap == .round && math.abs(distance2 - 4) < 0.01 { continue }
					expected := inside_body || (cap == .square && inside_square) || (cap == .round && distance2 < 4)
					point := rotated_sample(x, y, rotation, 1)
					stroke_sample(plain, point, expected)
					stroke_sample(split, point, expected)
				}
			}
			// Confirm the original P2 sample and cap distinctions independently.
			stroke_sample(split, rotated_sample(9.5, 10, rotation, 1), cap != .butt)
			stroke_sample(split, rotated_sample(8.1, 11.9, rotation, 1), cap == .square)
			stroke_sample(split, rotated_sample(7.9, 10, rotation, 1), false)
			stroke_sample(split, rotated_sample(32.1, 10, rotation, 1), false)
		}
	}
}

fn test_non_axis_collinear_split_adds_no_round_join_at_maximum_width() {
	mut path := ui2.VectorPath{}
	path.move_to(0, 0)
	path.line_to(1, 3)
	path.line_to(6, 18)
	shape := ui2.prepare_vector_shape(path, ui2.VectorStyle{
		stroke:       0
		stroke_width: 1e7
		join:         .round
		tolerance:    0.001
	})!
	// d1 x d2 is exactly zero; normalizing each length separately can round
	// the cross product away from zero and create an unwanted join triangle.
	assert shape.stroke_mesh().len == 4
	assert !shape.contains(-0.5, -1.5, .stroke)
	assert shape.contains(3, 9, .stroke)
}

fn test_short_round_turns_paint_only_the_outer_sector_in_both_orientations() {
	for reflection in [1.0, -1.0] {
		for rotation in 0 .. 4 {
			shape := joined_stroke([rotated_sample(10, 10, rotation, reflection),
				rotated_sample(11, 10, rotation, reflection),
				rotated_sample(11, 11, rotation, reflection)], .butt, false, 0.001)
			for sample in [ui2.vector_point(12.3, 8.7), ui2.vector_point(10.5, 8.5),
				ui2.vector_point(12.5, 10.5)] {
				stroke_sample(shape, rotated_sample(sample.x, sample.y, rotation, reflection), true)
			}
			// Each excluded quadrant is inside the old join disk, but outside
			// both finite segment rectangles and the required outer NE quarter.
			for sample in [ui2.vector_point(9.5, 9.5), ui2.vector_point(9.8, 11.2),
				ui2.vector_point(12.2, 11.2), ui2.vector_point(12.6, 8.4)] {
				stroke_sample(shape, rotated_sample(sample.x, sample.y, rotation, reflection), false)
			}
		}
	}
}

fn test_oblique_short_turn_sectors_do_not_take_the_long_arc() {
	for angle in [math.pi / 6, math.pi / 3, 2 * math.pi / 3, 5 * math.pi / 6] {
		for reflection in [1.0, -1.0] {
			shape := joined_stroke([ui2.vector_point(10, 10), ui2.vector_point(11, 10),
				ui2.vector_point(11 + math.cos(angle), 10 + reflection * math.sin(angle))], .butt, false, 0.001)
			// The middle of the exterior circular corner lies ahead of the
			// incoming end and behind the outgoing start, outside both strips.
			mid := -math.pi / 2 + angle / 2
			stroke_sample(shape, ui2.vector_point(11 + 1.8 * math.cos(mid), 10 + reflection * 1.8 * math.sin(mid)), true)
			stroke_sample(shape, ui2.vector_point(11 + 2.1 * math.cos(mid), 10 + reflection * 2.1 * math.sin(mid)), false)
			// Behind the butt start and outside the finite outgoing strip, within
			// r=2 of the join: the complementary arc/disk would paint this.
			stroke_sample(shape, ui2.vector_point(9.5, 10 + reflection * 0.5), false)
		}
	}
}

fn test_round_reversal_is_forward_semicircle_not_straight_or_full_disk() {
	for rotation in 0 .. 4 {
		for deviation in [0.0, -1e-10, 1e-10] {
			shape := joined_stroke([rotated_sample(10, 10, rotation, 1),
				rotated_sample(11, 10, rotation, 1), rotated_sample(10, 10 + deviation, rotation, 1)], .butt, false, 0.001)
			for sample in [ui2.vector_point(12.8, 10), ui2.vector_point(12.3, 8.7),
				ui2.vector_point(12.3, 11.3)] {
				stroke_sample(shape, rotated_sample(sample.x, sample.y, rotation, 1), true)
			}
			for sample in [ui2.vector_point(9.5, 10), ui2.vector_point(9.8, 11.2),
				ui2.vector_point(13.1, 10)] {
				stroke_sample(shape, rotated_sample(sample.x, sample.y, rotation, 1), false)
			}
		}
	}
	// A closed two-point contour has a cusp at each end, with no open caps.
	closed := joined_stroke([ui2.vector_point(10, 10), ui2.vector_point(11, 10)], .butt, true, 0.001)
	stroke_sample(closed, ui2.vector_point(8.2, 10), true)
	stroke_sample(closed, ui2.vector_point(12.8, 10), true)
	stroke_sample(closed, ui2.vector_point(7.9, 10), false)
}

fn test_closed_round_joins_include_the_seam_and_ignore_caps() {
	for reflection in [1.0, -1.0] {
		for cap in [ui2.VectorCap.butt, .round, .square] {
			// Start in the middle of a closing edge, so the seam is straight.
			shape := joined_stroke([rotated_sample(10, 11, 0, reflection),
				rotated_sample(10, 10, 0, reflection), rotated_sample(30, 10, 0, reflection),
				rotated_sample(30, 30, 0, reflection), rotated_sample(10, 30, 0, reflection)], cap, true, 0.001)
			seam := joined_stroke([rotated_sample(10, 10, 0, reflection),
				rotated_sample(30, 10, 0, reflection), rotated_sample(30, 30, 0, reflection),
				rotated_sample(10, 30, 0, reflection)], cap, true, 0.001)
			assert shape.stroke_mesh().len == seam.stroke_mesh().len + 2
			for point in [ui2.vector_point(8.7, 8.7), ui2.vector_point(31.3, 8.7),
				ui2.vector_point(31.3, 31.3), ui2.vector_point(8.7, 31.3)] {
				stroke_sample(shape, rotated_sample(point.x, point.y, 0, reflection), true)
				stroke_sample(seam, rotated_sample(point.x, point.y, 0, reflection), true)
			}
			for point in [ui2.vector_point(8.1, 8.1), ui2.vector_point(31.9, 8.1),
				ui2.vector_point(31.9, 31.9), ui2.vector_point(8.1, 31.9),
				ui2.vector_point(12.1, 12.1), ui2.vector_point(20, 20)] {
				stroke_sample(shape, rotated_sample(point.x, point.y, 0, reflection), false)
				stroke_sample(seam, rotated_sample(point.x, point.y, 0, reflection), false)
			}
		}
	}
}

fn test_round_sector_endpoints_orientation_and_chord_tolerance() {
	for reflection in [1.0, -1.0] {
		for tolerance in [0.001, 0.25, 10.0] {
			shape := joined_stroke([ui2.vector_point(10, 10), ui2.vector_point(11, 10),
				ui2.vector_point(11, 10 + reflection)], .butt, false, tolerance)
			arcs := shape.stroke_mesh()[4..] // two independent segment quads
			assert arcs.len >= 2
			assert arcs[0].b == ui2.vector_point(11, 10 - 2 * reflection)
			assert arcs.last().c == ui2.vector_point(13, 10)
			for triangle in arcs {
				assert triangle.a == ui2.vector_point(11, 10)
				for point in [triangle.b, triangle.c] {
					assert point.x >= 11 - 1e-9
					assert (point.y - 10) * reflection <= 1e-9
					assert math.abs(math.hypot(point.x - 11, point.y - 10) - 2) < 1e-9
				}
				mid_x := (triangle.b.x + triangle.c.x) / 2 - 11
				mid_y := (triangle.b.y + triangle.c.y) / 2 - 10
				assert 2 - math.hypot(mid_x, mid_y) <= tolerance + 1e-9
				assert ((triangle.b.x - 11) * (triangle.c.y - 10) - (triangle.b.y - 10) * (triangle.c.x - 11)) * reflection > 0
			}
		}
	}
}

fn test_round_join_large_width_small_turn_and_input_guards() {
	mut path := ui2.VectorPath{}
	path.move_to(0, 0)
	path.line_to(1, 0)
	path.line_to(2, 1e-10)
	shape := ui2.prepare_vector_shape(path, ui2.VectorStyle{ stroke: 0, stroke_width: 1e7, join: .round, tolerance: 0.001 })!
	// Small nonzero turns must not be discarded by an angular epsilon:
	// at radius 5e6 this outer wedge still has area 1250 square units.
	assert shape.stroke_mesh().len == 5
	arc := shape.stroke_mesh().last()
	assert math.abs(triangle_area(arc.a, arc.b, arc.c) - 1250) < 0.01
	for triangle in shape.stroke_mesh() {
		for point in [triangle.a, triangle.b, triangle.c] {
			assert !math.is_nan(point.x) && !math.is_inf(point.x, 0)
			assert !math.is_nan(point.y) && !math.is_inf(point.y, 0)
			assert math.abs(point.x) <= 1.5e7 && math.abs(point.y) <= 1.5e7
		}
	}
	path = ui2.VectorPath{}
	path.move_to(10, 10)
	path.line_to(11, 10)
	path.line_to(11, 11)
	if _ := ui2.prepare_vector_shape(path, ui2.VectorStyle{ stroke: 0, stroke_width: 1e7, join: .round, tolerance: 0.001 }) {
		assert false, 'round sectors must retain the arc segment limit'
	} else {
		assert err.msg() == 'vector round stroke exceeds 4096 arc segments'
	}
	for width in [math.nan(), math.inf(1), 1e7 + 1] {
		if _ := ui2.prepare_vector_shape(path, ui2.VectorStyle{ stroke: 0, stroke_width: width, join: .round }) {
			assert false
		}
	}
	for coordinate in [math.nan(), math.inf(1), 1e7 + 1] {
		path = ui2.VectorPath{}
		path.move_to(0, 0)
		path.line_to(coordinate, 10)
		if _ := ui2.prepare_vector_shape(path, ui2.VectorStyle{ stroke: 0, join: .round }) {
			assert false
		}
	}
	for tolerance in [math.nan(), math.inf(1), 0.0005, 10.1] {
		if _ := ui2.prepare_vector_shape(ui2.VectorPath{}, ui2.VectorStyle{ stroke: 0, join: .round, tolerance: tolerance }) {
			assert false
		}
	}
}

fn test_round_join_sectors_respect_total_stroke_mesh_budget() {
	mut path := ui2.VectorPath{}
	for i in 0 .. 800 {
		x := f64(i) * 250
		path.move_to(x, 0)
		path.line_to(x + 1, 0)
		path.line_to(x + 1, 1)
	}
	// 800 quarter circles of radius 100 at tolerance 0.001 exceed the total
	// triangle budget while each arc and the input stay within their limits.
	if _ := ui2.prepare_vector_shape(path, ui2.VectorStyle{ stroke: 0, stroke_width: 200, join: .round, tolerance: 0.001 }) {
		assert false
	} else {
		assert err.msg() == 'vector stroke exceeds 131072 triangles'
	}
}
