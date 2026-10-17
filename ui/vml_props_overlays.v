module ui2

// Overlay surfaces: Dialog, Popover, MenuOverlay, ContextMenu and Tooltip. Each
// is a View presented through with_overlay. `owner`, `anchor` and
// `initial_focus` name elements by their local id. on_open and on_dismiss are
// both overlay callbacks and element events.

// VmlOverlayFields are the overlay properties; defaults equal OverlayConfig.
pub struct VmlOverlayFields {
pub mut:
	open               bool
	owner              string
	anchor             string
	point              ?OverlayPoint
	placement          OverlayPlacement = .bottom_start
	gap                f64              = 6
	margin             f64              = 8
	initial_focus      string
	dismiss_on_escape  bool     = true
	dismiss_on_outside bool     = true
	backdrop           BoxStyle = BoxStyle{
		bg: 0x202938
	}
	backdrop_opacity   f64 = 0.3
	tooltip_delay      f64 = 0.5
}

pub fn (f VmlOverlayFields) overlay_config(kind OverlayKind, p CommonProps, ctx VmlBuildContext) OverlayConfig {
	return OverlayConfig{
		kind:               kind
		open:               f.open
		owner:              ctx.resolve_id(f.owner)
		anchor:             ctx.resolve_id(f.anchor)
		point:              f.point
		placement:          f.placement
		gap:                f.gap
		margin:             f.margin
		initial_focus:      ctx.resolve_id(f.initial_focus)
		dismiss_on_escape:  f.dismiss_on_escape
		dismiss_on_outside: f.dismiss_on_outside
		on_dismiss:         p.on_dismiss
		on_open:            p.on_open
		tooltip_delay:      f.tooltip_delay
		backdrop:           f.backdrop
		backdrop_opacity:   f.backdrop_opacity
	}
}

// The surface is a View; with_overlay runs after the common properties, so the
// overlay decides visibility, focus and the accessibility role.
fn vml_overlay_surface(p CommonProps, ctx VmlBuildContext) Element {
	return vml_handled(view(ctx.id, ctx.frame, BoxStyle{}, ctx.children), ctx, p.element_callback())
}

fn vml_present_overlay(el Element, kind OverlayKind, f VmlOverlayFields, p CommonProps, ctx VmlBuildContext) !Element {
	return with_overlay(p.project_common(el, ctx), f.overlay_config(kind, p, ctx))!
}

pub struct DialogProps {
	CommonProps
	VmlOverlayFields
}

pub fn (p DialogProps) vml_container() {}

pub fn (p DialogProps) vml_custom_renderer() {}

pub fn (p DialogProps) control_id_required() bool {
	return true
}

pub fn (p DialogProps) build(ctx VmlBuildContext) !Element {
	return vml_overlay_surface(p.CommonProps, ctx)
}

pub fn (p DialogProps) project(el Element, ctx VmlBuildContext) !Element {
	return vml_present_overlay(el, .dialog, p.VmlOverlayFields, p.CommonProps, ctx)
}

pub struct PopoverProps {
	CommonProps
	VmlOverlayFields
}

pub fn (p PopoverProps) vml_container() {}

pub fn (p PopoverProps) vml_custom_renderer() {}

pub fn (p PopoverProps) control_id_required() bool {
	return true
}

pub fn (p PopoverProps) build(ctx VmlBuildContext) !Element {
	return vml_overlay_surface(p.CommonProps, ctx)
}

pub fn (p PopoverProps) project(el Element, ctx VmlBuildContext) !Element {
	return vml_present_overlay(el, .popover, p.VmlOverlayFields, p.CommonProps, ctx)
}

pub struct MenuOverlayProps {
	CommonProps
	VmlOverlayFields
}

pub fn (p MenuOverlayProps) vml_container() {}

pub fn (p MenuOverlayProps) vml_custom_renderer() {}

pub fn (p MenuOverlayProps) control_id_required() bool {
	return true
}

pub fn (p MenuOverlayProps) build(ctx VmlBuildContext) !Element {
	return vml_overlay_surface(p.CommonProps, ctx)
}

pub fn (p MenuOverlayProps) project(el Element, ctx VmlBuildContext) !Element {
	return vml_present_overlay(el, .menu, p.VmlOverlayFields, p.CommonProps, ctx)
}

pub struct ContextMenuProps {
	CommonProps
	VmlOverlayFields
}

pub fn (p ContextMenuProps) vml_container() {}

pub fn (p ContextMenuProps) vml_custom_renderer() {}

pub fn (p ContextMenuProps) control_id_required() bool {
	return true
}

pub fn (p ContextMenuProps) build(ctx VmlBuildContext) !Element {
	return vml_overlay_surface(p.CommonProps, ctx)
}

pub fn (p ContextMenuProps) project(el Element, ctx VmlBuildContext) !Element {
	return vml_present_overlay(el, .context_menu, p.VmlOverlayFields, p.CommonProps, ctx)
}

pub struct TooltipProps {
	CommonProps
	VmlOverlayFields
}

pub fn (p TooltipProps) vml_container() {}

pub fn (p TooltipProps) vml_custom_renderer() {}

pub fn (p TooltipProps) control_id_required() bool {
	return true
}

pub fn (p TooltipProps) build(ctx VmlBuildContext) !Element {
	return vml_overlay_surface(p.CommonProps, ctx)
}

pub fn (p TooltipProps) project(el Element, ctx VmlBuildContext) !Element {
	return vml_present_overlay(el, .tooltip, p.VmlOverlayFields, p.CommonProps, ctx)
}
