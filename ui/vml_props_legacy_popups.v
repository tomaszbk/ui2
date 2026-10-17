module ui2

// Legacy popups: Dropdown with its Option children, and MessageBox, until the
// kit's menus and dialogs replace them.

// DropdownProps selects `text` among its Option children.
pub struct DropdownProps {
	CommonProps
pub mut:
	text DisplayText = ''
}

pub fn (p DropdownProps) build(ctx VmlBuildContext) !Element {
	return vml_handled(dropdown(ctx.id, p.text.str(), ctx.options().map(it.title), ctx.frame,
		BoxStyle{}, TextStyle{}), ctx, p.element_callback())
}

pub fn (mut p DropdownProps) apply_event(event ElementEvent) {
	if event.kind == .change { p.text = event.text }
}

// OptionProps is one choice of a Dropdown or Spinner.
pub struct OptionProps {
pub mut:
	text DisplayText = ''
}

pub fn (p OptionProps) part(ctx VmlBuildContext) !VmlPart {
	title := p.text.str()
	return MenuEntry{
		id:    title
		title: title
	}
}

// MessageBoxProps is the in-window dialog; its Button children are actions.
// The accessibility fields of the overlay stay empty unless authored.
pub struct MessageBoxProps {
	CommonProps
pub mut:
	title         string
	text          DisplayText = ''
	dialog_width  f64         = 300
	dialog_height f64         = 150
}

pub fn (p MessageBoxProps) vml_structure() VmlStructure {
	return .generated
}

pub fn (p MessageBoxProps) build(ctx VmlBuildContext) !Element {
	return vml_handled(custom_message_box(CustomMessageBoxConfig{
		id:      ctx.id
		frame:   ctx.frame
		title:   p.title
		text:    p.text.str()
		hidden:  p.hidden or { false }
		width:   p.dialog_width
		height:  p.dialog_height
		actions: ctx.message_actions()
	}), ctx, p.element_callback())
}
