module ui2

// Declaration-only records connect VML's typed child declarations to existing
// composite control APIs. They are not an AST, model or runtime evaluator.
@[heap]
pub struct CompiledVmlMetadata {
	// A styled composite constructor keeps its unstyled root box, which a
	// later style replacement restores (style_progress_bar).
	style_default_box ?BoxStyle
pub:
	accordion ?AccordionItem
	tab       ?TabbedPanelTab
	tree      ?TreeViewNode
	screen    ?ManagedScreen
	// A MenuBar or Menu document carries its application menus; see menus().
	menu_document bool
	menus         []Menu
}

// style_reset_box is the box a style replacement starts from: the unstyled
// root box a composite constructor recorded, or the element's own box.
fn style_reset_box(metadata &CompiledVmlMetadata, box BoxStyle) BoxStyle {
	if metadata == unsafe { nil } { return box }
	return metadata.style_default_box or { box }
}
