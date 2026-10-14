module ui2

import math

// Overlays retain their declaration owner but present in the window's overlay
// layer, outside the owner's scroll clip and visual transform.
pub enum OverlayKind {
	dialog
	popover
	menu
	context_menu
	tooltip
}

pub enum OverlayPlacement {
	bottom_start
	bottom
	bottom_end
	top_start
	top
	top_end
	right_start
	right
	right_end
	left_start
	left
	left_end
}

pub enum OverlayDismissReason {
	escape
	outside_pointer
	selection
	owner_unavailable
	pointer_leave
}

pub struct OverlayPoint {
pub:
	x f64
	y f64
}

// open is controlled by the declaration. Dismissal requests notify on_dismiss;
// the handler closes the overlay by updating its source, and can veto a request.
pub struct OverlayConfig {
pub:
	kind               OverlayKind = .popover
	open               bool
	owner              string
	anchor             string
	point              ?OverlayPoint
	placement          OverlayPlacement = .bottom_start
	gap                f64              = 6
	margin             f64              = 8
	initial_focus      string
	dismiss_on_escape  bool            = true
	dismiss_on_outside bool            = true
	on_dismiss         ElementCallback = unsafe { nil }
	on_open            ElementCallback = unsafe { nil }
	tooltip_delay      f64             = 0.5
	backdrop           BoxStyle        = BoxStyle{ bg: 0x202938 }
	backdrop_opacity   f64             = 0.3
}

pub fn (config OverlayConfig) validate() ! {
	if !finite_number(config.gap) || config.gap < 0 || !finite_number(config.margin)
		|| config.margin < 0 {
		return error('overlay gap and margin must be finite nonnegative logical units')
	}
	if !finite_number(config.tooltip_delay) || config.tooltip_delay < 0 {
		return error('tooltip delay must be finite and nonnegative seconds')
	}
	if !finite_number(config.backdrop_opacity) || config.backdrop_opacity < 0
		|| config.backdrop_opacity > 1 {
		return error('overlay backdrop opacity must be between zero and one')
	}
	if point := config.point {
		if !finite_number(point.x) || !finite_number(point.y) {
			return error('overlay point must contain finite logical coordinates')
		}
	}
	if config.kind != .dialog && config.anchor.len == 0 && config.point == none {
		return error('an anchored overlay requires an anchor id or a window point')
	}
	if config.kind == .tooltip && config.initial_focus.len > 0 {
		return error('a tooltip cannot take keyboard focus')
	}
}

// with_overlay turns one retained View into a portal. Its frame specifies the
// surface size; the host resolves position from the current anchor and viewport.
pub fn with_overlay(element Element, config OverlayConfig) !Element {
	config.validate()!
	if element.kind != .view || element.id.len == 0 {
		return error('an overlay requires a View with a stable id')
	}
	validate_layout_frame(element.frame)!
	return Element{
		...element
		overlay:            config
		hidden:             element.hidden || !config.open
		focus_scope:        config.kind in [.dialog, .menu, .context_menu] || config.initial_focus.len > 0 || element.focus_scope
		focus_policy:       if config.kind == .tooltip {
			.unfocusable
		} else if config.kind in [.dialog, .menu, .context_menu] {
			.focusable
		} else {
			element.focus_policy
		}
		tab_index:          if config.kind in [.dialog, .menu, .context_menu] {
			-1
		} else {
			element.tab_index
		}
		accessibility_role: match config.kind {
			.dialog { 'dialog' }
			.menu, .context_menu { 'menu' }
			.tooltip { 'tooltip' }
			.popover { element.accessibility_role }
		}
	}
}

fn overlay_axis(value f64, extent f64, start f64, available f64) f64 {
	return math.max(start, math.min(value, start + available - extent))
}

// Pure placement shared by the host and independent geometry fixtures. Anchors
// and pointer points are in window logical coordinates, after scroll/transforms.
pub fn overlay_frame(config OverlayConfig, size LayoutSize, anchor Rect, viewport Rect) !Rect {
	config.validate()!
	validate_layout_frame(viewport)!
	validate_layout_frame(anchor)!
	if !finite_number(size.width) || !finite_number(size.height) || size.width < 0 || size.height < 0 {
		return error('overlay surface dimensions must be finite and nonnegative')
	}
	margin_x := math.min(config.margin, viewport.width / 2)
	margin_y := math.min(config.margin, viewport.height / 2)
	area := rect(viewport.x + margin_x, viewport.y + margin_y,
		viewport.width - margin_x * 2, viewport.height - margin_y * 2)
	width := math.min(size.width, area.width)
	height := math.min(size.height, area.height)
	if config.kind == .dialog {
		return rect(area.x + (area.width - width) / 2, area.y + (area.height - height) / 2, width, height)
	}
	mut target := anchor
	if point := config.point { target = rect(point.x, point.y, 0, 0) }
	mut x := target.x
	mut y := target.y
	vertical := config.placement in [.bottom_start, .bottom, .bottom_end, .top_start, .top, .top_end]
	if vertical {
		x = match config.placement {
			.bottom, .top { target.x + (target.width - width) / 2 }
			.bottom_end, .top_end { target.x + target.width - width }
			else { target.x }
		}
		below := target.y + target.height + config.gap
		above := target.y - config.gap - height
		prefer_below := config.placement in [.bottom_start, .bottom, .bottom_end]
		y = if prefer_below { below } else { above }
		alternate := if prefer_below { above } else { below }
		if (y < area.y || y + height > area.y + area.height)
			&& alternate >= area.y && alternate + height <= area.y + area.height {
			y = alternate
		}
	} else {
		y = match config.placement {
			.right, .left { target.y + (target.height - height) / 2 }
			.right_end, .left_end { target.y + target.height - height }
			else { target.y }
		}
		right := target.x + target.width + config.gap
		left := target.x - config.gap - width
		prefer_right := config.placement in [.right_start, .right, .right_end]
		x = if prefer_right { right } else { left }
		alternate := if prefer_right { left } else { right }
		if (x < area.x || x + width > area.x + area.width)
			&& alternate >= area.x && alternate + width <= area.x + area.width {
			x = alternate
		}
	}
	return rect(overlay_axis(x, width, area.x, area.width), overlay_axis(y, height, area.y, area.height), width, height)
}
