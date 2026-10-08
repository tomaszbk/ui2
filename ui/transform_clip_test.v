module ui2

import math

$if !gcboehm ? { $compile_error('Exact clip fixtures require normal Boehm GC') }

fn clip_fixture_vertices(frame Rect) []PaintVertex {
	return [PaintVertex{ x: frame.x, y: frame.y },
		PaintVertex{ x: frame.x + frame.width, y: frame.y },
		PaintVertex{ x: frame.x + frame.width, y: frame.y + frame.height },
		PaintVertex{ x: frame.x, y: frame.y + frame.height }]
}

fn assert_empty_clip_contract(region ClipRegion) {
	descendant := transformed_clip(rect(250, 250, 40, 40), ContentTransform{})
	assert !region.contains(100, 200)
	assert !region.contains(1000, -1000)
	assert !region.contains(100, 100)
	assert region.bounds() == Rect{}
	assert region.clip_polygon(clip_fixture_vertices(rect(250, 250, 40, 40))).len == 0
	for intersection in [region.intersect(descendant), descendant.intersect(region),
		region.intersect(ClipRegion{}), ClipRegion{}.intersect(region)] {
		assert intersection.bounded && intersection.points.len == 0
		assert intersection.bounds() == Rect{}
		assert !intersection.contains(260, 260)
		assert intersection.clip_polygon(clip_fixture_vertices(rect(250, 250, 40, 40))).len == 0
	}
}

fn test_edge_and_corner_tangency_are_empty_for_hit_descendants_and_paint() {
	base := transformed_clip(rect(0, 0, 100, 100), ContentTransform{})
	for frame in [rect(100, 0, 100, 100), rect(100, 100, 100, 100)] {
		other := transformed_clip(frame, ContentTransform{})
		for region in [base.intersect(other), other.intersect(base)] {
			assert region.points.len == 0
			assert_empty_clip_contract(region)
		}
		assert base.clip_polygon(clip_fixture_vertices(frame)).len == 0
	}
}

fn test_public_degenerate_nonfinite_and_invalid_convex_regions_fail_closed() {
	for points in [
		[]Point{},
		[Point{100, 100}],
		[Point{100, 100}, Point{100, 100}, Point{100, 100}, Point{100, 100}],
		[Point{100, 0}, Point{100, 100}, Point{100, 100}, Point{100, 0}],
		[Point{0, 0}, Point{1, 1}, Point{2, 2}, Point{3, 3}],
		[Point{0, 0}, Point{math.nan(), 0}, Point{1, 1}],
		[Point{0, 0}, Point{math.inf(1), 0}, Point{1, 1}],
		[Point{-1e308, 0}, Point{1e308, 0}, Point{1e308, 1}, Point{-1e308, 1}],
		[Point{0, 0}, Point{10, 10}, Point{0, 10}, Point{10, 0}],
		[Point{0, 0}, Point{10, 0}, Point{5, 5}, Point{10, 10}, Point{0, 10}],
	] {
		assert_empty_clip_contract(ClipRegion{ bounded: true, points: points })
	}
	overflow := transformed_clip(rect(1e308, 0, 1e308, 1), ContentTransform{})
	assert_empty_clip_contract(overflow)
	projected_overflow := transformed_clip(rect(0, 0, 1e308, 1), ContentTransform{ xx: 2 })
	assert_empty_clip_contract(projected_overflow)
}

fn test_public_clockwise_duplicates_and_collinear_edges_normalize_without_losing_boundary() {
	// Clockwise, with a repeated closing vertex and an edge midpoint.
	region := ClipRegion{ bounded: true, points: [Point{0.125, 0.25}, Point{0.125, 10.75},
		Point{20.625, 10.75}, Point{20.625, 5.5}, Point{20.625, 0.25}, Point{0.125, 0.25}] }
	assert region.bounds() == rect(0.125, 0.25, 20.5, 10.5)
	for p in [Point{0.125, 0.25}, Point{20.625, 5.5}, Point{10.375, 10.75}] {
		assert region.contains(p.x, p.y)
	}
	assert !region.contains(21, 5.5)
	canonical := ClipRegion{}.intersect(region)
	assert canonical.points.len == 4
	assert canonical.bounds() == region.bounds()
	assert canonical.clip_polygon(clip_fixture_vertices(region.bounds())).len >= 4
	assert region.intersect(transformed_clip(rect(10.375, 0.25, 10.25, 10.5), ContentTransform{})).bounds()
		== rect(10.375, 0.25, 10.25, 10.5)
}

fn test_tiny_skinny_translated_and_cancellation_sensitive_regions_keep_positive_area() {
	for frame in [rect(0, 0, 1e-200, 1e-200), rect(0, 0, 1e200, 1e-200),
		rect(1e12, 1e12, 0.25, 0.5), rect(1, 1, math.ldexp(1, -52), math.ldexp(1, -52)),
		rect(0.125, 0.375, 1e-10, 2e-10)] {
		region := transformed_clip(frame, ContentTransform{})
		assert region.points.len == 4
		assert region.bounds().width > 0 && region.bounds().height > 0
		assert region.contains(frame.x + frame.width / 2, frame.y + frame.height / 2)
		assert region.contains(frame.x, frame.y)
		assert !region.contains(frame.x + 2 * frame.width, frame.y + 2 * frame.height)
		assert region.intersect(region).points.len == 4
		assert region.clip_polygon(clip_fixture_vertices(frame)).len == 4
	}
	// Products individually round to the same number, but this f64 triangle
	// has positive area 2^-104. Scaling and product residuals preserve it.
	epsilon := math.ldexp(1, -52)
	sliver := ClipRegion{ bounded: true, points: [Point{0, 0}, Point{1, 1 + epsilon}, Point{1 - epsilon, 1}] }
	assert sliver.bounds().width == 1
	assert sliver.intersect(ClipRegion{}).points.len == 3
	assert sliver.intersect(sliver).points.len == 3
	assert sliver.contains(0, 0)
	assert !sliver.contains(2, 2)
	assert !sliver.contains(1000, 1000)
	assert sliver.clip_polygon(sliver.points.map(PaintVertex{ x: it.x, y: it.y })).len == 3
}

fn test_fractional_shared_transformed_edge_keeps_selection_and_descendant_clip() {
	// Independently projected common geometry: R28 * scale(1.1,.8), fit .8,
	// then R-8. The selection's top edge shares the viewport's transformed edge.
	// Rounded intersections may introduce a redundant near-collinear corner.
	clip := ClipRegion{ bounded: true, points: [
		Point{82.10784033180889, 53.519846543696175},
		Point{230.95515146429682, 107.69583724648213},
		Point{219.1349353109617, 140.1716142208431},
		Point{70.28762417847376, 85.99562351805716},
	] }
	selection := ClipRegion{ bounded: true, points: [
		Point{150.9564384423796, 78.57868692690025},
		Point{167.7459100743364, 84.68955484998929},
		Point{162.4084119889148, 99.3542103160674},
		Point{145.618940356958, 93.24334239297832},
	] }
	paint := clip.clip_polygon(selection.points.map(PaintVertex{ x: it.x, y: it.y, r: 184, g: 215, b: 255 }))
	assert paint.len >= 4
	for vertex in paint {
		assert clip.contains(vertex.x, vertex.y)
		assert vertex.r == 184 && vertex.g == 215 && vertex.b == 255
	}
	visible := clip.intersect(selection)
	assert visible.bounds().width > 20 && visible.bounds().height > 19
	assert visible.contains(156, 89)
	descendant := visible.intersect(transformed_clip(rect(155, 87, 2, 2), ContentTransform{}))
	assert descendant.bounds() == rect(155, 87, 2, 2)
	assert descendant.contains(156, 88)
}

fn test_fractional_positive_clip_preserves_boundary_uv_and_all_color_channels() {
	region := transformed_clip(rect(0.125, 0.25, 0.5, 0.5), ContentTransform{})
	source := [PaintVertex{ x: 0, y: 0, u: 0, v: 0, r: 0, g: 10, b: 20, a: 30 },
		PaintVertex{ x: 1, y: 0, u: 1, v: 0, r: 100, g: 110, b: 120, a: 130 },
		PaintVertex{ x: 1, y: 1, u: 1, v: 1, r: 100, g: 110, b: 120, a: 130 },
		PaintVertex{ x: 0, y: 1, u: 0, v: 1, r: 0, g: 10, b: 20, a: 30 }]
	result := region.clip_polygon(source)
	assert result.len == 4
	for vertex in result {
		assert region.contains(vertex.x, vertex.y)
		assert math.abs(vertex.x - 0.125) < 1e-14 || math.abs(vertex.x - 0.625) < 1e-14
		assert math.abs(vertex.y - 0.25) < 1e-14 || math.abs(vertex.y - 0.75) < 1e-14
		assert math.abs(vertex.u - vertex.x) < 1e-14
		assert math.abs(vertex.v - vertex.y) < 1e-14
		assert math.abs(vertex.r - 100 * vertex.x) < 1e-12
		assert math.abs(vertex.g - (10 + 100 * vertex.x)) < 1e-12
		assert math.abs(vertex.b - (20 + 100 * vertex.x)) < 1e-12
		assert math.abs(vertex.a - (30 + 100 * vertex.x)) < 1e-12
	}
}

fn test_small_clip_of_larger_geometry_keeps_area_and_interpolated_attributes() {
	region := transformed_clip(rect(0, 0, 1e-200, 1e-200), ContentTransform{})
	source := [PaintVertex{ x: 0, y: 0, u: 0, v: 0, r: 0 },
		PaintVertex{ x: 1, y: 0, u: 1, v: 0, r: 100 },
		PaintVertex{ x: 1, y: 1, u: 1, v: 1, r: 100 },
		PaintVertex{ x: 0, y: 1, u: 0, v: 1, r: 0 }]
	result := region.clip_polygon(source)
	assert result.len == 4
	assert result.any(it.x > 0) && result.any(it.y > 0)
	for corner in [Point{0, 0}, Point{1e-200, 0}, Point{1e-200, 1e-200}, Point{0, 1e-200}] {
		assert result.any(math.abs((it.x - corner.x) / 1e-200) < 1e-14
			&& math.abs((it.y - corner.y) / 1e-200) < 1e-14)
	}
	for vertex in result {
		assert region.contains(vertex.x, vertex.y)
		assert math.abs(vertex.u - vertex.x) < 1e-214
		assert math.abs(vertex.v - vertex.y) < 1e-214
		assert math.abs(vertex.r - vertex.x * 100) < 1e-212
	}
	intersection := region.intersect(transformed_clip(rect(0, 0, 1, 1), ContentTransform{})).bounds()
	assert intersection.x == 0 && intersection.y == 0
	assert math.abs(intersection.width / 1e-200 - 1) < 1e-14
	assert math.abs(intersection.height / 1e-200 - 1) < 1e-14
}
