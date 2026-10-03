module ui2

import math

fn test_shared_edges_fractional_partition() {
	for scale in [1.0, 1.25, 1.5, 2.0] {
		mut previous := presentation_rect(rect(0.2, 0.3, 100.0 / 3, 40), scale)
		first := previous
		for index in 1 .. 3 {
			current := presentation_rect(rect(0.2 + f64(index) * 100.0 / 3, 0.3, 100.0 / 3, 40), scale)
			assert math.abs(previous.x + previous.width - current.x) < 0.00001
			previous = current
		}
		total := presentation_rect(rect(0.2, 0.3, 100, 40), scale)
		assert math.abs(previous.x + previous.width - first.x - total.width) < 0.00001
	}
}

fn test_logical_typography_and_legacy_are_explicit() {
	assert font_style_em_pixels(TextStyle{ size: 18, units: .logical }) == 18
	assert font_style_line_height(TextStyle{ size: 18, units: .logical }) == 22.5
	assert font_style_em_pixels(TextStyle{ size: 18 }) == font_em_pixels(18)
	assert native_font_points(TextStyle{ size: 18, units: .logical }) * font_pixels_per_point() == 18
}

fn test_vml_units_inherit_with_explicit_legacy_override() {
	el := element_from_vml('Screen { units: "logical" Label { text: "a" font_size: 18 } View { units: "legacy" Label { text: "b" } } }', rect(0, 0, 400, 300))!
	assert el.children[0].text_style.units == .logical
	assert el.children[1].children[0].text_style.units == .legacy
}

fn test_unknown_units_are_rejected() {
	if _ := element_from_vml('Label { units: "pixels" text: "bad" }', rect(0, 0, 100, 100)) {
		assert false
	}
}

fn test_border_tessellation_frame_matches_fractional_fill_presentation() {
	transform := ContentTransform{ scale: 0.5, y: 60 }
	original := rect(72.5, 64.5, 368.5, 200.5)
	// At DPI2 the fill begins on pixel (73,185), ending on (441,385).
	local := transform.rounded_local_rect(original, 2)
	assert local == rect(73, 65, 368, 200)
	assert transform.project(local) == rect(36.5, 92.5, 184, 100)
	assert original == rect(72.5, 64.5, 368.5, 200.5)
	for dpi in [1.0, 1.25, 1.5, 2.0] {
		snapped := transform.rounded_local_rect(original, dpi)
		projected := transform.project(snapped)
		assert math.abs(projected.x * dpi - math.round(projected.x * dpi)) < 0.00001
		assert math.abs((projected.x + projected.width) * dpi - math.round((projected.x + projected.width) * dpi)) < 0.00001
	}
}
