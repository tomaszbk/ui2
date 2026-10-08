module main

import math
import ui2

fn capped_path(points []ui2.VectorPoint, cap ui2.VectorCap, join ui2.VectorJoin, closed bool, tolerance f64) ui2.VectorShape {
	mut path := ui2.VectorPath{}
	path.move_to(points[0].x, points[0].y)
	for point in points[1..] { path.line_to(point.x, point.y) }
	if closed { path.close() }
	return ui2.prepare_vector_shape(path, ui2.VectorStyle{ stroke: 0, stroke_width: 4, cap: cap, join: join, tolerance: tolerance }) or { panic(err) }
}

fn cap_rotation(point ui2.VectorPoint, rotation int, reflection f64) ui2.VectorPoint {
	mut x := point.x - 10
	mut y := (point.y - 10) * reflection
	for _ in 0 .. rotation { x, y = -y, x }
	return ui2.vector_point(10 + x, 10 + y)
}

fn cap_area(a ui2.VectorPoint, b ui2.VectorPoint, c ui2.VectorPoint) f64 {
	return math.abs(a.x * (b.y - c.y) + b.x * (c.y - a.y) + c.x * (a.y - b.y)) / 2
}

// Independent area decomposition of the public paint mesh, with literal
// oracles derived from finite strips, bevel triangles and outward half circles.
fn cap_mesh_paints(shape ui2.VectorShape, point ui2.VectorPoint) bool {
	for t in shape.stroke_mesh() {
		area := cap_area(t.a, t.b, t.c)
		if area > 0 && math.abs(cap_area(point, t.b, t.c) + cap_area(t.a, point, t.c) + cap_area(t.a, t.b, point) - area) < 1e-8 {
			return true
		}
	}
	return false
}

fn cap_sample(shape ui2.VectorShape, point ui2.VectorPoint, expected bool) {
	assert cap_mesh_paints(shape, point) == expected, 'paint mesh at ${point}, expected ${expected}'
	assert shape.contains(point.x, point.y, .stroke) == expected
	assert shape.contains(point.x, point.y, .paint) == expected
	assert !shape.contains(point.x, point.y, .fill)
}

fn test_short_bevelled_endpoint_caps_exclude_inward_disk_overpaint() {
	for reflection in [1.0, -1.0] {
		for rotation in 0 .. 4 {
			for reverse in [false, true] {
				mut points := [ui2.vector_point(10, 10), ui2.vector_point(10.1, 10),
					ui2.vector_point(10.1, 20)]
				if reverse { points.reverse_in_place() }
				points = points.map(cap_rotation(it, rotation, reflection))
				shape := capped_path(points, .round, .bevel, false, 0.001)
				// (11.3,8.7) is inside the old start disk but outside both
				// strips, the bevel x-10.1+10-y<=2, and outward caps.
				// Reversing commands exercises the same defect at the end.
				for point in [ui2.vector_point(11.3, 8.7), ui2.vector_point(11.9, 8.1),
					ui2.vector_point(7.9, 10), ui2.vector_point(12.2, 15),
					ui2.vector_point(10.1, 22.1)] {
					cap_sample(shape, cap_rotation(point, rotation, reflection), false)
				}
				for point in [ui2.vector_point(8.5, 10), ui2.vector_point(8.7, 8.7),
					ui2.vector_point(11.3, 9.3), ui2.vector_point(12, 15),
					ui2.vector_point(10.1, 21.5), ui2.vector_point(11.4, 21.3)] {
					cap_sample(shape, cap_rotation(point, rotation, reflection), true)
				}
			}
		}
	}
	shape := capped_path([ui2.vector_point(10, 10), ui2.vector_point(10.1, 10),
		ui2.vector_point(10.1, 20)], .round, .bevel, false, 0.001)
	bounds := shape.paint_bounds()
	assert math.abs(bounds.x - 8) < 1e-9 && math.abs(bounds.y - 8) < 1e-9
	assert math.abs(bounds.width - 4.1) < 1e-9 && math.abs(bounds.height - 14) < 1e-9
}

fn test_short_reversal_caps_face_left_and_preserve_bevel_bounds() {
	for rotation in 0 .. 4 {
		points := [ui2.vector_point(10, 10), ui2.vector_point(11, 10), ui2.vector_point(10, 10)].map(cap_rotation(it, rotation, 1))
		shape := capped_path(points, .round, .bevel, false, 0.001)
		for point in [ui2.vector_point(11.5, 10), ui2.vector_point(11.3, 8.7),
			ui2.vector_point(11.3, 11.3), ui2.vector_point(7.9, 10), ui2.vector_point(8.1, 8.1)] {
			cap_sample(shape, cap_rotation(point, rotation, 1), false)
		}
		for point in [ui2.vector_point(8.5, 10), ui2.vector_point(8.7, 8.7),
			ui2.vector_point(8.7, 11.3), ui2.vector_point(10.5, 8.5), ui2.vector_point(10.5, 11.5)] {
			cap_sample(shape, cap_rotation(point, rotation, 1), true)
		}
		expected := [ui2.rect(8, 8, 3, 4), ui2.rect(8, 8, 4, 3), ui2.rect(9, 8, 3, 4),
			ui2.rect(8, 9, 4, 3)][rotation]
		assert shape.paint_bounds() == expected
		assert !shape.contains(cap_rotation(ui2.vector_point(11.5, 10), rotation, 1).x, cap_rotation(ui2.vector_point(11.5, 10), rotation, 1).y, .bounds)
		// A round JOIN at the cusp legitimately paints ahead of x=11.
		round_join := capped_path(points, .butt, .round, false, 0.001)
		cap_sample(round_join, cap_rotation(ui2.vector_point(11.5, 10), rotation, 1), true)
		cap_sample(round_join, cap_rotation(ui2.vector_point(9.5, 10), rotation, 1), false)
		butt := capped_path(points, .butt, .bevel, false, 0.001)
		cap_sample(butt, cap_rotation(ui2.vector_point(11.5, 10), rotation, 1), false)
	}
}

fn test_round_cap_arc_hemispheres_endpoints_chord_error_and_coarse_tolerance() {
	for direction in [ui2.vector_point(1, 0), ui2.vector_point(0, 1), ui2.vector_point(-1, 0),
		ui2.vector_point(0, -1), ui2.vector_point(0.6, 0.8), ui2.vector_point(-0.8, 0.6)] {
		start := ui2.vector_point(10, 10)
		end := ui2.vector_point(10 + 20 * direction.x, 10 + 20 * direction.y)
		n := ui2.vector_point(-2 * direction.y, 2 * direction.x)
		for tolerance in [0.001, 0.003, 0.25, 10.0] {
			shape := capped_path([start, end], .round, .bevel, false, tolerance)
			arcs := shape.stroke_mesh()[2..] // segment quad first
			assert arcs.len % 2 == 0
			count := arcs.len / 2
			assert count >= 4 && count <= 4096
			for index, center in [start, end] {
				arc := arcs[index * count..(index + 1) * count]
				sign := if index == 0 { 1.0 } else { -1.0 }
				assert arc[0].b == ui2.vector_point(center.x + sign * n.x, center.y + sign * n.y)
				assert arc.last().c == ui2.vector_point(center.x - sign * n.x, center.y - sign * n.y)
				mut area := 0.0
				for triangle in arc {
					assert triangle.a == center
					area += cap_area(triangle.a, triangle.b, triangle.c)
					for point in [triangle.b, triangle.c] {
						x, y := point.x - center.x, point.y - center.y
						assert math.abs(math.hypot(x, y) - 2) < 1e-9
						// Start is behind its forward tangent; end is ahead.
						assert sign * (x * direction.x + y * direction.y) <= 1e-9
					}
					bx, by := triangle.b.x - center.x, triangle.b.y - center.y
					cx, cy := triangle.c.x - center.x, triangle.c.y - center.y
					assert bx * cy - by * cx > 0
					assert 2 - math.hypot((bx + cx) / 2, (by + cy) / 2) <= tolerance + 1e-9
					assert bx * cx + by * cy >= 4 * math.cos(math.pi / 4) - 1e-9
				}
				assert math.abs(area - 2 * f64(count) * math.sin(math.pi / f64(count))) < 1e-8
				outward := ui2.vector_point(center.x - sign * 1.2 * direction.x, center.y - sign * 1.2 * direction.y)
				cap_sample(shape, outward, true)
			}
		}
	}
}

fn test_normalization_disconnected_and_zero_length_round_caps() {
	base := [ui2.vector_point(10, 10), ui2.vector_point(11, 10), ui2.vector_point(10, 10)]
	plain := capped_path(base, .round, .bevel, false, 0.001)
	duplicated := capped_path([base[0], base[0], base[1], base[1], base[2], base[2]], .round, .bevel, false, 0.001)
	assert duplicated.flattened_contours()[0].points == base
	assert duplicated.stroke_mesh() == plain.stroke_mesh()
	mut path := ui2.VectorPath{}
	for dx in [0.0, 30.0] {
		for index, point in base {
			if index == 0 {
				path.move_to(point.x + dx, point.y)
			} else {
				path.line_to(point.x + dx, point.y)
			}
		}
	}
	multi := ui2.prepare_vector_shape(path, ui2.VectorStyle{ stroke: 0, stroke_width: 4, cap: .round, join: .bevel, tolerance: 0.001 })!
	for x in [11.5, 41.5, 25.0] { cap_sample(multi, ui2.vector_point(x, 10), false) }
	for x in [8.5, 38.5] { cap_sample(multi, ui2.vector_point(x, 10), true) }
	for cap in [ui2.VectorCap.butt, .square, .round] {
		for closed in [false, true] {
			point := capped_path([ui2.vector_point(10, 10), ui2.vector_point(10, 10)], cap, .bevel, closed, 0.001)
			paints := cap == .round && !closed
			for p in [ui2.vector_point(10, 10), ui2.vector_point(11.3, 8.7),
				ui2.vector_point(8.7, 8.7), ui2.vector_point(8.7, 11.3), ui2.vector_point(11.3, 11.3)] {
				cap_sample(point, p, paints)
			}
			cap_sample(point, ui2.vector_point(12.1, 10), false)
			if paints {
				assert point.paint_bounds() == ui2.rect(8, 8, 4, 4)
			} else {
				assert point.stroke_mesh().len == 0
			}
		}
	}
	// Closed contours have joins but no caps, even at a two-point cusp.
	closed_butt := capped_path(base, .butt, .bevel, true, 0.001)
	closed_round := capped_path(base, .round, .bevel, true, 0.001)
	assert closed_butt.stroke_mesh() == closed_round.stroke_mesh()
}

fn test_round_caps_on_isolated_lines_and_flattened_curve_tangents() {
	for length in [0.1, 20.0] {
		line := capped_path([ui2.vector_point(10, 10), ui2.vector_point(10 + length, 10)], .round, .bevel, false, 0.001)
		for p in [ui2.vector_point(8.5, 10), ui2.vector_point(11.5 + length, 10),
			ui2.vector_point(10 + length / 2, 11.5)] {
			cap_sample(line, p, true)
		}
		for p in [ui2.vector_point(7.9, 10), ui2.vector_point(12.1 + length, 10),
			ui2.vector_point(8.1, 11.9)] {
			cap_sample(line, p, false)
		}
		bounds := line.paint_bounds()
		assert math.abs(bounds.x - 8) < 1e-9 && math.abs(bounds.width - (length + 4)) < 1e-9
		if length == 20 {
			mut area := 0.0
			for t in line.stroke_mesh() { area += cap_area(t.a, t.b, t.c) }
			// Analytic capsule area 80 + 4*pi, with inscribed chord error.
			// Full endpoint disks double-paint their inward halves and exceed this.
			assert area > 92.55 && area < 92.57
		}
	}
	mut path := ui2.VectorPath{}
	path.move_to(10, 10)
	path.quadratic_to(11, 10, 11, 11)
	path.cubic_to(11, 12, 10, 12, 10, 11)
	shape := ui2.prepare_vector_shape(path, ui2.VectorStyle{ stroke: 0, stroke_width: 4, cap: .round, join: .bevel, tolerance: 0.001 })!
	points := shape.flattened_contours()[0].points
	first := ui2.vector_point(points[1].x - points[0].x, points[1].y - points[0].y)
	last := ui2.vector_point(points.last().x - points[points.len - 2].x, points.last().y - points[points.len - 2].y)
	for index, center in [points[0], points.last()] {
		tangent := if index == 0 { first } else { last }
		sign := if index == 0 { -1.0 } else { 1.0 }
		outward := ui2.vector_point(center.x + sign * 1.8 * tangent.x / math.hypot(tangent.x, tangent.y), center.y + sign * 1.8 * tangent.y / math.hypot(tangent.x, tangent.y))
		cap_sample(shape, outward, true)
	}
}

fn test_round_endpoint_caps_share_arc_and_total_mesh_budgets() {
	mut path := ui2.VectorPath{}
	path.move_to(0, 0)
	path.line_to(1, 0)
	if _ := ui2.prepare_vector_shape(path, ui2.VectorStyle{ stroke: 0, stroke_width: 1e7, cap: .round, tolerance: 0.001 }) {
		assert false
	} else {
		assert err.msg() == 'vector round stroke exceeds 4096 arc segments'
	}
	path = ui2.VectorPath{}
	for i in 0 .. 200 {
		path.move_to(f64(i) * 250, 0)
		path.line_to(f64(i) * 250 + 1, 0)
	}
	if _ := ui2.prepare_vector_shape(path, ui2.VectorStyle{ stroke: 0, stroke_width: 200, cap: .round, tolerance: 0.001 }) {
		assert false
	} else {
		assert err.msg() == 'vector stroke exceeds 131072 triangles'
	}
}
