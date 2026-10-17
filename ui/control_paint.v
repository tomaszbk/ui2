module ui2

// ControlPaint is the chrome of a control the renderer draws itself: a text
// field or area, a dropdown, a checkbox, a slider, a switch, a button bezel,
// the ambient tooltip and the drawn popup menu. It carries the colors the
// renderer otherwise hard-codes. Kit components set Element.paint from the
// theme (KitTokens.control_paint); an element without paint keeps the
// renderer's defaults.
pub struct ControlPaint {
pub:
	surface       u32 // field fill
	border        u32
	focus_ring    u32
	accent        u32 // checked, on and filled parts
	on_accent     u32 // a check mark or a thumb over accent
	track         u32 // the unfilled track of a slider, the off switch
	text          u32
	placeholder   u32
	disabled_text u32
	popover       u32 // a menu or tooltip surface
	on_popover    u32
	hover         u32 // a highlighted menu row
	radius        f64
	// chrome false leaves out the surface and border, for a field drawn
	// inside a surface of its own (InputGroup).
	chrome bool = true
}
