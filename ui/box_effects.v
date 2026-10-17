module ui2

import math

// GradientStop is one color of a gradient: where along it (0 at the start, 1 at
// the end) and how opaque it is there.
pub struct GradientStop {
pub:
	color    u32
	position f64
	opacity  f64 = 1.0
}

// Gradient is a linear gradient across a view's box (buttons keep their solid fill,
// since a native button draws its title beneath any gradient layer; make a
// gradient button from a view with button_behavior). `angle` is in degrees, measured
// clockwise from left-to-right: 0 runs left to right, 90 top to bottom. It
// spans the box's projection onto that direction, corner to corner, the way
// CSS linear-gradient does.
pub struct Gradient {
pub:
	angle f64
	stops []GradientStop
}

// BoxShadow is a drop shadow drawn beneath a box: offset by x and y, grown by
// spread, and blurred over `blur` points. AppKit, UIKit and the custom renderer
// draw it; Win32 child windows cannot, so Windows leaves it out.
pub struct BoxShadow {
pub:
	color   u32
	opacity f64
	blur    f64
	x       f64
	y       f64
	spread  f64
}

// gradient_stop is shorthand for an opaque stop.
pub fn gradient_stop(color u32, position f64) GradientStop {
	return GradientStop{
		color:    color
		position: position
	}
}

// linear_gradient builds a Gradient from its angle and stops.
pub fn linear_gradient(angle f64, stops ...GradientStop) Gradient {
	return Gradient{
		angle: angle
		stops: stops
	}
}

// box_shadow is shorthand for the common soft shadow: color, opacity, blur and a
// downward offset.
pub fn box_shadow(color u32, opacity f64, blur f64, y f64) BoxShadow {
	return BoxShadow{
		color:   color
		opacity: opacity
		blur:    blur
		y:       y
	}
}

fn unit_clamp(value f64) f64 {
	return if math.is_nan(value) || value < 0 {
		0.0
	} else if value > 1 {
		1.0
	} else {
		value
	}
}

// box_fill_opacity is the opacity the fill is drawn with: zero for a transparent
// box, otherwise the declared opacity clamped to [0, 1].
fn box_fill_opacity(box BoxStyle) f64 {
	return if box.transparent { 0.0 } else { unit_clamp(box.opacity) }
}

fn box_has_gradient(box BoxStyle) bool {
	return !box.transparent && box.gradient.stops.len >= 2
}

fn box_has_shadow(box BoxStyle) bool {
	return unit_clamp(box.shadow.opacity) > 0
}

// gradient_sorted_stops returns the stops ordered by position, with positions
// and opacities clamped to [0, 1]. Equal positions keep their declared order,
// which is how a hard color change is written.
fn gradient_sorted_stops(gradient Gradient) []GradientStop {
	mut stops := gradient.stops.map(GradientStop{
		color:    it.color & 0xffffff
		position: unit_clamp(it.position)
		opacity:  unit_clamp(it.opacity)
	})
	stops.sort_with_compare(fn (a &GradientStop, b &GradientStop) int {
		return if a.position < b.position {
			-1
		} else if a.position > b.position {
			1
		} else {
			0
		}
	})
	return stops
}

fn mix_channel(a u32, b u32, shift u32, t f64) u32 {
	ca := f64((a >> shift) & 0xff)
	cb := f64((b >> shift) & 0xff)
	return u32(math.round(ca + (cb - ca) * t)) << shift
}

// gradient_color_at returns the color and opacity a gradient has at `t` along
// its length, interpolating in sRGB between the stops around it. Before the
// first stop and after the last the end colors continue.
fn gradient_color_at(stops []GradientStop, t f64) (u32, f64) {
	if stops.len == 0 {
		return u32(0), 0.0
	}
	if t <= stops[0].position {
		return stops[0].color, stops[0].opacity
	}
	for i in 1 .. stops.len {
		next := stops[i]
		if t <= next.position {
			prev := stops[i - 1]
			span := next.position - prev.position
			f := if span <= 0 { 1.0 } else { (t - prev.position) / span }
			color := mix_channel(prev.color, next.color, 16, f) | mix_channel(prev.color,
				next.color, 8, f) | mix_channel(prev.color, next.color, 0, f)
			return color, prev.opacity + (next.opacity - prev.opacity) * f
		}
	}
	last := stops[stops.len - 1]
	return last.color, last.opacity
}

// GradientLine is where a gradient starts and ends in a box's own coordinates.
struct GradientLine {
	x0 f64
	y0 f64
	x1 f64
	y1 f64
}

// gradient_line places a gradient across a w by h box: through its center along
// `angle`, long enough that the corners farthest along it are exactly at 0 and 1,
// as CSS does.
fn gradient_line(angle f64, w f64, h f64) GradientLine {
	radians := angle * math.pi / 180.0
	dx := math.cos(radians)
	dy := math.sin(radians)
	half := (math.abs(w * dx) + math.abs(h * dy)) / 2
	cx := w / 2
	cy := h / 2
	return GradientLine{
		x0: cx - dx * half
		y0: cy - dy * half
		x1: cx + dx * half
		y1: cy + dy * half
	}
}

// gradient_position is how far along the line a point lies, from 0 to 1.
fn gradient_position(line GradientLine, x f64, y f64) f64 {
	lx := line.x1 - line.x0
	ly := line.y1 - line.y0
	length2 := lx * lx + ly * ly
	if length2 <= 0 {
		return 0
	}
	return unit_clamp(((x - line.x0) * lx + (y - line.y0) * ly) / length2)
}

// box_rounded_border is the width of a box's border when it should follow the
// box's rounded corners: a radius and the same width on all four sides. Square
// boxes and uneven borders return 0 and keep their straight sides.
fn box_rounded_border(box BoxStyle) f64 {
	if box.radius <= 0 || box.border_left <= 0 || box.border_left != box.border_top
		|| box.border_left != box.border_right || box.border_left != box.border_bottom {
		return 0
	}
	return box.border_left
}
