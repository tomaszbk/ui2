module ui2

// BoxStylePatch changes only explicitly supplied properties, including black
// colors, zero widths and false transparency. Interaction never changes layout.
pub struct BoxStylePatch {
pub:
	bg                  ?u32
	radius              ?f64
	transparent         ?bool
	border_color        ?u32
	border_left         ?f64
	border_top          ?f64
	border_right        ?f64
	border_bottom       ?f64
	border_left_color   ?u32
	border_top_color    ?u32
	border_right_color  ?u32
	border_bottom_color ?u32
	border_pattern      ?BorderPattern
	dash_length         ?f64
	dash_gap            ?f64
}

pub struct InteractionStyle {
pub:
	hover    BoxStylePatch
	focus    BoxStylePatch
	pressed  BoxStylePatch
	disabled BoxStylePatch
}

pub fn with_interaction_style(el Element, style InteractionStyle) Element {
	return Element{ ...el, interaction_style: style }
}

fn apply_box_patch(base BoxStyle, patch BoxStylePatch) BoxStyle {
	return BoxStyle{
		...base
		bg:                  patch.bg or { base.bg }
		radius:              patch.radius or { base.radius }
		transparent:         patch.transparent or { base.transparent }
		border_color:        patch.border_color or { base.border_color }
		border_left:         patch.border_left or { base.border_left }
		border_top:          patch.border_top or { base.border_top }
		border_right:        patch.border_right or { base.border_right }
		border_bottom:       patch.border_bottom or { base.border_bottom }
		border_left_color:   if color := patch.border_left_color {
			?u32(color)
		} else {
			base.border_left_color
		}
		border_top_color:    if color := patch.border_top_color {
			?u32(color)
		} else {
			base.border_top_color
		}
		border_right_color:  if color := patch.border_right_color {
			?u32(color)
		} else {
			base.border_right_color
		}
		border_bottom_color: if color := patch.border_bottom_color {
			?u32(color)
		} else {
			base.border_bottom_color
		}
		border_pattern:      patch.border_pattern or { base.border_pattern }
		dash_length:         patch.dash_length or { base.dash_length }
		dash_gap:            patch.dash_gap or { base.dash_gap }
	}
}

fn interaction_box(el Element, hovered bool, focused bool, pressed bool) BoxStyle {
	if !el.enabled { return apply_box_patch(el.box, el.interaction_style.disabled) }
	mut box := el.box
	if hovered { box = apply_box_patch(box, el.interaction_style.hover) }
	if focused { box = apply_box_patch(box, el.interaction_style.focus) }
	if pressed { box = apply_box_patch(box, el.interaction_style.pressed) }
	return box
}

fn box_edge_color(box BoxStyle, side int) u32 {
	return match side {
		0 { box.border_top_color or { box.border_color } }
		1 { box.border_right_color or { box.border_color } }
		2 { box.border_bottom_color or { box.border_color } }
		else { box.border_left_color or { box.border_color } }
	}
}

fn box_contains_point(area Rect, x f64, y f64) bool {
	return area.width > 0 && area.height > 0 && x >= area.x && y >= area.y
		&& x < area.x + area.width && y < area.y + area.height
}
