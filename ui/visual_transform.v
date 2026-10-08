module ui2

import math

// VisualTransform presents an element and its subtree without changing layout.
// Positive rotation is clockwise in y-down logical coordinates. Origin is in
// local logical units from the element's top-left. Order: translate * pivot *
// rotate * scale * -pivot. Negative scales reflect; zero/singular values reject.
pub struct VisualTransform {
pub:
	translate_x f64
	translate_y f64
	scale_x     f64 = 1
	scale_y     f64 = 1
	rotation    f64
	origin_x    f64
	origin_y    f64
}

pub fn (t VisualTransform) matrix(frame Rect) !ContentTransform {
	for value in [t.translate_x, t.translate_y, t.scale_x, t.scale_y, t.rotation, t.origin_x,
		t.origin_y, frame.x, frame.y] {
		if !finite_number(value) { return error('visual transform values must be finite') }
	}
	angle := t.rotation * math.pi / 180
	c := math.cos(angle)
	s := math.sin(angle)
	px := frame.x + t.origin_x
	py := frame.y + t.origin_y
	result := ContentTransform{
		xx: c * t.scale_x
		xy: -s * t.scale_y
		yx: s * t.scale_x
		yy: c * t.scale_y
		x:  px + t.translate_x - c * t.scale_x * px + s * t.scale_y * py
		y:  py + t.translate_y - s * t.scale_x * px - c * t.scale_y * py
	}
	if !result.invertible() { return error('visual transform must be finite and nonsingular') }
	result.inverted()!
	return result
}

pub fn with_transform(el Element, transform VisualTransform) Element {
	return Element{
		...el
		translate_x: transform.translate_x
		translate_y: transform.translate_y
		scale_x:     transform.scale_x
		scale_y:     transform.scale_y
		rotation:    transform.rotation
		origin_x:    transform.origin_x
		origin_y:    transform.origin_y
	}
}

// PanZoom is a camera in its parent's logical space. It has no event loop or
// lifecycle: use existing typed pointer callbacks/capture and set_visual_transform.
pub struct PanZoom {
pub:
	x    f64
	y    f64
	zoom f64 = 1
}

pub fn (p PanZoom) transform() VisualTransform {
	return VisualTransform{ translate_x: p.x, translate_y: p.y, scale_x: p.zoom, scale_y: p.zoom }
}

// dx/dy are parent-logical vectors (use outer.inverse_vector for window input).
pub fn (p PanZoom) pan(dx f64, dy f64) !PanZoom {
	result := PanZoom{ x: p.x + dx, y: p.y + dy, zoom: p.zoom }
	result.transform().matrix(Rect{})!
	if p.zoom <= 0 { return error('pan/zoom requires positive zoom') }
	return result
}

// The parent-logical anchor remains fixed. Caller chooses its zoom bounds.
pub fn (p PanZoom) zoom_at(zoom f64, anchor Point) !PanZoom {
	if p.zoom <= 0 || !finite_number(p.zoom) || zoom <= 0 || !finite_number(zoom) || !finite_number(anchor.x) || !finite_number(anchor.y) {
		return error('pan/zoom requires finite coordinates and positive zoom')
	}
	ratio := zoom / p.zoom
	result := PanZoom{ x: anchor.x - (anchor.x - p.x) * ratio, y: anchor.y - (anchor.y - p.y) * ratio, zoom: zoom }
	result.transform().matrix(Rect{})!
	return result
}

// Canonical Element fields are also the thin VML lowering surface.
pub fn (el Element) visual_transform() VisualTransform {
	return VisualTransform{
		translate_x: el.translate_x
		translate_y: el.translate_y
		scale_x:     el.scale_x
		scale_y:     el.scale_y
		rotation:    el.rotation
		origin_x:    el.origin_x
		origin_y:    el.origin_y
	}
}
