module ui2

// IconName lists GPUI Kit's Lucide icon names that have a counterpart the
// renderer can draw: an SF Symbols name that ui/symbols.v maps to a Material
// Icons glyph of the same meaning. The first group is from GPUI's default
// component set, the second from the wider Lucide catalog, the third the
// glyphs the kit's own controls draw. `none` draws nothing; `padlock` is
// Lucide's Lock, which is a V keyword.
pub enum IconName {
	none
	a_large_small
	case_sensitive
	chevrons_up_down
	circle_user
	close
	copy
	dash
	delete
	ellipsis
	eye
	eye_off
	folder
	folder_closed
	info
	layout_dashboard
	menu
	minus
	palette
	panel_right
	plus
	redo
	redo_2
	refresh_cw
	rotate_cw
	search
	settings
	settings_2
	star
	undo
	undo_2
	window_close
	window_minimize
	align_justify
	align_left
	align_right
	badge
	book_a
	box
	braces
	chart_column
	clipboard_list
	cloud_download
	cloud_upload
	columns_3
	copy_plus
	crop
	download
	file_plus
	file_up
	hash
	history
	image
	indent_increase
	layers
	layout_grid
	list_ordered
	message_square_text
	mouse_pointer
	move_horizontal
	move_vertical
	padlock
	paintbrush
	pencil
	printer
	repeat
	scissors
	share
	square_function
	square_minus
	square_plus
	table
	tag
	user_round_plus
	users
	arrow_down
	arrow_left
	arrow_right
	arrow_up
	bell
	calendar
	check
	chevron_down
	chevron_left
	chevron_right
	chevron_up
	circle_alert
	circle_check
	circle_x
	trash
	triangle_alert
}

// symbol is the SF Symbol an icon draws as; symbol_known is true for each
// but none, which has no symbol.
pub fn (name IconName) symbol() string {
	return match name {
		.none { '' }
		.a_large_small { 'textformat.size' }
		.case_sensitive { 'textformat' }
		.chevrons_up_down, .move_vertical { 'arrow.up.and.down' }
		.circle_user { 'person.crop.circle' }
		.close, .window_close { 'xmark' }
		.copy { 'doc.on.doc' }
		.dash, .minus, .window_minimize { 'minus' }
		.delete, .trash { 'trash' }
		.ellipsis { 'ellipsis' }
		.eye { 'eye' }
		.eye_off { 'eye.slash' }
		.folder, .folder_closed { 'folder' }
		.info { 'info.circle' }
		.layout_dashboard { 'rectangle.3.group' }
		.menu { 'line.3.horizontal' }
		.palette { 'paintpalette' }
		.panel_right { 'sidebar.right' }
		.plus { 'plus' }
		.redo, .redo_2 { 'arrow.uturn.forward' }
		.refresh_cw, .rotate_cw { 'arrow.clockwise' }
		.search { 'magnifyingglass' }
		.settings { 'gearshape' }
		.settings_2 { 'slider.horizontal.3' }
		.star { 'star' }
		.undo, .undo_2 { 'arrow.uturn.backward' }
		.align_justify { 'text.justify' }
		.align_left { 'text.alignleft' }
		.align_right { 'text.alignright' }
		.badge { 'seal' }
		.book_a { 'character.book.closed' }
		.box { 'cube.transparent' }
		.braces { 'curlybraces' }
		.chart_column { 'chart.bar' }
		.clipboard_list { 'list.bullet.clipboard' }
		.cloud_download { 'icloud.and.arrow.down' }
		.cloud_upload { 'icloud.and.arrow.up' }
		.columns_3 { 'rectangle.split.3x1' }
		.copy_plus { 'plus.square.on.square' }
		.crop { 'crop' }
		.download { 'arrow.down.to.line' }
		.file_plus { 'doc.badge.plus' }
		.file_up { 'doc.badge.arrow.up' }
		.hash { 'number' }
		.history { 'clock.arrow.circlepath' }
		.image { 'photo' }
		.indent_increase { 'increase.indent' }
		.layers { 'square.stack.3d.up' }
		.layout_grid { 'rectangle.grid.2x2' }
		.list_ordered { 'list.number' }
		.message_square_text { 'text.bubble' }
		.mouse_pointer { 'cursorarrow' }
		.move_horizontal { 'arrow.left.and.right' }
		.padlock { 'lock' }
		.paintbrush { 'paintbrush' }
		.pencil { 'pencil' }
		.printer { 'printer' }
		.repeat { 'arrow.2.squarepath' }
		.scissors { 'scissors' }
		.share { 'square.and.arrow.up' }
		.square_function { 'function' }
		.square_minus { 'minus.rectangle' }
		.square_plus { 'plus.rectangle' }
		.table { 'tablecells' }
		.tag { 'tag' }
		.user_round_plus { 'person.crop.circle.badge.plus' }
		.users { 'person.2' }
		.arrow_down { 'arrow.down' }
		.arrow_left { 'arrow.left' }
		.arrow_right { 'arrow.right' }
		.arrow_up { 'arrow.up' }
		.bell { 'bell' }
		.calendar { 'calendar' }
		.check { 'checkmark' }
		.chevron_down { 'chevron.down' }
		.chevron_left { 'chevron.left' }
		.chevron_right { 'chevron.right' }
		.chevron_up { 'chevron.up' }
		.circle_alert { 'exclamationmark.circle' }
		.circle_check { 'checkmark.circle' }
		.circle_x { 'xmark.circle' }
		.triangle_alert { 'exclamationmark.triangle' }
	}
}

// title is the icon's name in words, its default accessibility label.
pub fn (name IconName) title() string {
	if name == .none {
		return ''
	}
	words := name.str().replace('_', ' ')
	return words[..1].to_upper() + words[1..]
}

// icon_names lists every IconName that draws, in declaration order.
pub fn icon_names() []IconName {
	mut names := []IconName{}
	$for value in IconName.values {
		if value.value != .none {
			names << value.value
		}
	}
	return names
}

// icon_pixel_size returns GPUI's icon size for a size preset.
pub fn icon_pixel_size(size ControlSize) f64 {
	return match size {
		.small { 14 }
		.medium { 16 }
		.large { 24 }
	}
}
