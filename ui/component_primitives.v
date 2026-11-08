module ui2

import math

// ComponentSize provides shared metrics for the portable component catalog.
pub enum ComponentSize {
	small
	medium
	large
}

pub struct ComponentMetrics {
pub:
	height    f64
	font_size f64
	padding   f64
	gap       f64
	radius    f64
}

pub fn component_metrics(size ComponentSize) ComponentMetrics {
	return match size {
		.small { ComponentMetrics{24, 12, 6, 4, 4} }
		.medium { ComponentMetrics{32, 14, 8, 6, 6} }
		.large { ComponentMetrics{40, 16, 12, 8, 8} }
	}
}

pub enum ComponentTone {
	neutral
	primary
	success
	warning
	danger
}

// component_tone_colors are the background and text colors of a semantic
// tone, from the kit tokens.
fn component_tone_colors(t KitTokens, tone ComponentTone) (u32, u32) {
	match tone {
		.neutral { return t.surface_muted, t.text }
		.primary { return t.accent, t.on_accent }
		.success { return t.success, t.on_success }
		.warning { return t.warning, t.on_warning }
		.danger { return t.danger, t.on_danger }
	}
}

fn component_finite(value f64) bool {
	return !math.is_nan(value) && !math.is_inf(value, 0)
}

fn component_validate_frame(frame Rect) ! {
	if !component_finite(frame.x) || !component_finite(frame.y)
		|| !component_finite(frame.width) || !component_finite(frame.height)
		|| !component_finite(frame.x + frame.width)
		|| !component_finite(frame.y + frame.height)
		|| frame.width < 0 || frame.height < 0 {
		return error('component frame must be finite with non-negative dimensions')
	}
}

fn component_validate_id(id string) ! {
	if id.trim_space().len == 0 {
		return error('interactive component requires a non-empty id')
	}
}

// component_inset clamps padding to half each dimension. It preserves the
// coordinate space of frame, including when the available space is zero.
pub fn component_inset(frame Rect, padding f64) !Rect {
	component_validate_frame(frame)!
	if !component_finite(padding) || padding < 0 {
		return error('component padding must be finite and non-negative')
	}
	px := math.min(padding, frame.width / 2)
	py := math.min(padding, frame.height / 2)
	return rect(frame.x + px, frame.y + py, frame.width - 2 * px, frame.height - 2 * py)
}

// component_text_width_estimate approximates how wide text renders without a
// text backend: wide (CJK, emoji) runes count as one em and the rest as a
// typical proportional glyph; callers add padding for the slack. Font sizes are
// logical em sizes on every backend, so the estimate is in logical units too.
fn component_text_width_estimate(text string, font_size f64) f64 {
	mut ems := 0.0
	for r in text.runes() {
		ems += if r >= 0x2e80 { 1.0 } else { 0.62 }
	}
	return ems * font_size
}

fn component_local(frame Rect) Rect {
	return rect(0, 0, frame.width, frame.height)
}

// component_part_id is the stable id of one part of a component, for focus,
// state and lookup. An id never chooses a handler: every interactive part
// carries its own typed callback.
fn component_part_id(id string, part string) string {
	return if id.len == 0 { '' } else { '${id}:component:${part}' }
}

// component_absorb is the callback of a surface that takes presses only so they
// stay with it instead of reaching what lies beneath it, such as a dismissing
// backdrop. A view needs a callback before it takes pointer input at all.
fn component_absorb(_ ElementEvent) {}

// component_forward_click passes a part's click on to an application callback,
// leaving every other event kind out. A nil callback stays nil.
fn component_forward_click(callback ElementCallback) ElementCallback {
	if voidptr(callback) == unsafe { nil } {
		return unsafe { nil }
	}
	return fn [callback] (event ElementEvent) {
		if event.kind == .click {
			callback(event)
		}
	}
}

fn component_finish(el Element) !Element {
	validate_element_tree(el)!
	return el
}

// component_popup_shadow is the drop shadow a floating surface casts: popovers,
// menus, hover cards, dialogs and sheets, as GPUI Kit's popups do.
pub fn component_popup_shadow() BoxShadow {
	return box_shadow(0x000000, 0.16, 24, 8)
}
