module ui2

import math

// PaintVertex travels through the common convex clipper with interpolated UV
// and color. Coordinates are window-logical after affine projection. Consumers
// triangulate the returned convex polygon; device DPI belongs to submission.
pub struct PaintVertex {
pub:
	x f64
	y f64
	u f64
	v f64
	r f64 = 255
	g f64 = 255
	b f64 = 255
	a f64 = 255
}

// An unbounded region is the default. Bounded regions without finite convex
// area are empty, including public snapshots constructed with points directly.
// Regions are immutable snapshots, shared by paint, hit, hover and scroll.
pub struct ClipRegion {
pub:
	bounded bool
	points  []Point
}

// Scale the two axes independently, after subtraction. World-space shoelace
// products lose small translated regions and overflow/underflow for large/tiny
// coordinates. This basis preserves their orientation without an area cutoff.
fn clip_side(extent Rect, a Point, b Point, x f64, y f64) f64 {
	_, x_exp := math.frexp(extent.width)
	_, y_exp := math.frexp(extent.height)
	dx := math.ldexp(b.x - a.x, -x_exp)
	dy := math.ldexp(b.y - a.y, -y_exp)
	px := math.ldexp(x - a.x, -x_exp)
	py := math.ldexp(y - a.y, -y_exp)
	left := dx * py
	right := dy * px
	// Power-of-two scaling preserves representable coordinates. Recover the
	// product residuals too, so cancellation does not erase a positive sliver.
	return (left - right) + (clip_product_error(dx, py, left) - clip_product_error(dy, px, right))
}

fn clip_product_error(a f64, b f64, product f64) f64 {
	// Bounded polygon coordinates are small after scaling. Distant queries can
	// exceed the split range; their ordinary side/finite checks still fail closed.
	if !finite_number(product) || math.abs(a) > 1e299 || math.abs(b) > 1e299 { return 0 }
	a_split := 134217729 * a
	a_high := a_split - (a_split - a)
	a_low := a - a_high
	b_split := 134217729 * b
	b_high := b_split - (b_split - b)
	b_low := b - b_high
	return ((a_high * b_high - product) + a_high * b_low + a_low * b_high) + a_low * b_low
}

fn clip_roundoff(extent Rect, a Point, b Point, x f64, y f64) f64 {
	_, x_exp := math.frexp(extent.width)
	_, y_exp := math.frexp(extent.height)
	dx := math.ldexp(b.x - a.x, -x_exp)
	dy := math.ldexp(b.y - a.y, -y_exp)
	px := math.ldexp(x - a.x, -x_exp)
	py := math.ldexp(y - a.y, -y_exp)
	return 8 * 2.220446049250313e-16 * (math.abs(dx * py) + math.abs(dy * px)
		+ math.abs(dx) + math.abs(dy))
}

fn clip_area(points []Point) (Rect, int) {
	if points.len < 3 { return Rect{}, 0 }
	for p in points {
		if !finite_number(p.x) || !finite_number(p.y) { return Rect{}, 0 }
	}
	extent := point_bounds(points)
	if !finite_number(extent.width) || !finite_number(extent.height)
		|| extent.width <= 0 || extent.height <= 0 { return Rect{}, 0 }
	mut area := 0.0
	for i in 1 .. points.len - 1 {
		area += clip_side(extent, points[0], points[i], points[i + 1].x, points[i + 1].y)
	}
	if !finite_number(area) || area == 0 { return Rect{}, 0 }
	winding := if area > 0 { 1 } else { -1 }
	return extent, winding
}

// clip_axis_rect recognizes a finite four-vertex axis-aligned rectangle with
// positive area. Its basis and set operations need no general polygon work.
fn clip_axis_rect(points []Point) (Rect, int) {
	left, top, right, bottom, winding := clip_axis_edges(points)
	if winding == 0 { return Rect{}, 0 }
	return rect(left, top, right - left, bottom - top), winding
}

// clip_axis_edges returns exact edge coordinates; x + width can round.
fn clip_axis_edges(points []Point) (f64, f64, f64, f64, int) {
	if points.len != 4 { return 0, 0, 0, 0, 0 }
	a, b, c, d := points[0], points[1], points[2], points[3]
	mut winding := 0
	if a.y == b.y && b.x == c.x && c.y == d.y && d.x == a.x {
		winding = if (b.x > a.x) == (c.y > b.y) { 1 } else { -1 }
	} else if a.x == b.x && b.y == c.y && c.x == d.x && d.y == a.y {
		winding = if (b.y > a.y) != (c.x > b.x) { 1 } else { -1 }
	} else {
		return 0, 0, 0, 0, 0
	}
	left := math.min(a.x, c.x)
	top := math.min(a.y, c.y)
	right := math.max(a.x, c.x)
	bottom := math.max(a.y, c.y)
	if !finite_number(left) || !finite_number(top) || !finite_number(right) || !finite_number(bottom)
		|| !finite_number(right - left) || !finite_number(bottom - top) || right <= left || bottom <= top {
		return 0, 0, 0, 0, 0
	}
	return left, top, right, bottom, winding
}

fn clip_basis(points []Point) (Rect, int) {
	axis, axis_winding := clip_axis_rect(points)
	if axis_winding != 0 { return axis, axis_winding }
	extent, winding := clip_area(points)
	if winding == 0 { return Rect{}, 0 }
	// Public snapshots must bound a convex polygon, rather than an arbitrary set
	// of halfplanes (a concave/self-crossing sequence is not a clip region).
	for i, a in points {
		b := points[(i + 1) % points.len]
		for p in points {
			if clip_side(extent, a, b, p.x, p.y) * winding < -clip_roundoff(extent, a, b, p.x, p.y) { return Rect{}, 0 }
		}
	}
	return extent, winding
}

fn compare_clip_points(a &Point, b &Point) int {
	if a.x < b.x || (a.x == b.x && a.y < b.y) { return -1 }
	if a.x == b.x && a.y == b.y { return 0 }
	return 1
}

// Intersections of validated convex operands are convex by construction. Hull
// normalization removes redundant/reversed turns caused by intersection
// roundoff, rather than rejecting a positive-area result or using an epsilon
// that could erase a genuine small sliver. Paint attributes are never hulled.
fn convex_clip_result(vertices []Point) ClipRegion {
	extent, winding := clip_area(vertices)
	if winding == 0 { return ClipRegion{ bounded: true } }
	mut points := vertices.clone()
	points.sort_with_compare(compare_clip_points)
	mut lower := []Point{cap: points.len}
	mut upper := []Point{cap: points.len}
	for p in points {
		if lower.len > 0 && p == lower.last() { continue }
		for lower.len >= 2 && clip_side(extent, lower[lower.len - 2], lower.last(), p.x, p.y) <= 0 {
			lower.pop()
		}
		lower << p
	}
	for i := points.len - 1; i >= 0; i-- {
		p := points[i]
		if upper.len > 0 && p == upper.last() { continue }
		for upper.len >= 2 && clip_side(extent, upper[upper.len - 2], upper.last(), p.x, p.y) <= 0 {
			upper.pop()
		}
		upper << p
	}
	lower.pop()
	upper.pop()
	lower << upper
	_, result_winding := clip_area(lower)
	if result_winding == 0 { return ClipRegion{ bounded: true } }
	return ClipRegion{ bounded: true, points: lower }
}

fn (clip ClipRegion) normalized() ClipRegion {
	if !clip.bounded { return ClipRegion{} }
	_, axis_winding := clip_axis_rect(clip.points)
	if axis_winding > 0 { return clip }
	extent, winding := clip_basis(clip.points)
	if winding == 0 { return ClipRegion{ bounded: true } }
	// Valid canonical snapshots can be shared without allocating. Remove only
	// exact redundant vertices; tolerance must never erase a thin valid region.
	mut redundant := false
	for i, p in clip.points {
		previous := clip.points[(i + clip.points.len - 1) % clip.points.len]
		next := clip.points[(i + 1) % clip.points.len]
		if p == previous || (clip_side(extent, previous, next, p.x, p.y) == 0
			&& p.x >= math.min(previous.x, next.x) && p.x <= math.max(previous.x, next.x)
			&& p.y >= math.min(previous.y, next.y) && p.y <= math.max(previous.y, next.y)) {
			redundant = true
			break
		}
	}
	if !redundant && winding > 0 { return clip }
	return convex_clip_result(clip.points)
}

pub fn transformed_clip(frame Rect, t ContentTransform) ClipRegion {
	if !finite_number(frame.x) || !finite_number(frame.y) || !finite_number(frame.width) || !finite_number(frame.height) || frame.width <= 0 || frame.height <= 0 || !t.invertible() {
		return ClipRegion{ bounded: true }
	}
	return ClipRegion{ bounded: true, points: t.quad(frame) }.normalized()
}

pub fn (clip ClipRegion) contains(x f64, y f64) bool {
	if !finite_number(x) || !finite_number(y) { return false }
	if !clip.bounded { return true }
	extent, winding := clip_basis(clip.points)
	if winding == 0 { return false }
	// A nearly collinear valid polygon still bounds a finite area. Halfplane
	// roundoff alone must not admit arbitrarily far extensions of its edges.
	nx := (x - extent.x) / extent.width
	ny := (y - extent.y) / extent.height
	edge_error := 8 * 2.220446049250313e-16
	if !finite_number(nx) || !finite_number(ny) || nx < -edge_error || nx > 1 + edge_error
		|| ny < -edge_error || ny > 1 + edge_error { return false }
	for i, a in clip.points {
		b := clip.points[(i + 1) % clip.points.len]
		side := clip_side(extent, a, b, x, y) * winding
		// Relative floating-point roundoff only, never an absolute cross/area
		// threshold that lets tiny regions contain arbitrary distant points.
		tolerance := clip_roundoff(extent, a, b, x, y)
		if !finite_number(side) || !finite_number(tolerance) || side < -tolerance { return false }
	}
	return true
}

pub fn (clip ClipRegion) bounds() Rect {
	if !clip.bounded { return Rect{} }
	extent, _ := clip_basis(clip.points)
	return extent
}

fn lerp_vertex(a PaintVertex, b PaintVertex, t f64) PaintVertex {
	return PaintVertex{
		x: a.x + (b.x - a.x) * t
		y: a.y + (b.y - a.y) * t
		u: a.u + (b.u - a.u) * t
		v: a.v + (b.v - a.v) * t
		r: a.r + (b.r - a.r) * t
		g: a.g + (b.g - a.g) * t
		b: a.b + (b.b - a.b) * t
		a: a.a + (b.a - a.a) * t
	}
}

// clip_axis_halfplane keeps x >= bound (or y, or <= with keep_greater false)
// with the same nearer-endpoint interpolation as the general clipper.
fn clip_axis_halfplane(polygon []PaintVertex, horizontal bool, bound f64, keep_greater bool) []PaintVertex {
	if polygon.len == 0 { return []PaintVertex{} }
	mut output := []PaintVertex{cap: polygon.len + 1}
	mut previous := polygon[polygon.len - 1]
	mut previous_side := clip_axis_side(previous, horizontal, bound, keep_greater)
	if !finite_number(previous_side) { return []PaintVertex{} }
	for current in polygon {
		side := clip_axis_side(current, horizontal, bound, keep_greater)
		if !finite_number(side) { return []PaintVertex{} }
		if (side >= 0) != (previous_side >= 0) {
			magnitude := math.max(math.abs(previous_side), math.abs(side))
			previous_fraction := math.abs(previous_side) / magnitude
			current_fraction := math.abs(side) / magnitude
			if previous_fraction <= current_fraction {
				output << lerp_vertex(previous, current, previous_fraction / (previous_fraction + current_fraction))
			} else {
				output << lerp_vertex(current, previous, current_fraction / (previous_fraction + current_fraction))
			}
		}
		if side >= 0 { output << current }
		previous = current
		previous_side = side
	}
	return output
}

fn clip_axis_side(v PaintVertex, horizontal bool, bound f64, keep_greater bool) f64 {
	coordinate := if horizontal { v.x } else { v.y }
	return if keep_greater { coordinate - bound } else { bound - coordinate }
}

// paint_polygon_has_area matches clip_area for paint vertices, without copying them.
fn paint_polygon_has_area(vertices []PaintVertex) bool {
	if vertices.len < 3 { return false }
	mut left := vertices[0].x
	mut right := left
	mut top := vertices[0].y
	mut bottom := top
	for v in vertices {
		if !finite_number(v.x) || !finite_number(v.y) { return false }
		left = math.min(left, v.x)
		right = math.max(right, v.x)
		top = math.min(top, v.y)
		bottom = math.max(bottom, v.y)
	}
	extent := rect(left, top, right - left, bottom - top)
	if !finite_number(extent.width) || !finite_number(extent.height) || extent.width <= 0
		|| extent.height <= 0 { return false }
	origin := Point{vertices[0].x, vertices[0].y}
	mut area := 0.0
	for i in 1 .. vertices.len - 1 {
		area += clip_side(extent, origin, Point{vertices[i].x, vertices[i].y}, vertices[i + 1].x, vertices[i + 1].y)
	}
	return finite_number(area) && area != 0
}

pub fn (clip ClipRegion) clip_polygon(vertices []PaintVertex) []PaintVertex {
	if !clip.bounded { return vertices }
	extent, winding := clip_basis(clip.points)
	if winding == 0 || vertices.len < 3 { return []PaintVertex{} }
	for v in vertices {
		if !finite_number(v.x) || !finite_number(v.y) { return []PaintVertex{} }
	}
	left, top, right, bottom, axis_winding := clip_axis_edges(clip.points)
	if axis_winding != 0 {
		// Axis-aligned halfplanes have exact signed distances. Clip only against
		// the edges some vertex crosses; wholly inside paint is returned as is.
		mut outside_left, mut outside_right, mut outside_top, mut outside_bottom := false, false, false, false
		mut beyond_left, mut beyond_right, mut beyond_top, mut beyond_bottom := true, true, true, true
		for v in vertices {
			outside_left = outside_left || v.x < left
			outside_right = outside_right || v.x > right
			outside_top = outside_top || v.y < top
			outside_bottom = outside_bottom || v.y > bottom
			beyond_left = beyond_left && v.x < left
			beyond_right = beyond_right && v.x > right
			beyond_top = beyond_top && v.y < top
			beyond_bottom = beyond_bottom && v.y > bottom
		}
		if beyond_left || beyond_right || beyond_top || beyond_bottom { return []PaintVertex{} }
		if !(outside_left || outside_right || outside_top || outside_bottom) {
			return if paint_polygon_has_area(vertices) { vertices } else { []PaintVertex{} }
		}
		mut polygon := []PaintVertex{}
		mut clipped := false
		if outside_top {
			polygon = clip_axis_halfplane(vertices, false, top, true)
			clipped = true
		}
		if outside_right {
			polygon = clip_axis_halfplane(if clipped { polygon } else { vertices }, true, right, false)
			clipped = true
		}
		if outside_bottom {
			polygon = clip_axis_halfplane(if clipped { polygon } else { vertices }, false, bottom, false)
			clipped = true
		}
		if outside_left {
			polygon = clip_axis_halfplane(if clipped { polygon } else { vertices }, true, left, true)
		}
		return if paint_polygon_has_area(polygon) { polygon } else { []PaintVertex{} }
	}
	mut polygon := vertices.clone()
	for i, a in clip.points {
		if polygon.len == 0 { break }
		b := clip.points[(i + 1) % clip.points.len]
		mut output := []PaintVertex{cap: polygon.len + 1}
		mut previous := polygon[polygon.len - 1]
		mut previous_side := clip_side(extent, a, b, previous.x, previous.y) * winding
		if !finite_number(previous_side) { return []PaintVertex{} }
		for current in polygon {
			side := clip_side(extent, a, b, current.x, current.y) * winding
			if !finite_number(side) { return []PaintVertex{} }
			if (side >= 0) != (previous_side >= 0) {
				magnitude := math.max(math.abs(previous_side), math.abs(side))
				previous_fraction := math.abs(previous_side) / magnitude
				current_fraction := math.abs(side) / magnitude
				// Anchor at the nearer endpoint: 1 - a tiny fraction can round
				// to 1 and collapse a small but valid clipped polygon otherwise.
				if previous_fraction <= current_fraction {
					output << lerp_vertex(previous, current, previous_fraction / (previous_fraction + current_fraction))
				} else {
					output << lerp_vertex(current, previous, current_fraction / (previous_fraction + current_fraction))
				}
			}
			if side >= 0 { output << current }
			previous = current
			previous_side = side
		}
		polygon = unsafe { output }
	}
	// Tangency submits no triangles. Keep every attribute-bearing vertex of
	// positive-area paint polygons, including coincident UV/color seams.
	_, area_winding := clip_area(polygon.map(Point{it.x, it.y}))
	return if area_winding == 0 { []PaintVertex{} } else { polygon }
}

pub fn (clip ClipRegion) intersect(other ClipRegion) ClipRegion {
	left := clip.normalized()
	right := other.normalized()
	if !left.bounded { return right }
	if !right.bounded { return left }
	l0, t0, r0, b0, left_axis := clip_axis_edges(left.points)
	l1, t1, r1, b1, right_axis := clip_axis_edges(right.points)
	if left_axis != 0 && right_axis != 0 {
		x0, y0 := math.max(l0, l1), math.max(t0, t1)
		x1, y1 := math.min(r0, r1), math.min(b0, b1)
		if x1 <= x0 || y1 <= y0 { return ClipRegion{ bounded: true } }
		return ClipRegion{ bounded: true, points: [Point{x0, y0}, Point{x1, y0}, Point{x1, y1}, Point{x0, y1}] }
	}
	vertices := right.points.map(PaintVertex{ x: it.x, y: it.y })
	return convex_clip_result(left.clip_polygon(vertices).map(Point{it.x, it.y}))
}

// Inclusive conservative broad phase. Inverse/projection roundoff must not
// discard a painted boundary before the exact narrow phase can inspect it.
pub fn presentation_bounds_contains(frame Rect, x f64, y f64) bool {
	return finite_number(x) && finite_number(y) && finite_number(frame.x) && finite_number(frame.y)
		&& finite_number(frame.width) && finite_number(frame.height) && frame.width > 0 && frame.height > 0
		&& x >= frame.x - 1e-8 && x <= frame.x + frame.width + 1e-8
		&& y >= frame.y - 1e-8 && y <= frame.y + frame.height + 1e-8
}

// Shared exact narrow phase. Bounds may accelerate this test but never replace it.
pub fn transformed_contains(frame Rect, t ContentTransform, clip ClipRegion, x f64, y f64) bool {
	if !t.invertible() || !clip.contains(x, y) { return false }
	lx, ly := t.inverse(x, y)
	return presentation_bounds_contains(frame, lx, ly)
}
