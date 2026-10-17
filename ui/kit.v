module ui2

import math

// The kit's shared vocabulary: control sizes, tones and the color math its
// components derive states from. Components are VML props types (kit_*.v);
// their colors and metrics come from KitTokens (kit_tokens.v).

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
