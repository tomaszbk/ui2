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

// An unbounded region is the default. bounded + no points is an empty region.
// Regions are immutable snapshots, shared by paint, hit, hover and scroll.
pub struct ClipRegion {
pub:
	bounded bool
	points  []Point
}

fn cross_edge(a Point, b Point, x f64, y f64) f64 {
	return (b.x - a.x) * (y - a.y) - (b.y - a.y) * (x - a.x)
}

fn polygon_winding(points []Point) f64 {
	mut area := 0.0
	for i, p in points {
		q := points[(i + 1) % points.len]
		area += p.x * q.y - q.x * p.y
	}
	return area
}

pub fn transformed_clip(frame Rect, t ContentTransform) ClipRegion {
	if !finite_number(frame.x) || !finite_number(frame.y) || !finite_number(frame.width) || !finite_number(frame.height) || frame.width <= 0 || frame.height <= 0 || !t.invertible() {
		return ClipRegion{ bounded: true }
	}
	mut points := t.quad(frame)
	if polygon_winding(points) < 0 { points.reverse_in_place() }
	return ClipRegion{ bounded: true, points: points }
}

pub fn (clip ClipRegion) contains(x f64, y f64) bool {
	if !finite_number(x) || !finite_number(y) { return false }
	if !clip.bounded { return true }
	if clip.points.len < 3 { return false }
	for i, a in clip.points {
		if cross_edge(a, clip.points[(i + 1) % clip.points.len], x, y) < -1e-8 { return false }
	}
	return true
}

pub fn (clip ClipRegion) bounds() Rect { return point_bounds(clip.points) }

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

pub fn (clip ClipRegion) clip_polygon(vertices []PaintVertex) []PaintVertex {
	if !clip.bounded { return vertices }
	if clip.points.len < 3 || vertices.len < 3 { return []PaintVertex{} }
	mut polygon := vertices.clone()
	for i, a in clip.points {
		if polygon.len == 0 { break }
		b := clip.points[(i + 1) % clip.points.len]
		mut output := []PaintVertex{cap: polygon.len + 1}
		mut previous := polygon[polygon.len - 1]
		mut previous_side := cross_edge(a, b, previous.x, previous.y)
		for current in polygon {
			side := cross_edge(a, b, current.x, current.y)
			if (side >= 0) != (previous_side >= 0) {
				output << lerp_vertex(previous, current, math.clamp(previous_side / (previous_side - side), 0.0, 1.0))
			}
			if side >= 0 { output << current }
			previous = current
			previous_side = side
		}
		polygon = unsafe { output }
	}
	return polygon
}

pub fn (clip ClipRegion) intersect(other ClipRegion) ClipRegion {
	if !clip.bounded { return other }
	if !other.bounded { return clip }
	vertices := other.points.map(PaintVertex{ x: it.x, y: it.y })
	return ClipRegion{ bounded: true, points: clip.clip_polygon(vertices).map(Point{it.x, it.y}) }
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
