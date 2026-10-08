module ui2

$if ( linux || ( ( macos || windows ) && ui2_custom_rendering ?) ) && !ui2_headless ? {
	import math
}

fn test_typography_defaults_and_validation() {
	assert text_style_weight(TextStyle{}) == 400
	assert text_style_weight(TextStyle{ bold: true }) == 700
	assert text_style_weight(TextStyle{ bold: true, weight: 400 }) == 400
	assert text_style_line_height(TextStyle{ size: 20 }) == font_line_height(20)
	assert text_style_line_height(TextStyle{ size: 20, line_height: 27 }) == 27
	assert text_style_line_height(TextStyle{ size: 20, line_height_factor: 1.5 }) == 20 * 1.5
	for style in [TextStyle{ weight: 99 }, TextStyle{ weight: 901 }, TextStyle{ line_height: -1 },
		TextStyle{ line_height: 10, line_height_factor: 1 }] {
		if _ := layout_validate_text_measurement(style, -1) {
			assert false
		}
	}
}

fn test_logical_typography_factors_and_runs_keep_fractional_sizes() {
	assert text_style_line_height(TextStyle{ size: 18.25, line_height_factor: 1.5 }) == 27.375
	el := element_from_vml('Screen { Label { font_size: 18.25 Run { text: "a" } Run { text: "b" font_size: 12.5 } } }', rect(0, 0, 200, 100))!
	assert el.children[0].text_runs[0].style.size == 18.25
	assert el.children[0].text_runs[1].style.size == 12.5
}

fn test_vml_runs_inherit_and_explicit_false_overrides() {
	node := parse_vml('Label { font_size: 24 color: #123456 weight: 800 bold: true lines: 3 Run { text: "first " } Run { text: "small" font_size: 12 weight: 400 bold: false baseline_offset: 3 } }')!
	el := node_to_element(node, rect(0, 0, 200, 100))!
	assert el.text == 'first small'
	assert el.text_runs.len == 2
	assert el.text_runs[0].style.size == 24
	assert el.text_runs[0].style.color == 0x123456
	assert el.text_runs[0].style.weight == 800
	assert el.text_runs[1].style.size == 12
	assert !el.text_runs[1].style.bold
	assert el.text_runs[1].style.weight == 400
	assert el.text_runs[1].style.baseline_offset == 3
	sliced := text_runs_slice(el.text_runs, 3, 8, true)
	assert text_runs_content(sliced) == 'st sm…'
	assert sliced.last().style.size == 12
}

fn test_vglyph_rich_metrics_tracking_line_grid_and_scale() {
	$if ( linux || ( ( macos || windows ) && ui2_custom_rendering ?) ) && !ui2_headless ? {
		mut engine := new_text_engine(1)!
		defer { engine.free() }
		base := TextStyle{ font_family: 'Inter', size: 24, lines: 5, line_height: 36 }
		plain := engine.shape('MMMMMMMM', base, -1, 1, false)!
		spaced := engine.shape('MMMMMMMM', TextStyle{ ...base, letter_spacing: 2 }, -1, 1, false)!
		assert spaced.size.width > plain.size.width + 10
		heavy := engine.shape('MMMMMMMM', TextStyle{ ...base, weight: 900 }, -1, 1, false)!
		assert heavy.size.width > plain.size.width + 1
		runs := [TextRun{ text: 'Large ', style: TextStyle{ ...base, weight: 900 } },
			TextRun{ text: 'small text wraps here', style: TextStyle{ ...base, size: 12, baseline_offset: 3 } }]
		full := engine.shape_runs(runs, base, 100, 5, true)!
		assert full.lines.len >= 2
		assert math.abs(full.size.height - f64(full.lines.len) * 36) < 0.05
		measured := layout_measure_vglyph_runs(runs, base, 100)!
		assert math.abs(measured.height - full.size.height) < 0.02
		assert math.abs(measured.width - math.min(full.size.width, 100)) < 0.02
		label_size := measure_layout_element(rich_label('rich', runs, Rect{}, base), LayoutConstraints{ max_width: 100 }, measure_layout_text)!
		assert math.abs(label_size.height - measured.height) < 0.02
		mut scaled := new_text_engine(2)!
		defer { scaled.free() }
		dpi := scaled.shape_runs(runs, base, 100, 5, true)!
		assert dpi.lines.len == full.lines.len
		assert math.abs(dpi.size.height - full.size.height) < 0.02
		unbounded_runs := [TextRun{ text: 'first\nsecond\nthird', style: base }]
		one_line := layout_measure_vglyph_runs(unbounded_runs, TextStyle{ ...base, lines: 1 }, -1)!
		assert math.abs(one_line.height - 36) < 0.02
		// Multiple paragraphs exhaust one label-wide budget, retaining tail style.
		tail_runs := [TextRun{ text: 'first\n', style: base },
			TextRun{ text: 'second\nthird', style: TextStyle{ ...base, size: 12, weight: 900, color: 0xff0000 } }]
		truncated := engine.shape_runs(tail_runs, base, 100, 2, true)!
		assert truncated.truncated
		assert truncated.lines.len == 2
		assert truncated.layout.items.last().color.r == 255
		digits := engine.shape('1111', TextStyle{ ...base, tabular_figures: true }, -1, 1, false)!
		wide_digits := engine.shape('8888', TextStyle{ ...base, tabular_figures: true }, -1, 1, false)!
		assert math.abs(digits.size.width - wide_digits.size.width) < 0.02
	}
}

struct TypographyBindingApp {
pub mut:
	content  string
	run_size f64
}

fn test_runtime_run_binding_rebuilds_intrinsic_measurement() {
	source := 'Screen { Flex { orientation: vertical width: 120 height: 300 Label { width: 120 lines: 10 font_size: 16 Run { text: app.content font_size: app.run_size } } } }'
	first := element_from_vml_model(source, TypographyBindingApp{ content: 'one', run_size: 12 }, rect(0, 0, 120, 300))!
	second := element_from_vml_model(source, TypographyBindingApp{ content: 'one two three four five six seven', run_size: 24 }, rect(0, 0, 120, 300))!
	a := first.children[0].children[0]
	b := second.children[0].children[0]
	assert a.text == 'one'
	assert b.text == 'one two three four five six seven'
	assert a.text_runs[0].style.size == 12
	assert b.text_runs[0].style.size == 24
	$if ( linux || ( ( macos || windows ) && ui2_custom_rendering ?) ) && !ui2_headless ? {
		assert b.frame.height > a.frame.height * 2
	}
	// UTF-8 slicing preserves a multi-byte tail and its style.
	sliced := text_runs_slice([
		TextRun{ text: 'café ', style: TextStyle{ weight: 700 } },
		TextRun{ text: '日本語', style: TextStyle{ size: 12 } },
	], 3, 9, true)
	assert text_runs_content(sliced) == 'é 日…'
	assert sliced.last().style.size == 12
}

fn test_floating_overlay_scales_complete_typography_once() {
	style := TextStyle{ size: 24, letter_spacing: 2, line_height: 36, baseline_offset: 4, weight: 800 }
	output := scaled_overlay_text_style(style, 0.5)
	assert output.size == 12 && output.line_height == 18
	assert output.letter_spacing == 1 && output.baseline_offset == 2
	assert output.weight == 800
	assert text_style_line_height(scaled_overlay_text_style(TextStyle{ size: 24, line_height_factor: 1.5 }, 0.5)) == 18
}

fn test_mixed_size_runs_keep_absolute_parent_line_grid() {
	$if ( linux || ( ( macos || windows ) && ui2_custom_rendering ?) ) && !ui2_headless ? {
		mut engine := new_text_engine(1)!
		defer { engine.free() }
		for pair in [[48.0, 15.0, 67.2], [38.0, 18.0, 38.0], [22.0, 14.0, 30.8]] {
			base := TextStyle{ font_family: 'Inter', size: pair[0], line_height: pair[2], lines: 5 }
			runs := [
				TextRun{ text: 'Large ', style: TextStyle{ ...base, weight: 900 } },
				TextRun{ text: 'small', style: TextStyle{ ...base, size: pair[1] } },
			]
			single := engine.shape_runs(runs, base, -1, 5, false)!
			fallback := engine.shape('Latin ♜', base, -1, 5, false)!
			assert math.abs(fallback.size.height - pair[2]) < 0.02
			assert math.abs(single.size.height - pair[2]) < 0.02
			wrapped_runs := [TextRun{ text: 'Large first ', style: base },
				TextRun{ text: 'small second words third line', style: TextStyle{ ...base, size: pair[1], baseline_offset: 3 } }]
			for ellipsis in [false, true] {
				shaped := engine.shape_runs(wrapped_runs, base, 160, 2, ellipsis)!
				assert shaped.lines.len >= 2
				assert math.abs(shaped.size.height - f64(shaped.lines.len) * pair[2]) < 0.02
				for i, line in shaped.lines {
					assert math.abs(line.y - f64(i) * pair[2]) < 0.02
				}
				if ellipsis {
					assert shaped.lines.len == 2
				}
			}
			shaped := engine.shape_runs(wrapped_runs, base, 160, 5, true)!
			measured := layout_measure_vglyph_runs(wrapped_runs, base, 160)!
			assert math.abs(measured.height - shaped.size.height) < 0.02
		}
	}
}

fn test_rich_baseline_offset_is_complete_run_style() {
	$if ( linux || ( ( macos || windows ) && ui2_custom_rendering ?) ) && !ui2_headless ? {
		mut engine := new_text_engine(1)!
		defer { engine.free() }
		base := TextStyle{ font_family: 'Inter', size: 24, line_height: 36, baseline_offset: 3 }
		plain := engine.shape('baseline', base, -1, 1, false)!
		rich := engine.shape_runs([TextRun{ text: 'baseline', style: base }], base, -1, 1, false)!
		assert math.abs(plain.layout.items[0].y - rich.layout.items[0].y) < 0.02
	}
}
