module ui2

// Containers: Screen, View, Absolute, Flex/Row/Column, Grid, Stack, Scroll and
// ScaledContent. Each wraps the matching ui2 constructor or layout config.

// ScreenProps is a window root. With `name` it is instead a ScreenManager page:
// a view with screen metadata.
pub struct ScreenProps {
	CommonProps
pub mut:
	name ?string
}

pub fn (p ScreenProps) vml_container() {}

pub fn (p ScreenProps) build(ctx VmlBuildContext) !Element {
	if name := p.name {
		return vml_managed_screen(ctx, name)
	}
	return vml_handled(Element{
		kind:              .screen
		id:                ctx.id
		frame:             ctx.frame
		children:          ctx.children
		compiled_metadata: &CompiledVmlMetadata{
			screen: ManagedScreen{
				name: ctx.id
			}
		}
	}, ctx, p.element_callback())
}

pub fn (p ScreenProps) part(ctx VmlBuildContext) !VmlPart {
	return ManagedScreen{
		name: p.name or { ctx.id }
	}
}

// ViewProps is a plain container. `overlay` presents it as an overlay surface.
pub struct ViewProps {
	CommonProps
pub mut:
	overlay ?OverlayConfig
}

pub fn (p ViewProps) vml_container() {}

pub fn (p ViewProps) build(ctx VmlBuildContext) !Element {
	return vml_handled(view(ctx.id, ctx.frame, BoxStyle{}, ctx.children), ctx, p.element_callback())
}

pub fn (p ViewProps) project(el Element, ctx VmlBuildContext) !Element {
	base := p.CommonProps.project_common(el, ctx)
	config := p.overlay or { return base }
	return with_overlay(base, OverlayConfig{
		...config
		on_open:    if p.on_open != unsafe { nil } { p.on_open } else { config.on_open }
		on_dismiss: if p.on_dismiss != unsafe { nil } { p.on_dismiss } else { config.on_dismiss }
	})!
}

// AbsoluteProps positions its children at their authored x and y.
pub struct AbsoluteProps {
	CommonProps
}

pub fn (p AbsoluteProps) vml_container() {}

pub fn (p AbsoluteProps) vml_positioner() {}

pub fn (p AbsoluteProps) child_placement(placement VmlPlacement) VmlPlacement {
	return .preferred
}

pub fn (p AbsoluteProps) build(ctx VmlBuildContext) !Element {
	return vml_handled(view(ctx.id, ctx.frame, BoxStyle{}, ctx.children), ctx, p.element_callback())
}

// VmlFlexFields are shared by Flex, Row and Column. `spacing` is the older
// spelling of `gap`; `gap` wins when both are authored.
pub struct VmlFlexFields {
pub mut:
	gap         ?f64
	spacing     ?f64
	line_gap    f64 = -1
	wrap        bool
	justify     FlexJustify
	align_items LayoutAlignment = .stretch
}

fn (f VmlFlexFields) build_flex(p CommonProps, orientation LayoutOrientation, ctx VmlBuildContext) !Element {
	mut items := []FlexChild{cap: ctx.children.len}
	for index, child in ctx.children {
		items << ctx.child_layout(index).flex_child(child)
	}
	base := flex(FlexConfig{
		id:          ctx.id
		frame:       ctx.frame
		children:    items
		orientation: orientation
		gap:         f.gap or { f.spacing or { 0 } }
		line_gap:    f.line_gap
		wrap:        f.wrap
		justify:     f.justify
		align:       f.align_items
	})!
	return vml_layout_element(base, p, ctx)
}

// A layout container keeps its authored children and the layout spec the
// LayoutTree resolves; its own frame is its layout input.
fn vml_layout_element(base Element, p CommonProps, ctx VmlBuildContext) Element {
	return Element{
		...vml_handled(view(ctx.id, ctx.frame, BoxStyle{}, ctx.children), ctx, p.element_callback())
		frame:        base.frame
		layout:       base.layout
		layout_input: base.layout_input
	}
}

pub struct FlexProps {
	CommonProps
	VmlFlexFields
pub mut:
	orientation LayoutOrientation
}

pub fn (p FlexProps) vml_container() {}

pub fn (p FlexProps) child_placement(placement VmlPlacement) VmlPlacement {
	return .preferred
}

pub fn (p FlexProps) build(ctx VmlBuildContext) !Element {
	return p.VmlFlexFields.build_flex(p.CommonProps, p.orientation, ctx)
}

// RowProps is a horizontal Flex.
pub struct RowProps {
	CommonProps
	VmlFlexFields
}

pub fn (p RowProps) vml_container() {}

pub fn (p RowProps) child_placement(placement VmlPlacement) VmlPlacement {
	return .preferred
}

pub fn (p RowProps) build(ctx VmlBuildContext) !Element {
	return p.VmlFlexFields.build_flex(p.CommonProps, .horizontal, ctx)
}

// ColumnProps is a vertical Flex.
pub struct ColumnProps {
	CommonProps
	VmlFlexFields
}

pub fn (p ColumnProps) vml_container() {}

pub fn (p ColumnProps) child_placement(placement VmlPlacement) VmlPlacement {
	return .preferred
}

pub fn (p ColumnProps) build(ctx VmlBuildContext) !Element {
	return p.VmlFlexFields.build_flex(p.CommonProps, .vertical, ctx)
}

// GridProps places children in cells; `cols` is the older spelling of
// `columns`, and `spacing` sets both axes unless spacing_x/spacing_y do.
pub struct GridProps {
	CommonProps
pub mut:
	columns                ?int
	cols                   ?int
	rows                   int
	orientation            GridOrientation
	spacing                ?f64
	spacing_x              ?f64
	spacing_y              ?f64
	auto_columns_min_width f64
	max_columns            int
	col_default_width      f64
	row_default_height     f64
	col_force_default      bool
	row_force_default      bool
}

pub fn (p GridProps) vml_container() {}

pub fn (p GridProps) child_placement(placement VmlPlacement) VmlPlacement {
	return .preferred
}

pub fn (p GridProps) build(ctx VmlBuildContext) !Element {
	mut spans := []GridSpan{cap: ctx.children.len}
	for index, _ in ctx.children {
		spans << ctx.child_layout(index).grid_span()
	}
	spacing := p.spacing or { 0 }
	base := grid_declaration(GridConfig{
		id:                     ctx.id
		frame:                  ctx.frame
		children:               ctx.children
		child_spans:            spans
		columns:                p.columns or { p.cols or { 0 } }
		rows:                   p.rows
		auto_columns_min_width: p.auto_columns_min_width
		max_columns:            p.max_columns
		orientation:            p.orientation
		spacing:                GridSpacing{
			horizontal: p.spacing_x or { spacing }
			vertical:   p.spacing_y or { spacing }
		}
		column_default_width:   p.col_default_width
		row_default_height:     p.row_default_height
		force_column_width:     p.col_force_default
		force_row_height:       p.row_force_default
	})!
	return vml_layout_element(base, p.CommonProps, ctx)
}

// StackProps layers its children; each child may override the alignment with
// align_self_x/align_self_y.
pub struct StackProps {
	CommonProps
pub mut:
	align_x LayoutAlignment = .start
	align_y LayoutAlignment = .start
}

pub fn (p StackProps) vml_container() {}

pub fn (p StackProps) child_placement(placement VmlPlacement) VmlPlacement {
	return .preferred
}

// A Stack's events are not attached: like the other composite constructors
// it keeps the element the constructor returns.
pub fn (p StackProps) build(ctx VmlBuildContext) !Element {
	mut children := []StackChild{cap: ctx.children.len}
	for index, child in ctx.children {
		children << ctx.child_layout(index).stack_child(child)
	}
	return vml_keyed(stack(StackConfig{
		id:       ctx.id
		frame:    ctx.frame
		align_x:  p.align_x
		align_y:  p.align_y
		children: children
	})!, ctx)
}

// ScrollProps scrolls its content along scroll_mode.
pub struct ScrollProps {
	CommonProps
pub mut:
	persistent  bool
	scroll_mode ScrollMode
}

pub fn (p ScrollProps) vml_container() {}

pub fn (p ScrollProps) child_placement(placement VmlPlacement) VmlPlacement {
	return .inherited_preferred
}

pub fn (p ScrollProps) child_input(frame Rect, child_count int) !Rect {
	return rect(0, 0, 0, 0)
}

pub fn (p ScrollProps) build(ctx VmlBuildContext) !Element {
	return vml_handled(Element{
		...scroll_with_mode(ctx.id, ctx.frame, BoxStyle{}.bg, p.scroll_mode, ctx.children)
		persistent_scrollbars: p.persistent
	}, ctx, p.element_callback())
}

// ScaledContentProps fits a fixed logical composition inside its frame.
pub struct ScaledContentProps {
	CommonProps
pub mut:
	content_width  f64
	content_height f64
}

pub fn (p ScaledContentProps) vml_container() {}

pub fn (p ScaledContentProps) vml_custom_renderer() {}

pub fn (p ScaledContentProps) validate() ! {
	p.CommonProps.validate()!
	if p.content_width <= 0 { return error('`content_width` must be positive') }
	if p.content_height <= 0 { return error('`content_height` must be positive') }
}

pub fn (p ScaledContentProps) child_input(frame Rect, child_count int) !Rect {
	return rect(0, 0, p.content_width, p.content_height)
}

pub fn (p ScaledContentProps) build(ctx VmlBuildContext) !Element {
	return vml_handled(scaled_content(ctx.id, ctx.frame, p.content_width, p.content_height,
		BoxStyle{}, ctx.children), ctx, p.element_callback())
}
