module ui2

import math

// The kit's shared vocabulary: control sizes, tones, the color math its
// components derive states from, part ids, motion presets and the
// spinner. Components are VML props types (kit_*.v); their colors and metrics
// come from KitTokens (kit_tokens.v).

// ControlSize is the size preset of a control: its height, font size,
// padding, gap and corner radius (KitTokens.metrics).
pub enum ControlSize {
	small
	medium
	large
}

// Tone is the semantic color of a status or emphasis: neutral is the muted
// surface, the others are the accent and status colors.
pub enum Tone {
	neutral
	primary
	info
	success
	warning
	danger
}

// ── Colors ──────────────────────────────────────────────────────────

// kit_mix blends two 0xRRGGBB colors; t = 0 is a, t = 1 is b.
fn kit_mix(a u32, b u32, t f64) u32 {
	amount := math.max(0.0, math.min(1.0, t))
	mut out := u32(0)
	for shift in [u32(16), 8, 0]! {
		from := f64((a >> shift) & 0xff)
		to := f64((b >> shift) & 0xff)
		out |= u32(math.round(from + (to - from) * amount)) << shift
	}
	return out
}

// kit_luminance is the WCAG relative luminance of a color, from 0 to 1.
fn kit_luminance(color u32) f64 {
	weights := [0.2126, 0.7152, 0.0722]!
	mut sum := 0.0
	for i, shift in [u32(16), 8, 0]! {
		channel := f64((color >> shift) & 0xff) / 255.0
		linear := if channel <= 0.03928 {
			channel / 12.92
		} else {
			math.pow((channel + 0.055) / 1.055, 2.4)
		}
		sum += weights[i] * linear
	}
	return sum
}

// kit_contrast is the WCAG contrast ratio of two colors, from 1 to 21.
fn kit_contrast(a u32, b u32) f64 {
	la := kit_luminance(a)
	lb := kit_luminance(b)
	return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05)
}

// kit_legible moves color toward `toward` (normally the text color) until it
// reads at 4.5:1 on bg. Tone colors such as the warning yellow are fills, and
// need darkening before they can be text on a light background.
fn kit_legible(color u32, bg u32, toward u32) u32 {
	for i in 0 .. 11 {
		candidate := kit_mix(color, toward, f64(i) / 10)
		if kit_contrast(candidate, bg) >= 4.5 {
			return candidate
		}
	}
	return toward
}

// ── Parts ───────────────────────────────────────────────────────────

// kit_part_id is the id of one part of a component: `<id>__<part>`, the
// convention of the overlay backdrop and content parts. A component without
// an id has anonymous parts.
pub fn kit_part_id(id string, part string) string {
	return if id.len == 0 { '' } else { id + '__' + part }
}

// ── Motion ──────────────────────────────────────────────────────────

// kit_motion_popup is how a popover, menu, hover card or tooltip appears: it
// fades and grows in, moving 4 units away from its anchor's side.
pub fn kit_motion_popup(placement OverlayPlacement) MotionConfig {
	slide := match placement {
		.bottom_start, .bottom, .bottom_end { motion_slide_y(-4) }
		.top_start, .top, .top_end { motion_slide_y(4) }
		.right_start, .right, .right_end { motion_slide_x(-4) }
		.left_start, .left, .left_end { motion_slide_x(4) }
	}
	return motion_compose(motion_fade(0.12), motion_scale(0.96), slide)
}

// kit_motion_dialog is how a dialog appears: it drops into place from 48 units
// above while fading in, over 0.2 seconds.
pub fn kit_motion_dialog() MotionConfig {
	return MotionConfig{
		enter:            MotionStyle{
			opacity:     0
			translate_y: -48
		}
		enter_transition: MotionTransition{
			duration: 0.2
			easing:   .out_cubic
		}
	}
}

// kit_motion_sheet is how a sheet docked to an edge appears: it slides in from
// (dx, dy), its own width or height beyond that edge, and slides back out.
pub fn kit_motion_sheet(dx f64, dy f64) MotionConfig {
	return MotionConfig{
		enter:            MotionStyle{
			translate_x: dx
			translate_y: dy
		}
		exit:             MotionStyle{
			translate_x: dx
			translate_y: dy
		}
		enter_transition: MotionTransition{
			duration: 0.2
			easing:   .out_cubic
		}
		exit_transition:  MotionTransition{
			duration: 0.2
			easing:   .in_cubic
		}
	}
}

// kit_motion_toast is how a toast comes and goes: it fades in sliding dx along
// x from its region's edge, and moves when the stack above it reflows.
pub fn kit_motion_toast(dx f64) MotionConfig {
	return motion_compose(motion_fade(0.2), motion_slide_x(dx), motion_easing(.out_cubic),
		motion_layout(.position), motion_transition(0.2))
}

// ── Vectors ─────────────────────────────────────────────────────────

// kit_arc_path is the arc of a circle centered at (cx, cy), from turn `start`
// to turn `end` measured clockwise from twelve o'clock. VectorPath has no arc,
// so it is cubic segments of at most a quarter turn each.
pub fn kit_arc_path(cx f64, cy f64, radius f64, start f64, end f64) VectorPath {
	mut path := VectorPath{}
	sweep := end - start
	segments := int(math.max(1, math.ceil(math.abs(sweep) * 4 - 1e-9)))
	step := sweep * 2 * math.pi / f64(segments)
	handle := 4.0 / 3.0 * math.tan(step / 4) * radius
	mut angle := start * 2 * math.pi
	path.move_to(cx + radius * math.sin(angle), cy - radius * math.cos(angle))
	for _ in 0 .. segments {
		next := angle + step
		x0, y0 := cx + radius * math.sin(angle), cy - radius * math.cos(angle)
		x1, y1 := cx + radius * math.sin(next), cy - radius * math.cos(next)
		path.cubic_to(x0 + handle * math.cos(angle), y0 + handle * math.sin(angle),
			x1 - handle * math.cos(next), y1 - handle * math.sin(next), x1, y1)
		angle = next
	}
	return path
}

// kit_spinner_element is the loading indicator: a three-quarter ring in color,
// diameter wide, turning once every 0.8 seconds about its center. Reduced
// motion stills it.
pub fn kit_spinner_element(id string, diameter f64, color u32) Element {
	stroke := math.max(1.5, diameter / 8)
	radius := math.max(0.0, (diameter - stroke) / 2)
	shape := prepare_vector_shape(kit_arc_path(diameter / 2, diameter / 2, radius, 0, 0.75),
		VectorStyle{
			stroke:       color
			stroke_width: stroke
			cap:          .round
		}) or { VectorShape{} }
	canvas := vector_canvas(
		id:     id
		frame:  rect(0, 0, diameter, diameter)
		shapes: if shape.prepared { [shape] } else { []VectorShape{} }
	) or { view(id, rect(0, 0, diameter, diameter), BoxStyle{ transparent: true }, []) }
	turn := motion_keyframes(0.8, MotionKeyframe{
		at:    0
		style: MotionStyle{
			rotation: 0
		}
	}, MotionKeyframe{
		at:    1
		style: MotionStyle{
			rotation: 360
		}
	}).looped()
	return with_motion(Element{
		...canvas
		origin_x:            diameter / 2
		origin_y:            diameter / 2
		accessibility_role:  'progressbar'
		accessibility_label: 'Loading'
	}, motion_compose(motion_timeline(turn)))
}
