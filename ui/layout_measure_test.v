module ui2

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
