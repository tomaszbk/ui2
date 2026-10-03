module ui2

import math

fn layout_measure_fixture_width(text string) f64 {
	mut width := 0.0
	for character in text.runes() {
		width += match character {
			`W` { 12.0 }
			`i` { 3.0 }
			` ` { 4.0 }
			else { 8.0 }
		}
	}
	return width
}

fn layout_measure_fixture_text(text string, style TextStyle, width f64) !LayoutSize {
	return layout_measure_text_lines(text, style, width, 20, layout_measure_fixture_width)
}

fn layout_measure_unexpected_text(_text string, _style TextStyle, _width f64) !LayoutSize {
	return error('fixed and hidden elements must not request text measurement')
}

fn test_layout_constraints_distinguish_zero_from_unbounded_and_validate() {
	unbounded := LayoutConstraints{ min_width: 10 }
	assert unbounded.constrain(LayoutSize{ width: 200, height: 50 })! == LayoutSize{ width: 200, height: 50 }
	assert unbounded.constrain(LayoutSize{ width: 2, height: -3 })! == LayoutSize{ width: 10 }
	zero := LayoutConstraints{ max_width: 0, max_height: 0 }
	assert zero.constrain(LayoutSize{ width: 200, height: 50 })! == LayoutSize{}
	if _ := (LayoutConstraints{ min_width: 20, max_width: 10 }).constrain(LayoutSize{}) {
		assert false, 'contradictory constraints must be rejected'
	}
	if _ := (LayoutConstraints{ max_height: -2 }).constrain(LayoutSize{}) {
		assert false, 'only -1 represents an unbounded maximum'
	}
	tight := LayoutConstraints{ min_width: 100, max_width: 100, min_height: 40, max_height: 40 }
	assert tight.loosen() == LayoutConstraints{ max_width: 100, max_height: 40 }
	assert tight.deflate(BoxPadding{ left: 20, right: 30, top: 50 })! == LayoutConstraints{
		min_width:  50
		max_width:  50
		max_height: 0
	}
	if _ := tight.deflate(BoxPadding{ left: -1 }) {
		assert false, 'negative padding must be rejected'
	}
}

fn test_layout_measure_text_uses_available_content_width_and_preserves_point_style() {
	label_inset := $if macos && !ui2_custom_rendering ?&& !ui2_headless ? { 4.0 } $else { 0.0 }
	style := TextStyle{ size: 14, lines: 3 }
	label := label('description', 'WW WW', Rect{}, style)
	unbounded := measure_layout_element(label, LayoutConstraints{}, layout_measure_fixture_text)!
	assert unbounded == LayoutSize{ width: 52 + label_inset, height: 20 }
	narrow := measure_layout_element(label, LayoutConstraints{ max_width: 30 }, layout_measure_fixture_text)!
	assert narrow == LayoutSize{ width: 24 + label_inset, height: 40 }
	assert label.text_style.size == 14
	assert label.frame == Rect{}
	fixed_width := Element{ ...label, frame: rect(0, 0, 30, 0) }
	assert measure_layout_element(fixed_width, LayoutConstraints{}, layout_measure_fixture_text)! == LayoutSize{ width: 30, height: 40 }
	button := button('action', 'WW WW', Rect{}, BoxStyle{}, style)
	// Control insets are removed before wrapping, then added to its answer.
	assert measure_layout_element(button, LayoutConstraints{ max_width: 54 }, layout_measure_fixture_text)! == LayoutSize{ width: 48, height: 52 }
}

fn test_layout_measure_declared_sizes_hidden_nodes_and_nested_extents() {
	label_inset := $if macos && !ui2_custom_rendering ?&& !ui2_headless ? { 4.0 } $else { 0.0 }
	fixed := label('fixed', 'text', rect(7, 3, 40, 30), TextStyle{})
	assert measure_layout_element(fixed, LayoutConstraints{ max_width: 20 }, layout_measure_unexpected_text)! == LayoutSize{ width: 20, height: 30 }
	hidden := Element{ ...fixed, hidden: true }
	assert measure_layout_element(hidden, LayoutConstraints{}, layout_measure_unexpected_text)! == LayoutSize{}
	child := label('intrinsic', 'WWW', rect(7, 3, 0, 0), TextStyle{})
	container := view('root', Rect{}, BoxStyle{}, [
		view('nested', rect(10, 5, 0, 0), BoxStyle{}, [child]),
		Element{ ...fixed, frame: rect(1_000, 1_000, 400, 400), hidden: true },
	])
	assert measure_layout_element(container, LayoutConstraints{}, layout_measure_fixture_text)! == LayoutSize{ width: 53 + label_inset, height: 28 }
}

fn test_layout_default_text_measurement_uses_real_fonts_before_window_creation() {
	style := TextStyle{ size: 16 }
	wide := measure_layout_text('WWW', style, -1)!
	narrow := measure_layout_text('iii', style, -1)!
	assert wide.width > narrow.width * 1.5
	assert narrow.width > 0
	assert wide.height > 0
	larger := measure_layout_text('WWW', TextStyle{ size: 32 }, -1)!
	assert larger.width > wide.width * 1.7
	assert larger.height > wide.height * 1.7
	wrapped := measure_layout_text('WWW WWW', TextStyle{ ...style, lines: 3 }, wide.width + 1)!
	assert wrapped.width <= wide.width + 1
	assert wrapped.height > wide.height
}

fn layout_measure_require_declared_zero_lines(_text string, style TextStyle, _width f64) !LayoutSize {
	if style.lines != 0 { return error('external callbacks must receive the declared label style') }
	return LayoutSize{width: 16, height: 20}
}

fn layout_measure_require_declared_editor_style(_text string, style TextStyle, _width f64) !LayoutSize {
	if style.lines != 1 || style.size != 16 || style.font_family != 'Roboto Mono' {
		return error('external callbacks must receive the declared editor style')
	}
	return LayoutSize{width: 16, height: 20}
}

fn test_custom_intrinsic_text_area_wraps_all_rows_in_the_drawn_content_width() {
	$if (linux || ((macos || windows) && ui2_custom_rendering ?)) && !ui2_headless ? {
		style := TextStyle{size: 16, font_family: 'Roboto Mono'}
		advance := measure_layout_text('M', style, -1)!.width
		// The width accommodates exactly two fixed-width glyphs. Five glyphs
		// occupy three rows and the explicit paragraph contributes a fourth.
		content_width := advance * 2 + 0.05
		for scrolling in [true, false] {
			area := Element{
				...text_area('notes', 'MMMMM\nM', Rect{}, BoxStyle{}, style)
				padding_left: 12
				disable_scroll: !scrolling
			}
			gutter := if scrolling { 12.0 } else { 8.0 }
			measured := measure_layout_element(area,
				LayoutConstraints{max_width: content_width + 12 + gutter}, measure_layout_text)!
			assert measured.width > advance * 2 + 12 + gutter - 0.01
			assert measured.width <= content_width + 12 + gutter
			// Pango quantizes line height to 1/1024 of a device pixel.
			assert math.abs(measured.height - font_line_height(style.size) * 4 - 16) < 0.01
			assert area.text_style.lines == 1
			// Only the built-in adapter requests unlimited editor wrapping;
			// an embedder's callback still sees its original public style.
			custom := measure_layout_element(area, LayoutConstraints{},
				layout_measure_require_declared_editor_style)!
			assert custom.height == 36
			fixed := Element{...area, frame: rect(0, 0, 90, 30)}
			assert measure_layout_element(fixed, LayoutConstraints{}, layout_measure_unexpected_text)! == LayoutSize{width: 90, height: 30}
		}
		label_one_line := label('caption', 'one\ntwo', Rect{}, TextStyle{lines: 0})
		assert measure_layout_element(label_one_line, LayoutConstraints{}, layout_measure_require_declared_zero_lines)! == LayoutSize{width: 16, height: 20}
		assert label_one_line.text_style.lines == 0
		one_row := measure_layout_text('one', label_one_line.text_style, -1)!
		default_label := measure_layout_element(label_one_line, LayoutConstraints{}, measure_layout_text)!
		assert default_label.height == one_row.height
	}
}
