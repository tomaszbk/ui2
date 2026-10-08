module main

import math
import ui2

fn near(actual f64, expected f64) {
	assert math.abs(actual - expected) < 1e-7, '${actual} != ${expected}'
}

fn mesh_area(mesh []ui2.VectorTriangle) f64 {
	mut area := 0.0
	for t in mesh {
		area += math.abs((t.b.x - t.a.x) * (t.c.y - t.a.y) - (t.b.y - t.a.y) * (t.c.x - t.a.x)) / 2
	}
	return area
}

fn polygon(points []ui2.VectorPoint, style ui2.VectorStyle) ui2.VectorShape {
	return ui2.prepare_vector_shape(ui2.vector_polygon(points), style) or { panic(err) }
}

fn test_concave_polygon_area_and_fill_are_not_bounds() {
	// 10x10 square minus the upper-right 6x6 corner: exact area 64.
	shape := polygon([ui2.vector_point(0, 0), ui2.vector_point(10, 0), ui2.vector_point(10, 4),
		ui2.vector_point(4, 4), ui2.vector_point(4, 10), ui2.vector_point(0, 10)], ui2.VectorStyle{ fill: 0x112233 })
	near(mesh_area(shape.fill_mesh()), 64)
	assert shape.contains(2, 8, .fill)
	assert shape.contains(8, 2, .paint)
	assert !shape.contains(8, 8, .fill)
	assert shape.contains(8, 8, .bounds)
	assert shape.contains(4, 8, .fill) // painted boundary included
	assert !shape.contains(4.001, 8, .paint)
	assert !shape.contains(2, 2, .stroke)
}

fn hole_path(reverse bool) ui2.VectorPath {
	mut path := ui2.vector_polygon([ui2.vector_point(0, 0), ui2.vector_point(20, 0),
		ui2.vector_point(20, 20), ui2.vector_point(0, 20)])
	path.move_to(5, 5)
	if reverse {
		path.line_to(5, 15)
		path.line_to(15, 15)
		path.line_to(15, 5)
	} else {
		path.line_to(15, 5)
		path.line_to(15, 15)
		path.line_to(5, 15)
	}
	path.close()
	return path
}

fn test_holes_and_winding_rules_have_independent_areas() {
	for reverse in [false, true] {
		for rule in [ui2.VectorFillRule.nonzero, .even_odd] {
			shape := ui2.prepare_vector_shape(hole_path(reverse), ui2.VectorStyle{ fill: 0x112233, fill_rule: rule })!
			hole := reverse || rule == .even_odd
			near(mesh_area(shape.fill_mesh()), if hole { 300.0 } else { 400.0 })
			assert shape.contains(10, 10, .fill) == !hole
			assert shape.contains(2, 10, .fill)
			assert shape.contains(5, 10, .fill) // boundary shared with outer paint
		}
	}
	// Intersecting bowtie has two triangular lobes of area 25 each.
	bowtie := polygon([ui2.vector_point(0, 0), ui2.vector_point(10, 10), ui2.vector_point(0, 10),
		ui2.vector_point(10, 0)], ui2.VectorStyle{ fill: 0, fill_rule: .even_odd })
	near(mesh_area(bowtie.fill_mesh()), 50)
	assert bowtie.contains(5, 1, .fill)
	assert !bowtie.contains(1, 5, .fill)
}

fn test_quadratic_and_cubic_bezier_sampled_geometry() {
	mut path := ui2.VectorPath{}
	path.move_to(0, 0)
	path.quadratic_to(10, 20, 20, 0)
	quad := ui2.prepare_vector_shape(path, ui2.VectorStyle{ stroke: 0, stroke_width: 2, tolerance: 0.01 })!
	points := quad.flattened_contours()[0].points
	// B(1/2)=(10,10), independently from polynomial coefficients.
	mid := points[points.len / 2]
	near(mid.x, 10)
	near(mid.y, 10)
	assert quad.contains(10, 10, .stroke)
	assert !quad.contains(10, 12, .stroke)
	assert !quad.contains(10, 3, .fill)
	path = ui2.VectorPath{}
	path.move_to(0, 0)
	path.cubic_to(0, 16, 16, 16, 16, 0)
	cubic := ui2.prepare_vector_shape(path, ui2.VectorStyle{ fill: 0, stroke: 0, tolerance: 0.01 })!
	cp := cubic.flattened_contours()[0].points
	near(cp[cp.len / 2].x, 8)
	near(cp[cp.len / 2].y, 12)
	assert cubic.contains(8, 6, .fill) // implicit closing edge for open fill
	assert !cubic.contains(8, 13, .paint)
	// Compare the entire approximation to independent analytic samples.
	for i in 0 .. 101 {
		t := f64(i) / 100
		x := 48 * t * t - 32 * t * t * t
		y := 48 * t * (1 - t)
		assert cubic.contains(x, y, .stroke)
	}
	mut backtracking := ui2.VectorPath{}
	backtracking.move_to(0, 0)
	backtracking.cubic_to(30, 0, -30, 0, 1, 0)
	assert backtracking.flatten(0.01)![0].points.len > 2
}

fn line_shape(cap ui2.VectorCap) ui2.VectorShape {
	mut path := ui2.VectorPath{}
	path.move_to(10, 10)
	path.line_to(30, 10)
	return ui2.prepare_vector_shape(path, ui2.VectorStyle{ stroke: 0, stroke_width: 4, cap: cap, tolerance: 0.001 }) or { panic(err) }
}

fn test_every_cap_and_fill_stroke_hit_mode() {
	butt := line_shape(.butt)
	near(mesh_area(butt.stroke_mesh()), 80)
	assert butt.contains(10, 12, .stroke)
	assert !butt.contains(9, 10, .stroke)
	assert !butt.contains(20, 10, .fill)
	square := line_shape(.square)
	near(mesh_area(square.stroke_mesh()), 96)
	assert square.contains(8.1, 11.9, .stroke)
	assert !square.contains(7.9, 10, .stroke)
	round := line_shape(.round)
	assert round.contains(8.1, 10, .stroke)
	assert !round.contains(8.1, 11.9, .stroke)
	assert round.contains(8.1, 11.9, .bounds)
	assert !round.contains(20, 12.01, .stroke)
}

fn corner_shape(join ui2.VectorJoin, limit f64) ui2.VectorShape {
	mut path := ui2.VectorPath{}
	path.move_to(0, 0)
	path.line_to(10, 0)
	path.line_to(10, 10)
	return ui2.prepare_vector_shape(path, ui2.VectorStyle{ stroke: 0, stroke_width: 4, join: join, miter_limit: limit, tolerance: 0.001 }) or { panic(err) }
}

fn test_every_join_and_miter_limit() {
	// Outer 90-degree corner is (12,-2); bevel cuts x-y>12.
	miter := corner_shape(.miter, 4)
	bevel := corner_shape(.bevel, 4)
	round := corner_shape(.round, 4)
	assert miter.contains(11.9, -1.9, .stroke)
	assert !bevel.contains(11.9, -1.9, .stroke)
	assert !round.contains(11.9, -1.9, .stroke)
	assert round.contains(11.3, -1.3, .stroke)
	assert !bevel.contains(11.3, -1.3, .stroke)
	assert bevel.contains(10.8, -0.8, .stroke)
	assert !corner_shape(.miter, 1).contains(11.3, -1.3, .stroke)
	// Reflection reverses winding and picks the other outer side.
	mut path := ui2.VectorPath{}
	path.move_to(0, 0)
	path.line_to(10, 0)
	path.line_to(10, -10)
	left := ui2.prepare_vector_shape(path, ui2.VectorStyle{ stroke: 0, stroke_width: 4 })!
	assert left.contains(11.9, 1.9, .stroke)
}

fn test_open_fill_closed_stroke_and_degenerate_contours() {
	mut open := ui2.VectorPath{}
	open.move_to(0, 0)
	open.line_to(10, 0)
	open.line_to(10, 10)
	a := ui2.prepare_vector_shape(open, ui2.VectorStyle{ fill: 0, stroke: 0, stroke_width: 1 })!
	assert a.contains(7, 3, .fill)
	assert !a.contains(5, 5, .stroke) // open stroke has no diagonal closing segment
	open.close()
	b := ui2.prepare_vector_shape(open, ui2.VectorStyle{ stroke: 0, stroke_width: 1, cap: .square })!
	assert b.contains(5, 5, .stroke)
	assert b.flattened_contours()[0].closed
	mut point := ui2.VectorPath{}
	point.move_to(10, 10)
	point.line_to(10, 10)
	for cap in [ui2.VectorCap.butt, .square, .round] {
		shape := ui2.prepare_vector_shape(point, ui2.VectorStyle{ stroke: 0, stroke_width: 4, cap: cap })!
		assert shape.contains(10, 10, .stroke) == (cap == .round)
	}
	zero := ui2.prepare_vector_shape(open, ui2.VectorStyle{ stroke: 0, stroke_width: 0 })!
	assert !zero.contains(5, 0, .paint)
}

fn test_snapshots_and_input_validation() {
	mut path := ui2.vector_polygon([ui2.vector_point(0, 0), ui2.vector_point(10, 0),
		ui2.vector_point(0, 10)])
	shape := ui2.prepare_vector_shape(path, ui2.VectorStyle{ fill: 0 })!
	path.commands.clear()
	mut mesh := shape.fill_mesh()
	mesh.clear()
	mut contours := shape.flattened_contours()
	contours[0] = ui2.VectorContour{}
	assert shape.contains(1, 1, .paint)
	mut invalid := ui2.VectorPath{}
	invalid.line_to(0, 0)
	if _ := invalid.flatten(0.1) {
		assert false
	}
	invalid = ui2.VectorPath{}
	invalid.move_to(math.inf(1), 0)
	if _ := invalid.flatten(0.1) {
		assert false
	}
	for style in [ui2.VectorStyle{ tolerance: 0 }, ui2.VectorStyle{ stroke_width: -1 },
		ui2.VectorStyle{ miter_limit: 0 }] {
		if _ := ui2.prepare_vector_shape(ui2.VectorPath{}, style) {
			assert false
		}
	}
	if _ := ui2.vector_canvas(frame: ui2.rect(0, 0, 10, 10), shapes: [ui2.VectorShape{}]) {
		assert false
	}
	assert !shape.contains(math.nan(), 0, .fill)
}

fn test_round_point_contours_respect_the_stroke_mesh_budget() {
	// Radius 100 at tolerance 0.001 needs over 700 chords per disk.
	// 200 distinct point contours exceed the documented total paint budget,
	// while staying well below the command and flattened-point limits.
	mut path := ui2.VectorPath{}
	for i in 0 .. 200 {
		path.move_to(f64(i) * 250, 0)
	}
	if _ := ui2.prepare_vector_shape(path, ui2.VectorStyle{
		stroke: 0
		stroke_width: 200
		cap: .round
		tolerance: 0.001
	}) {
		assert false, 'round point contours must respect the total stroke mesh budget'
	} else {
		assert err.msg() == 'vector stroke exceeds 131072 triangles'
	}
}

fn test_native_profile_rejects_vector_presentation() {
	shape := line_shape(.butt)
	for shapes in [[shape], []ui2.VectorShape{}] {
		el := ui2.vector_canvas(id: 'shape', frame: ui2.rect(0, 0, 40, 40), shapes: shapes)!
		$if !( android || linux || ( ( macos || windows ) && ui2_custom_rendering ?) ) && !ui2_headless ? {
			if _ := ui2.validate_element_tree(el) {
				assert false
			} else {
				assert err.msg().contains('vector canvas requires the custom renderer')
			}
		} $else {
			ui2.validate_element_tree(el)!
		}
	}
}
