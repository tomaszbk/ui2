module main

import ui2

fn preview_toolbar_height(app &IdeApp) f64 {
	return if app.active_tab != 'source' { 42.0 } else { 0.0 }
}

fn build_layout_inspector(width f64, app &IdeApp) []ui2.Element {
	mut children := [
		ui2.label('', 'Absolute canvas', ui2.rect(4, 8, width - 8, 22), text_style(11, color_text, true)),
		ui2.label('', 'Controls use parent-local logical coordinates. Preview sizes preserve the saved design. Use Flex, Grid or Stack in source for automatic layout.', ui2.rect(4, 38, width - 8, 110), ui2.TextStyle{ size: 10, color: color_muted, lines: 6 }),
	]
	if component := app.selected_component() {
		children << ui2.Element{
			...ui2.with_event(ui2.checkbox('component_hidden', 'Hidden in preview', component.hidden, ui2.rect(4, 160, width - 8, 24), text_style(10, color_text, false)), ide_action('component_hidden'))
			enabled: app.geometry_editable()
		}
	}
	return children
}

fn build_preview_toolbar(layout IdeLayout, app &IdeApp) []ui2.Element {
	if preview_toolbar_height(app) == 0 { return []ui2.Element{} }
	mut children := []ui2.Element{}
	mut x := 8.0
	for index, title in ['Design size', 'Phone', 'Tablet', 'Desktop', 'Rotate'] {
		id := ['preview_base', 'preview_phone', 'preview_tablet', 'preview_desktop', 'preview_rotate'][index]
		children << tiny_button(id, title, ui2.rect(x, 6, 76, 24), true)
		x += 82
	}
	children << ui2.text_input(
		id:          'preview_width'
		on_event:    ide_preview_size_callback
		placeholder: 'Width'
		text:        '${app.canvas_width():g}'
		frame:       ui2.rect(x + 4, 6, 66, 24)
		box:         ui2.BoxStyle{ bg: 0xffffff }
		text_style:  text_style(10, color_text, false)
		keyboard:    ui2.keyboard_decimal
		multiline:   false
	) or { panic(err) }
	children << ui2.label('', 'x', ui2.rect(x + 76, 9, 12, 18), text_style(10, color_muted, false))
	children << ui2.text_input(
		id:          'preview_height'
		on_event:    ide_preview_size_callback
		placeholder: 'Height'
		text:        '${app.canvas_height():g}'
		frame:       ui2.rect(x + 90, 6, 66, 24)
		box:         ui2.BoxStyle{ bg: 0xffffff }
		text_style:  text_style(10, color_text, false)
		keyboard:    ui2.keyboard_decimal
		multiline:   false
	) or { panic(err) }
	children << tiny_button('preview_size', 'Apply size', ui2.rect(x + 164, 6, 76, 24), true)
	children << tiny_button('preview_check', 'Check layout', ui2.rect(x + 248, 6, 90, 24), true)
	return [ui2.scroll('preview_toolbar', ui2.rect(layout.stage.x, layout.stage.y, layout.stage.width, 38), color_panel_alt, children)]
}
