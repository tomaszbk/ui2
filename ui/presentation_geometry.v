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
