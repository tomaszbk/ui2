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

// ContentTransform maps fixed composition coordinates into window coordinates.
// Device scale is deliberately absent; DPI is applied only at presentation.
pub struct ContentTransform {
pub:
	scale f64 = 1
	x     f64
	y     f64
}

pub fn contain_content(viewport Rect, width f64, height f64) !ContentTransform {
	if math.is_nan(viewport.x) || math.is_nan(viewport.y) || math.is_inf(viewport.x, 0) || math.is_inf(viewport.y, 0)
		|| width <= 0 || height <= 0 || viewport.width <= 0 || viewport.height <= 0
		|| math.is_nan(width) || math.is_nan(height) || math.is_inf(width, 0) || math.is_inf(height, 0)
		|| math.is_nan(viewport.width) || math.is_nan(viewport.height) || math.is_inf(viewport.width, 0) || math.is_inf(viewport.height, 0) {
		return error('fixed content and viewport dimensions must be finite and positive')
	}
	scale := math.min(viewport.width / width, viewport.height / height)
	return ContentTransform{ scale: scale, x: viewport.x + (viewport.width - width * scale) / 2, y: viewport.y + (viewport.height - height * scale) / 2 }
}

pub fn (outer ContentTransform) compose(inner ContentTransform) ContentTransform {
	return ContentTransform{ scale: outer.scale * inner.scale, x: outer.x + inner.x * outer.scale, y: outer.y + inner.y * outer.scale }
}

pub fn (transform ContentTransform) project(area Rect) Rect {
	return rect(transform.x + area.x * transform.scale, transform.y + area.y * transform.scale, area.width * transform.scale, area.height * transform.scale)
}

pub fn (transform ContentTransform) inverse(x f64, y f64) (f64, f64) {
	return (x - transform.x) / transform.scale, (y - transform.y) / transform.scale
}

pub fn (transform ContentTransform) inverse_rect(area Rect) Rect {
	x, y := transform.inverse(area.x, area.y)
	return rect(x, y, area.width / transform.scale, area.height / transform.scale)
}

// Snap an outer paint frame to the same physical edges as filled rectangles,
// then return to composition coordinates for tessellation. Layout is unchanged.
fn (transform ContentTransform) rounded_local_rect(area Rect, device_scale f64) Rect {
	return transform.inverse_rect(presentation_rect(transform.project(area), device_scale))
}
