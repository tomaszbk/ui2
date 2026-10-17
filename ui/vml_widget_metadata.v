module ui2

// Declaration-only records connect VML's typed child declarations to existing
// composite control APIs. They are not an AST, model or runtime evaluator.
@[heap]
pub struct CompiledVmlMetadata {
pub:
	accordion ?AccordionItem
	tab       ?TabbedPanelTab
	tree      ?TreeViewNode
	screen    ?ManagedScreen
	// A MenuBar or Menu document carries its application menus; see menus().
	menu_document bool
	menus         []Menu
}
