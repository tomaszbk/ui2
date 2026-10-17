module ui2

import math

fn test_gradient_colors_interpolate_between_sorted_stops() {
	stops := gradient_sorted_stops(linear_gradient(0, gradient_stop(0xffffff, 1), gradient_stop(0x000000,
		0), GradientStop{ color: 0xff0000, position: 0.5, opacity: 0.5 }))
	assert stops.map(it.position) == [0.0, 0.5, 1.0]
	mut color, mut opacity := gradient_color_at(stops, 0)
	assert color == 0x000000 && opacity == 1
	color, opacity = gradient_color_at(stops, 0.25)
	assert color == 0x800000 && opacity == 0.75
	color, opacity = gradient_color_at(stops, 0.75)
	assert color == 0xff8080 && opacity == 0.75
	color, _ = gradient_color_at(stops, 2)
	assert color == 0xffffff
	// A hard stop: both sides of 0.5 keep their own colors.
	hard := gradient_sorted_stops(linear_gradient(0, gradient_stop(0x0000ff, 0), gradient_stop(0x0000ff,
		0.5), gradient_stop(0x00ff00, 0.5), gradient_stop(0x00ff00, 1)))
	color, _ = gradient_color_at(hard, 0.49)
	assert color == 0x0000ff
	color, _ = gradient_color_at(hard, 0.51)
	assert color == 0x00ff00
}

fn test_gradient_line_reaches_the_corners_like_css() {
	horizontal := gradient_line(0, 200, 100)
	assert math.abs(gradient_position(horizontal, 0, 50)) < 1e-9
	assert math.abs(gradient_position(horizontal, 200, 0) - 1) < 1e-9
	vertical := gradient_line(90, 200, 100)
	assert math.abs(gradient_position(vertical, 100, 0)) < 1e-9
	assert math.abs(gradient_position(vertical, 0, 100) - 1) < 1e-9
	diagonal := gradient_line(45, 100, 100)
	assert math.abs(gradient_position(diagonal, 0, 0)) < 1e-9
	assert math.abs(gradient_position(diagonal, 100, 100) - 1) < 1e-9
	assert math.abs(gradient_position(diagonal, 100, 0) - 0.5) < 1e-9
}

fn test_box_effects_defaults_change_nothing() {
	plain := BoxStyle{}
	assert box_fill_opacity(plain) == 1
	assert !box_has_gradient(plain)
	assert !box_has_shadow(plain)
	assert box_fill_opacity(BoxStyle{ transparent: true }) == 0
	assert box_fill_opacity(BoxStyle{ opacity: 7 }) == 1
	assert box_fill_opacity(BoxStyle{ opacity: math.nan() }) == 0
	assert !box_has_gradient(BoxStyle{ gradient: linear_gradient(0, gradient_stop(0, 0)) })
	assert box_has_shadow(BoxStyle{ shadow: box_shadow(0, 0.3, 8, 2) })
}

fn test_box_rounded_border_needs_a_radius_and_even_sides() {
	even := BoxStyle{
		radius:        8
		border_left:   2
		border_top:    2
		border_right:  2
		border_bottom: 2
	}
	assert box_rounded_border(even) == 2
	assert box_rounded_border(BoxStyle{ ...even, radius: 0 }) == 0
	assert box_rounded_border(BoxStyle{ ...even, border_bottom: 1 }) == 0
	assert box_rounded_border(BoxStyle{ radius: 8 }) == 0
}

fn test_zero_lines_reach_the_renderers_as_unlimited() {
	assert text_line_budget(TextStyle{ lines: 0 }.lines) == text_lines_unlimited
	assert text_line_budget(TextStyle{}.lines) == 1
	assert text_line_budget(TextStyle{ lines: 3 }.lines) == 3
	assert text_line_budget(TextStyle{ lines: -3 }.lines) == text_lines_unlimited
	measured := layout_measure_text_lines('one two three', TextStyle{ lines: 0 }, 30, 10,
		fn (line string) f64 {
			return f64(line.len) * 5
		}) or { panic(err) }
	assert measured.height == 30
}
