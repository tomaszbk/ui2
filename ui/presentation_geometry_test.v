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

fn test_logical_typography_and_layout_preserve_fractional_sizes() {
	style := TextStyle{ size: 18.25 }
	assert style.size == 18.25
	assert text_style_line_height(style) == 22.8125
	frame := rect(0.125, 0.375, 100.25, 50.75)
	el := element_from_vml('Label { text: "fractional" font_size: 18.25 }', frame)!
	assert el.text_style.size == 18.25
	assert el.frame == frame
	for scale in [1.0, 1.25, 1.5, 2.0] {
		presented := presentation_rect(frame, scale)
		assert math.abs(presented.x * scale - math.round(presented.x * scale)) < 0.00001
		assert math.abs(presented.y * scale - math.round(presented.y * scale)) < 0.00001
		assert el.frame == frame
		assert el.text_style.size == 18.25
	}
}

fn test_logical_text_measurement_has_the_same_em_height_at_every_dpi() {
	style := TextStyle{ size: 18.25, lines: 1 }
	$if ( linux || ( ( macos || windows ) && ui2_custom_rendering ?) ) && !ui2_headless ? {
		for dpi in [f32(1), 1.25, 1.5, 2] {
			mut engine := new_text_engine(dpi)!
			shaped := engine.shape('fractional', style, -1, 1, false)!
			assert math.abs(shaped.size.height - 22.8125) < 0.01
			engine.free()
		}
	} $else {
		// CPU Fontstash receives the fractional metric size, without pixel rounding.
		measured := layout_measure_cpu_text('fractional', style, -1)!
		assert math.abs(measured.height - 22.8125) < 0.01
	}
}

fn test_authored_units_property_is_rejected_for_every_profile_and_node() {
	for source in [
		'Label { units: "legacy" text: "bad" }',
		'Screen { units: "logical" Label { text: "bad" } }',
		'Label { text: "bad" units: "pixels" }',
		'Label { Run { units: "logical" text: "bad" } }',
		'Label { units: "" text: "bad" }',
	] {
		if _ := parse_vml(source) {
			assert false, source
		} else {
			assert err.msg().contains('units is not a VML property')
		}
	}
}

fn test_programmatic_vnode_units_property_is_rejected() {
	node := &VNode{
		tag:      'Label'
		children: [&VNode{
			tag:   'Run'
			props: {
				'units': 'logical'
				'text':  'bad'
			}
		}]
	}
	if _ := element_from_vnode(node, rect(0, 0, 100, 100)) {
		assert false
	} else {
		assert err.msg().contains('units is not a VML property')
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
