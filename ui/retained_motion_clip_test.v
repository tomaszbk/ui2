// vtest vflags: -gc boehm -d no_gc_thread_local_alloc
module ui2

import math

fn inline_convex_clip(vertices []Point) ClipRegion {
	if vertices.len > 32 {
		return ClipRegion{ bounded: true, points: vertices.clone() }.normalized()
	}
	extent, winding := clip_basis(vertices)
	if winding == 0 { return ClipRegion{ bounded: true } }
	mut points := [32]Point{}
	for i, vertex in vertices { points[i] = vertex }
	clip := ClipRegion{ bounded: true, inline_convex: points, inline_count: vertices.len }
	if winding > 0 && !clip.has_redundant_points(extent) { return clip }
	return convex_clip_result_storage(vertices, true)
}

fn retained_clip_fixture_vertices(frame Rect) []PaintVertex {
	return [PaintVertex{ x: frame.x, y: frame.y, u: 0, v: 0, a: 20 },
		PaintVertex{ x: frame.x + frame.width, y: frame.y, u: 1, v: 0, a: 80 },
		PaintVertex{ x: frame.x + frame.width, y: frame.y + frame.height, u: 1, v: 1, a: 160 },
		PaintVertex{ x: frame.x, y: frame.y + frame.height, u: 0, v: 1, a: 240 }]
}

fn assert_retained_clip_matches_public(retained ClipRegion, public ClipRegion) {
	assert retained.bounded == public.bounded
	assert retained.bounds() == public.bounds()
	for y in -8 .. 24 {
		for x in -8 .. 24 {
			px, py := f64(x) * 7.125 + 0.375, f64(y) * 6.25 + 0.625
			assert retained.contains(px, py) == public.contains(px, py)
		}
	}
	paint := retained_clip_fixture_vertices(rect(-10, -15, 190, 170))
	actual := retained.clip_polygon(paint)
	expected := public.clip_polygon(paint)
	assert actual.len == expected.len
	for vertex in actual {
		assert expected.any(math.abs(it.x - vertex.x) < 1e-12 && math.abs(it.y - vertex.y) < 1e-12
			&& math.abs(it.u - vertex.u) < 1e-12 && math.abs(it.v - vertex.v) < 1e-12
			&& math.abs(it.a - vertex.a) < 1e-9)
	}
}

fn test_inline_rotated_clips_match_owned_geometry_and_keep_old_snapshots() ! {
	frame := rect(10.25, 20.5, 120.75, 80.125)
	other := rect(30.5, 4.25, 100.25, 100.5)
	mut previous := ClipRegion{}
	mut previous_bounds := Rect{}
	for rotation in [-53.0, -19, 0, 17, 74] {
		for scale in [-1.1, 0.8] {
			transform := VisualTransform{ rotation: rotation, scale_x: scale, origin_x: 60, origin_y: 40 }.matrix(frame)!
			retained := paint_transformed_clip(frame, transform)
			public := transformed_clip(frame, transform)
			assert public.points.len == 4
			assert retained.inline_storage() && retained.points.len == 0
			assert_retained_clip_matches_public(retained, public)
			nested_transform := VisualTransform{ rotation: -rotation / 2, origin_x: 50, origin_y: 50 }.matrix(other)!
			intersection := retained.intersect(paint_transformed_clip(other, nested_transform))
			oracle := public.intersect(transformed_clip(other, nested_transform))
			assert_retained_clip_matches_public(intersection, oracle)
			assert previous.bounds() == previous_bounds
			previous = intersection
			previous_bounds = intersection.bounds()
		}
	}
}

fn test_inline_tiny_sliver_and_shared_transformed_edges_remain_exact() {
	epsilon := math.ldexp(1, -52)
	triangle := [Point{0, 0}, Point{1, 1 + epsilon}, Point{1 - epsilon, 1}]
	sliver := inline_convex_clip(triangle)
	public := ClipRegion{ bounded: true, points: triangle }
	assert sliver.inline_count == 3 && sliver.bounds() == public.bounds()
	assert sliver.contains(0, 0) && !sliver.contains(2, 2)
	intersection := sliver.intersect(sliver)
	assert intersection.inline_count == 3 && intersection.bounds() == public.bounds()
	for frame in [rect(0, 0, 1e-200, 1e-200), rect(1e12, 1e12, 0.25, 0.5)] {
		for transform in [ContentTransform{}, ContentTransform{ xx: -1, xy: 0.25, yx: 0.125 }] {
			retained := paint_transformed_clip(frame, transform)
			oracle := transformed_clip(frame, transform)
			assert retained.bounds() == oracle.bounds()
			center := transform.point(frame.x + frame.width / 2, frame.y + frame.height / 2)
			assert retained.contains(center.x, center.y) == oracle.contains(center.x, center.y)
			assert retained.intersect(retained).bounds() == oracle.intersect(oracle).bounds()
		}
	}
	viewport := [Point{82.10784033180889, 53.519846543696175},
		Point{230.95515146429682, 107.69583724648213}, Point{219.1349353109617, 140.1716142208431},
		Point{70.28762417847376, 85.99562351805716}]
	selection := [Point{150.9564384423796, 78.57868692690025},
		Point{167.7459100743364, 84.68955484998929}, Point{162.4084119889148, 99.3542103160674},
		Point{145.618940356958, 93.24334239297832}]
	retained := inline_convex_clip(viewport).intersect(inline_convex_clip(selection))
	oracle := ClipRegion{ bounded: true, points: viewport }.intersect(ClipRegion{ bounded: true, points: selection })
	assert_retained_clip_matches_public(retained, oracle)
	assert retained.contains(156, 89)
}

fn clip_regular_polygon(count int, phase f64) []Point {
	mut points := []Point{cap: count}
	for i in 0 .. count {
		angle := 2 * math.pi * (f64(i) + phase) / f64(count)
		points << Point{100 * math.cos(angle), 100 * math.sin(angle)}
	}
	return points
}

fn test_inline_convex_capacity_promotes_owned_results_without_losing_vertices() {
	first := clip_regular_polygon(24, 0)
	second := clip_regular_polygon(24, 0.5)
	retained := inline_convex_clip(first).intersect(inline_convex_clip(second))
	oracle := ClipRegion{ bounded: true, points: first }.intersect(ClipRegion{ bounded: true, points: second })
	assert retained.inline_count == 0 && retained.points.len == 48
	assert retained.points == oracle.points
	complex := ClipRegion{ bounded: true, points: clip_regular_polygon(40, 0) }
	window := rect(-200, -200, 400, 400)
	fallback := paint_transformed_clip(window, ContentTransform{}).intersect(complex)
	assert fallback.points.len == 40 && fallback.bounds() == complex.bounds()
}

fn test_changing_rotated_clip_snapshots_allocate_nothing() ! {
	frame := rect(10.25, 20.5, 120.75, 80.125)
	viewport := paint_transformed_clip(rect(0, 0, 240, 180), ContentTransform{})
	before := gc_allocation_snapshot()!
	mut total := 0.0
	for i in 0 .. 1000 {
		transform := VisualTransform{ rotation: f64(i) / 20, origin_x: 60, origin_y: 40 }.matrix(frame)!
		outer := viewport.intersect(paint_transformed_clip(frame, transform))
		inner := outer.intersect(paint_transformed_clip(rect(30, 30, 80, 60), transform))
		total += inner.bounds().width
		center := transform.point(60, 60)
		assert inner.contains(center.x, center.y)
	}
	delta := gc_allocation_snapshot()!.delta_since(before)
	assert total > 1000
	assert delta.allocated_bytes == 0
	assert delta.collections == 0
}
