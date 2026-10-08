module ui2

import math

// Rounded device edges derive widths from shared boundaries, never independent sizes.
// Return window-logical coordinates; logical layout stays fractional and untouched.
pub fn presentation_rect(area Rect, device_scale f64) Rect {
	scale := if device_scale > 0 && !math.is_inf(device_scale, 0) && !math.is_nan(device_scale) {
		device_scale
	} else {
		1.0
	}
	left := math.round(area.x * scale)
	top := math.round(area.y * scale)
	right := math.round((area.x + area.width) * scale)
	bottom := math.round((area.y + area.height) * scale)
	return rect(left / scale, top / scale, (right - left) / scale, (bottom - top) / scale)
}

// ContentTransform maps local logical points to window logical points. Device DPI
// is applied by the renderer once, after this matrix. compose(inner) = self * inner.
pub struct ContentTransform {
pub:
	xx f64 = 1
	xy f64
	yx f64
	yy f64 = 1
	x  f64
	y  f64
}

pub struct Point {
pub:
	x f64
	y f64
}

fn finite_number(x f64) bool { return !math.is_nan(x) && !math.is_inf(x, 0) }

pub fn (t ContentTransform) invertible() bool {
	return finite_number(t.xx) && finite_number(t.xy) && finite_number(t.yx)
		&& finite_number(t.yy) && finite_number(t.x) && finite_number(t.y)
		&& finite_number(t.xx * t.yy - t.xy * t.yx) && math.abs(t.xx * t.yy - t.xy * t.yx) > 1e-12
}

pub fn (outer ContentTransform) compose(inner ContentTransform) ContentTransform {
	return ContentTransform{
		xx: outer.xx * inner.xx + outer.xy * inner.yx
		xy: outer.xx * inner.xy + outer.xy * inner.yy
		yx: outer.yx * inner.xx + outer.yy * inner.yx
		yy: outer.yx * inner.xy + outer.yy * inner.yy
		x:  outer.x + outer.xx * inner.x + outer.xy * inner.y
		y:  outer.y + outer.yx * inner.x + outer.yy * inner.y
	}
}

pub fn (t ContentTransform) point(x f64, y f64) Point {
	return Point{t.xx * x + t.xy * y + t.x, t.yx * x + t.yy * y + t.y}
}

pub fn (t ContentTransform) vector(x f64, y f64) Point {
	return Point{t.xx * x + t.xy * y, t.yx * x + t.yy * y}
}

pub fn (t ContentTransform) inverted() !ContentTransform {
	if !t.invertible() { return error('visual transform must be finite and nonsingular') }
	d := t.xx * t.yy - t.xy * t.yx
	result := ContentTransform{
		xx: t.yy / d
		xy: -t.xy / d
		yx: -t.yx / d
		yy: t.xx / d
		x:  (t.xy * t.y - t.yy * t.x) / d
		y:  (t.yx * t.x - t.xx * t.y) / d
	}
	for value in [result.xx, result.xy, result.yx, result.yy, result.x, result.y] {
		if !finite_number(value) { return error('visual transform inverse must be finite') }
	}
	return result
}

// Invalid matrices are noninteractive; authored/runtime setters reject them.
pub fn (t ContentTransform) inverse(x f64, y f64) (f64, f64) {
	inv := t.inverted() or { return math.nan(), math.nan() }
	// Subtract translation before the inverse basis to avoid cancellation at
	// large offsets and preserve exact logical coordinates for uniform fits.
	p := inv.vector(x - t.x, y - t.y)
	return p.x, p.y
}

pub fn (t ContentTransform) inverse_vector(x f64, y f64) Point {
	inv := t.inverted() or { return Point{math.nan(), math.nan()} }
	return inv.vector(x, y)
}

pub fn (t ContentTransform) quad(area Rect) []Point {
	return [t.point(area.x, area.y), t.point(area.x + area.width, area.y),
		t.point(area.x + area.width, area.y + area.height), t.point(area.x, area.y + area.height)]
}

fn point_bounds(points []Point) Rect {
	if points.len == 0 { return Rect{} }
	mut left := points[0].x
	mut right := left
	mut top := points[0].y
	mut bottom := top
	for p in points {
		left = math.min(left, p.x)
		right = math.max(right, p.x)
		top = math.min(top, p.y)
		bottom = math.max(bottom, p.y)
	}
	return rect(left, top, right - left, bottom - top)
}

// project/inverse_rect return bounding boxes, for culling/semantics/IME only.
pub fn (t ContentTransform) project(area Rect) Rect { return point_bounds(t.quad(area)) }

pub fn (t ContentTransform) inverse_rect(area Rect) Rect {
	inv := t.inverted() or { return Rect{} }
	return inv.project(area)
}

// Largest singular value: conservative footprint for overlay font sizing/assets.
pub fn (t ContentTransform) footprint_scale() f64 {
	a := t.xx * t.xx + t.yx * t.yx
	b := t.xy * t.xy + t.yy * t.yy
	c := t.xx * t.xy + t.yx * t.yy
	return math.sqrt((a + b + math.sqrt((a - b) * (a - b) + 4 * c * c)) / 2)
}

pub fn contain_content(viewport Rect, width f64, height f64) !ContentTransform {
	if !finite_number(viewport.x) || !finite_number(viewport.y) || !finite_number(width)
		|| !finite_number(height) || !finite_number(viewport.width) || !finite_number(viewport.height)
		|| width <= 0 || height <= 0 || viewport.width <= 0 || viewport.height <= 0 {
		return error('fixed content and viewport dimensions must be finite and positive')
	}
	scale := math.min(viewport.width / width, viewport.height / height)
	return ContentTransform{ xx: scale, yy: scale, x: viewport.x + (viewport.width - width * scale) / 2, y: viewport.y + (viewport.height - height * scale) / 2 }
}

fn (t ContentTransform) rounded_local_rect(area Rect, device_scale f64) Rect {
	// Snapping a rotated AABB back into local space distorts geometry. Preserve
	// affine vertices; the rasterizer presents them at device DPI without feedback.
	if t.xy != 0 || t.yx != 0 || t.xx <= 0 || t.yy <= 0 { return area }
	return t.inverse_rect(presentation_rect(t.project(area), device_scale))
}
