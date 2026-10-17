module ui2

// Composite controls: Accordion, TabbedPanel, Carousel, ScreenManager and
// TreeView, with the typed child declarations they read (AccordionItem, Tab,
// CarouselSlide, ManagedScreen/ScreenView, TreeNode). A child declaration is an
// element carrying its record in compiled_metadata, so a parent rebuild sees
// the same records. Like the existing constructors, composites keep the root
// element their constructor returns: element events are not attached.

fn vml_view_id(id string, suffix string) string {
	return if id.len > 0 { id + suffix } else { '' }
}

fn vml_managed_screen(ctx VmlBuildContext, name string) Element {
	return Element{
		...vml_keyed(view(ctx.id, ctx.frame, BoxStyle{}, ctx.children), ctx)
		compiled_metadata: &CompiledVmlMetadata{
			screen: ManagedScreen{
				name: name
			}
		}
	}
}

fn vml_header_box(background u32, radius f64) BoxStyle {
	return BoxStyle{
		bg:     background
		radius: radius
	}
}

fn vml_header_text(color u32, size f64, bold bool) TextStyle {
	return TextStyle{
		color: color
		size:  size
		bold:  bold
		align: .center
	}
}

fn vml_accordion_items(children []Element) ![]AccordionItem {
	mut items := []AccordionItem{cap: children.len}
	for child in children {
		metadata := child.compiled_metadata
		if metadata == unsafe { nil } { return error('Accordion requires typed child declarations') }
		item := metadata.accordion or { return error('Accordion requires typed child declarations') }
		items << AccordionItem{
			...item
			content: child
		}
	}
	return items
}

fn vml_tabbed_panel_tabs(children []Element) ![]TabbedPanelTab {
	mut tabs := []TabbedPanelTab{cap: children.len}
	for child in children {
		metadata := child.compiled_metadata
		if metadata == unsafe { nil } {
			return error('TabbedPanel requires typed child declarations')
		}
		tab := metadata.tab or { return error('TabbedPanel requires typed child declarations') }
		tabs << TabbedPanelTab{
			...tab
			content: child
		}
	}
	return tabs
}

fn vml_managed_screens(children []Element) ![]ManagedScreen {
	mut screens := []ManagedScreen{cap: children.len}
	for child in children {
		metadata := child.compiled_metadata
		if metadata == unsafe { nil } { return error('ScreenManager requires Screen children') }
		record := metadata.screen or { return error('ScreenManager requires Screen children') }
		screens << ManagedScreen{
			...record
			content: child
		}
	}
	return screens
}

fn vml_tree_nodes(children []Element, tag string) ![]TreeViewNode {
	mut nodes := []TreeViewNode{cap: children.len}
	for child in children {
		metadata := child.compiled_metadata
		if metadata == unsafe { nil } { return error('${tag} requires TreeNode children') }
		nodes << metadata.tree or { return error('${tag} requires TreeNode children') }
	}
	return nodes
}

// AccordionProps shows the content of the `current` item between its headers.
pub struct AccordionProps {
	CommonProps
pub mut:
	current                 int
	orientation             LayoutOrientation
	min_space               f64 = 44
	title_background        u32 = 0xe2e8f0
	active_title_background u32 = 0x2563eb
	title_color             u32 = 0x475569
	active_title_color      u32 = 0xffffff
	title_font_size         f64 = 14
	title_corner_radius     f64 = 6
}

pub fn (p AccordionProps) vml_container() {}

fn (p AccordionProps) config(ctx VmlBuildContext, items []AccordionItem) AccordionConfig {
	return AccordionConfig{
		id:                       ctx.id
		frame:                    ctx.frame
		current:                  p.current
		orientation:              p.orientation
		min_space:                p.min_space
		header_box:               vml_header_box(p.title_background, p.title_corner_radius)
		active_header_box:        vml_header_box(p.active_title_background, p.title_corner_radius)
		header_text_style:        vml_header_text(p.title_color, p.title_font_size, false)
		active_header_text_style: vml_header_text(p.active_title_color, p.title_font_size,
			true)
		items:                    items
	}
}

// Items fill the content region left by the headers.
pub fn (p AccordionProps) child_input(frame Rect, child_count int) !Rect {
	geometry := accordion_geometry(p.config(VmlBuildContext{ frame: frame }, []AccordionItem{len: child_count}))!
	return rect(0, 0, geometry.content.width, geometry.content.height)
}

pub fn (p AccordionProps) build(ctx VmlBuildContext) !Element {
	return vml_keyed(accordion(p.config(ctx, vml_accordion_items(ctx.children)!))!, ctx)
}

// AccordionItemProps is one Accordion section; on_select runs from its header.
pub struct AccordionItemProps {
	CommonProps
pub mut:
	title     string
	on_select ElementCallback = unsafe { nil }
}

pub fn (p AccordionItemProps) vml_container() {}

fn (p AccordionItemProps) item(ctx VmlBuildContext) AccordionItem {
	return AccordionItem{
		id:       ctx.id
		title:    p.title
		on_event: p.on_select
		enabled:  p.enabled or { true }
	}
}

pub fn (p AccordionItemProps) build(ctx VmlBuildContext) !Element {
	return Element{
		...vml_keyed(view(vml_view_id(ctx.id, '__content'), ctx.frame, BoxStyle{}, ctx.children),
			ctx)
		compiled_metadata: &CompiledVmlMetadata{
			accordion: p.item(ctx)
		}
	}
}

pub fn (p AccordionItemProps) part(ctx VmlBuildContext) !VmlPart {
	return p.item(ctx)
}

// TabbedPanelProps shows the `current` tab (or its older spelling
// `current_tab`) below or beside its tab headers.
pub struct TabbedPanelProps {
	CommonProps
pub mut:
	current               ?int
	current_tab           ?int
	tab_pos               TabPosition
	tab_height            f64 = 40
	tab_width             f64 = 100
	tab_background        u32 = 0xe2e8f0
	active_tab_background u32 = 0xffffff
	tab_color             u32 = 0x475569
	active_tab_color      u32 = 0x0f172a
	tab_font_size         f64 = 14
	tab_corner_radius     f64 = 6
}

pub fn (p TabbedPanelProps) vml_container() {}

pub fn (p TabbedPanelProps) child_input(frame Rect, child_count int) !Rect {
	geometry := tabbed_panel_geometry(TabbedPanelConfig{
		frame:        frame
		tab_position: p.tab_pos
		tab_height:   p.tab_height
		tab_width:    p.tab_width
	})!
	return rect(0, 0, geometry.content.width, geometry.content.height)
}

pub fn (p TabbedPanelProps) build(ctx VmlBuildContext) !Element {
	return vml_keyed(tabbed_panel(TabbedPanelConfig{
		id:                       ctx.id
		frame:                    ctx.frame
		current:                  p.current or { p.current_tab or { 0 } }
		tab_position:             p.tab_pos
		tab_height:               p.tab_height
		tab_width:                p.tab_width
		header_box:               vml_header_box(p.tab_background, p.tab_corner_radius)
		active_header_box:        vml_header_box(p.active_tab_background, p.tab_corner_radius)
		header_text_style:        vml_header_text(p.tab_color, p.tab_font_size, false)
		active_header_text_style: vml_header_text(p.active_tab_color, p.tab_font_size, true)
		tabs:                     vml_tabbed_panel_tabs(ctx.children)!
	})!, ctx)
}

// TabProps is one TabbedPanel page; on_select runs from its header.
pub struct TabProps {
	CommonProps
pub mut:
	text      DisplayText     = ''
	on_select ElementCallback = unsafe { nil }
}

pub fn (p TabProps) vml_container() {}

fn (p TabProps) tab(ctx VmlBuildContext) TabbedPanelTab {
	return TabbedPanelTab{
		id:       ctx.id
		title:    p.text.str()
		on_event: p.on_select
		enabled:  p.enabled or { true }
	}
}

pub fn (p TabProps) build(ctx VmlBuildContext) !Element {
	return Element{
		...vml_keyed(view(vml_view_id(ctx.id, '__content'), ctx.frame, BoxStyle{}, ctx.children),
			ctx)
		compiled_metadata: &CompiledVmlMetadata{
			tab: p.tab(ctx)
		}
	}
}

pub fn (p TabProps) part(ctx VmlBuildContext) !VmlPart {
	return p.tab(ctx)
}

// CarouselProps shows one CarouselSlide at a time.
pub struct CarouselProps {
	CommonProps
pub mut:
	index                       int
	direction                   CarouselDirection
	loop                        bool
	min_move                    f64 = 0.2
	ignore_perpendicular_swipes bool
}

pub fn (p CarouselProps) vml_container() {}

pub fn (p CarouselProps) build(ctx VmlBuildContext) !Element {
	return vml_keyed(carousel(CarouselConfig{
		id:                          ctx.id
		frame:                       ctx.frame
		index:                       p.index
		direction:                   p.direction
		loop:                        p.loop
		min_move:                    p.min_move
		ignore_perpendicular_swipes: p.ignore_perpendicular_swipes
		slides:                      ctx.children
	})!, ctx)
}

pub struct CarouselSlideProps {
	CommonProps
}

pub fn (p CarouselSlideProps) vml_container() {}

pub fn (p CarouselSlideProps) build(ctx VmlBuildContext) !Element {
	return vml_keyed(view(ctx.id, ctx.frame, BoxStyle{}, ctx.children), ctx)
}

// ScreenManagerProps shows the page named `current` (the first when empty).
pub struct ScreenManagerProps {
	CommonProps
pub mut:
	current string
}

pub fn (p ScreenManagerProps) vml_container() {}

pub fn (p ScreenManagerProps) build(ctx VmlBuildContext) !Element {
	return vml_keyed(screen_manager(ScreenManagerConfig{
		id:      ctx.id
		frame:   ctx.frame
		current: p.current
		screens: vml_managed_screens(ctx.children)!
	})!, ctx)
}

// ManagedScreenProps is a ScreenManager page named `name` (default: its id).
pub struct ManagedScreenProps {
	CommonProps
pub mut:
	name ?string
}

pub fn (p ManagedScreenProps) vml_container() {}

pub fn (p ManagedScreenProps) build(ctx VmlBuildContext) !Element {
	return vml_managed_screen(ctx, p.name or { ctx.id })
}

pub fn (p ManagedScreenProps) part(ctx VmlBuildContext) !VmlPart {
	return ManagedScreen{
		name: p.name or { ctx.id }
	}
}

// ScreenViewProps is the same page declaration as ManagedScreen.
pub struct ScreenViewProps {
	CommonProps
pub mut:
	name ?string
}

pub fn (p ScreenViewProps) vml_container() {}

pub fn (p ScreenViewProps) build(ctx VmlBuildContext) !Element {
	return vml_managed_screen(ctx, p.name or { ctx.id })
}

pub fn (p ScreenViewProps) part(ctx VmlBuildContext) !VmlPart {
	return ManagedScreen{
		name: p.name or { ctx.id }
	}
}

// TreeViewProps draws rows for its TreeNode children. It styles itself: the
// authored typography refines every row and foreground the ordinary rows.
pub struct TreeViewProps {
	CommonProps
pub mut:
	row_height            f64 = 36
	spacing               f64 = 2
	indent                f64 = 24
	disclosure_width      f64 = 28
	row_background        u32 = 0xffffff
	row_corner_radius     f64 = 4
	selected_background   u32 = 0xdbeafe
	disclosure_background u32 = 0xffffff
	selected_color        u32 = 0x1d4ed8
	disclosure_color      u32 = 0x64748b
}

pub fn (p TreeViewProps) vml_container() {}

pub fn (p TreeViewProps) build(ctx VmlBuildContext) !Element {
	config := TreeViewConfig{
		id:                    ctx.id
		frame:                 ctx.frame
		row_height:            p.row_height
		spacing:               p.spacing
		indent:                p.indent
		disclosure_width:      p.disclosure_width
		row_box:               vml_header_box(p.row_background, p.row_corner_radius)
		selected_row_box:      vml_header_box(p.selected_background, p.row_corner_radius)
		disclosure_box:        vml_header_box(p.disclosure_background, p.row_corner_radius)
		text_style:            TextStyle{
			color: 0x334155
			size:  14
		}
		selected_text_style:   TextStyle{
			color: p.selected_color
			size:  14
			bold:  true
		}
		disclosure_text_style: vml_header_text(p.disclosure_color, 14, false)
		nodes:                 vml_tree_nodes(ctx.children, 'TreeView')!
	}
	styled := if p.style != StylePatch{} { style_tree_view(config, p.style)! } else { config }
	return vml_keyed(tree_view(styled)!, ctx)
}

// TreeNodeProps is one row of a TreeView; `title` is the older spelling of
// `text`. on_select runs from the row, on_toggle from its disclosure button.
pub struct TreeNodeProps {
	CommonProps
pub mut:
	text      ?DisplayText
	title     ?string
	expanded  bool
	selected  bool
	on_select ElementCallback = unsafe { nil }
	on_toggle ElementCallback = unsafe { nil }
}

pub fn (p TreeNodeProps) vml_container() {}

fn (p TreeNodeProps) node(ctx VmlBuildContext) !TreeViewNode {
	return TreeViewNode{
		id:        ctx.id
		text:      if text := p.text { text.str() } else { p.title or { '' } }
		on_event:  p.on_select
		on_toggle: p.on_toggle
		expanded:  p.expanded
		selected:  p.selected
		enabled:   p.enabled or { true }
		children:  vml_tree_nodes(ctx.children, 'TreeNode')!
	}
}

pub fn (p TreeNodeProps) build(ctx VmlBuildContext) !Element {
	return Element{
		...vml_keyed(view(vml_view_id(ctx.id, '__record'), ctx.frame, BoxStyle{}, ctx.children),
			ctx)
		compiled_metadata: &CompiledVmlMetadata{
			tree: p.node(ctx)!
		}
	}
}

pub fn (p TreeNodeProps) part(ctx VmlBuildContext) !VmlPart {
	return p.node(ctx)!
}
