module ui2

// Menus: MenuItem rows and separators. A MenuItem under an element is a
// context-menu entry of that element (Element.menu); under Menu or MenuItem it
// is an application menu row. A MenuBar (or a single Menu) document builds an
// element carrying the menus; menus(el) reads them back.

pub struct MenuItemProps {
pub mut:
	text      DisplayText = ''
	title     ?string
	shortcut  string
	checked   bool
	enabled   bool = true
	separator bool
	on_click  ElementCallback = unsafe { nil }
}

pub fn (p MenuItemProps) part(ctx VmlBuildContext) !VmlPart {
	return MenuItem{
		id:        ctx.id
		on_select: p.on_click
		title:     p.title or { p.text.str() }
		shortcut:  p.shortcut
		checked:   p.checked
		enabled:   p.enabled
		separator: p.separator
		items:     ctx.menu_items()
	}
}

pub struct MenuSeparatorProps {}

pub fn (p MenuSeparatorProps) part(ctx VmlBuildContext) !VmlPart {
	return menu_separator()
}

pub struct MenuProps {
pub mut:
	text  DisplayText = ''
	title ?string
}

fn (p MenuProps) menu(ctx VmlBuildContext) Menu {
	return Menu{
		title: p.title or { p.text.str() }
		items: ctx.menu_items()
	}
}

pub fn (p MenuProps) part(ctx VmlBuildContext) !VmlPart {
	return p.menu(ctx)
}

// A Menu document root is a menu bar with that one menu.
pub fn (p MenuProps) build(ctx VmlBuildContext) !Element {
	return vml_menu_document(ctx, [p.menu(ctx)])
}

pub fn (p MenuProps) validate() ! {}

pub fn (p MenuProps) project(el Element, ctx VmlBuildContext) !Element {
	return el
}

pub struct MenuBarProps {}

pub fn (p MenuBarProps) build(ctx VmlBuildContext) !Element {
	return vml_menu_document(ctx, ctx.menus())
}

pub fn (p MenuBarProps) validate() ! {}

pub fn (p MenuBarProps) project(el Element, ctx VmlBuildContext) !Element {
	return el
}

fn vml_menu_document(ctx VmlBuildContext, document []Menu) !Element {
	validate_menus(document)!
	return Element{
		kind:              .view
		id:                ctx.id
		key:               ctx.key
		frame:             ctx.frame
		compiled_metadata: &CompiledVmlMetadata{
			menu_document: true
			menus:         document
		}
	}
}

// menus returns the application menus of a MenuBar or Menu document.
pub fn menus(el Element) ![]Menu {
	if el.compiled_metadata == unsafe { nil } || !el.compiled_metadata.menu_document {
		return error('element is not a VML menu document')
	}
	return el.compiled_metadata.menus
}
