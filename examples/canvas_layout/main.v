module main

import ui2

const canvas_layout_width = 900
const canvas_layout_height = 660
const canvas_sheet_root_x = 34.0
const canvas_sheet_root_y = 100.0
const canvas_sheet_height = 760.0
const canvas_tile_width = 150.0
const canvas_tile_height = 70.0

pub struct CanvasNote {
pub:
	id    int
	key   string
	label string
	x     f64
	y     f64
}

@[heap]
pub struct CanvasLayoutDemo {
pub mut:
	tile_x       f64    = 24
	tile_y       f64    = 24
	theme        string = 'Classic'
	tile_color   u32    = u32(0xe2e8f0)
	tile_text    u32    = u32(0x0f172a)
	pointer_text string = '(0, 0)'
	menu_hidden  bool   = true
	menu_label   string = 'Show menu'
	notes        []CanvasNote
	text         string = 'A canvas places every child at its own\ncoordinates, so this text area keeps its\nspot while the sheet scrolls.'
	status       string = 'Drag the tile, or drag the sheet to read canvas coordinates.'
mut:
	next_note int = 1
	grab_x    f64
	grab_y    f64
}

const canvas_layout_state = &CanvasLayoutDemo{}

fn canvas_theme_colors(theme string) (u32, u32) {
	return match theme {
		'Blue' { u32(0x1d4ed8), u32(0xffffff) }
		'Red' { u32(0xb91c1c), u32(0xffffff) }
		'Green' { u32(0x15803d), u32(0xffffff) }
		'Slate' { u32(0x334155), u32(0xffffff) }
		else { u32(0xe2e8f0), u32(0x0f172a) }
	}
}

pub fn (mut app CanvasLayoutDemo) apply_theme(theme string) {
	app.theme = theme
	app.tile_color, app.tile_text = canvas_theme_colors(theme)
	app.status = '${theme} theme applied to the movable tile.'
}

// canvas_sheet_point converts a root-view pointer position into sheet
// coordinates. The sheet scrolls, so its origin moves with the viewport.
fn canvas_sheet_point(x f64, y f64, scroll f64) (f64, f64) {
	return x - canvas_sheet_root_x, y - canvas_sheet_root_y + scroll
}

pub fn (mut app CanvasLayoutDemo) track_pointer(x f64, y f64, scroll f64) {
	sheet_x, sheet_y := canvas_sheet_point(x, y, scroll)
	app.pointer_text = '(${int(sheet_x)}, ${int(sheet_y)})'
}

pub fn (mut app CanvasLayoutDemo) grab_tile(x f64, y f64, scroll f64) {
	sheet_x, sheet_y := canvas_sheet_point(x, y, scroll)
	app.grab_x = sheet_x - app.tile_x
	app.grab_y = sheet_y - app.tile_y
}

pub fn (mut app CanvasLayoutDemo) drag_tile(x f64, y f64, scroll f64, sheet_width f64) {
	sheet_x, sheet_y := canvas_sheet_point(x, y, scroll)
	max_x := sheet_width - canvas_tile_width - 20
	max_y := canvas_sheet_height - canvas_tile_height - 20
	app.tile_x = clamp_canvas(sheet_x - app.grab_x, 20, max_x)
	app.tile_y = clamp_canvas(sheet_y - app.grab_y, 20, max_y)
	app.pointer_text = '(${int(sheet_x)}, ${int(sheet_y)})'
	app.status = 'Tile at (${int(app.tile_x)}, ${int(app.tile_y)}).'
}

fn clamp_canvas(value f64, low f64, high f64) f64 {
	if high < low {
		return low
	}
	if value < low {
		return low
	}
	return if value > high { high } else { value }
}

pub fn (mut app CanvasLayoutDemo) reset_tile() {
	app.tile_x = 24
	app.tile_y = 24
	app.status = 'Tile returned to the top left of the sheet.'
}

pub fn (mut app CanvasLayoutDemo) add_note() {
	id := app.next_note
	app.notes << CanvasNote{
		id:    id
		key:   'note-${id}'
		label: 'Note ${id}'
		// Notes walk down the sheet in a fixed pattern, so a rebuild puts every
		// keyed card back where it was.
		x:     24 + f64((id - 1) % 3) * 150
		y:     300 + f64((id - 1) / 3) * 90
	}
	app.next_note++
	app.status = 'Added note ${id}; the sheet keeps growing past the viewport.'
}

pub fn (mut app CanvasLayoutDemo) clear_notes() {
	app.notes = []
	app.status = 'Notes cleared.'
}

pub fn (mut app CanvasLayoutDemo) toggle_menu() {
	app.menu_hidden = !app.menu_hidden
	app.menu_label = if app.menu_hidden { 'Show menu' } else { 'Hide menu' }
	app.status = if app.menu_hidden { 'Menu hidden.' } else { 'Menu shown on the sheet.' }
}

pub fn (mut app CanvasLayoutDemo) choose_menu_item(title string) {
	app.status = 'Menu item: ${title}.'
}

fn canvas_sheet_width(frame ui2.Rect) f64 {
	return frame.width - 68.0
}

fn canvas_layout_callbacks() map[string]ui2.ElementCallback {
	return {
		'theme_dropdown': fn (event ui2.ElementEvent) {
			mut state := unsafe { canvas_layout_state }
			state.apply_theme(event.text)
			ui2.refresh()
		}
		'reset_tile':     fn (_event ui2.ElementEvent) {
			mut state := unsafe { canvas_layout_state }
			state.reset_tile()
			ui2.refresh()
		}
		'add_note':       fn (_event ui2.ElementEvent) {
			mut state := unsafe { canvas_layout_state }
			state.add_note()
			ui2.refresh()
		}
		'clear_notes':    fn (_event ui2.ElementEvent) {
			mut state := unsafe { canvas_layout_state }
			state.clear_notes()
			ui2.refresh()
		}
		'toggle_menu':    fn (_event ui2.ElementEvent) {
			mut state := unsafe { canvas_layout_state }
			state.toggle_menu()
			ui2.refresh()
		}
		'menu_delete':    fn (_event ui2.ElementEvent) {
			mut state := unsafe { canvas_layout_state }
			state.choose_menu_item('Delete all users')
			ui2.refresh()
		}
		'menu_export':    fn (_event ui2.ElementEvent) {
			mut state := unsafe { canvas_layout_state }
			state.choose_menu_item('Export users')
			ui2.refresh()
		}
		'menu_exit':      fn (_event ui2.ElementEvent) {
			mut state := unsafe { canvas_layout_state }
			state.choose_menu_item('Exit')
			ui2.refresh()
		}
		'about':          fn (_event ui2.ElementEvent) {
			ui2.alert('Canvas layout', 'Built with V UI')
			ui2.refresh()
		}
		'canvas_tile':    fn (event ui2.ElementEvent) {
			mut state := unsafe { canvas_layout_state }
			scroll := ui2.scroll_offset('canvas')
			match event.kind {
				.pointer_down { state.grab_tile(event.x, event.y, scroll) }
				.pointer_drag, .pointer_up {
					state.drag_tile(event.x, event.y, scroll, canvas_sheet_width(ui2.bounds()))
				}
				else {}
			}
			ui2.refresh()
		}
		'canvas_sheet':   fn (event ui2.ElementEvent) {
			mut state := unsafe { canvas_layout_state }
			if event.kind in [.pointer_down, .pointer_drag, .pointer_up] {
				state.track_pointer(event.x, event.y, ui2.scroll_offset('canvas'))
			}
			ui2.refresh()
		}
	}
}

fn main() {
	ui2.run_compiled_vml[CanvasLayoutDemo](
		build:  build_canvas_layout
		model:  canvas_layout_state
		title:  'Canvas Layout'
		width:  canvas_layout_width
		height: canvas_layout_height
	) or { panic(err) }
}

fn build_canvas_layout(mut app CanvasLayoutDemo) ui2.Element {
	callbacks := canvas_layout_callbacks()
	callback_theme_dropdown := callbacks['theme_dropdown'] or { panic('missing theme_dropdown callback') }
	callback_about := callbacks['about'] or { panic('missing about callback') }
	callback_clear_notes := callbacks['clear_notes'] or { panic('missing clear_notes callback') }
	callback_add_note := callbacks['add_note'] or { panic('missing add_note callback') }
	callback_reset_tile := callbacks['reset_tile'] or { panic('missing reset_tile callback') }
	callback_toggle_menu := callbacks['toggle_menu'] or { panic('missing toggle_menu callback') }
	callback_canvas_sheet := callbacks['canvas_sheet'] or { panic('missing canvas_sheet callback') }
	callback_menu_delete := callbacks['menu_delete'] or { panic('missing menu_delete callback') }
	callback_menu_export := callbacks['menu_export'] or { panic('missing menu_export callback') }
	callback_menu_exit := callbacks['menu_exit'] or { panic('missing menu_exit callback') }
	callback_canvas_tile := callbacks['canvas_tile'] or { panic('missing canvas_tile callback') }
	return $vml('canvas_layout.vml')
}

fn canvas_layout_tree(mut app CanvasLayoutDemo, frame ui2.Rect) ui2.Element {
	callbacks := canvas_layout_callbacks()
	callback_theme_dropdown := callbacks['theme_dropdown'] or { panic('missing theme_dropdown callback') }
	callback_about := callbacks['about'] or { panic('missing about callback') }
	callback_clear_notes := callbacks['clear_notes'] or { panic('missing clear_notes callback') }
	callback_add_note := callbacks['add_note'] or { panic('missing add_note callback') }
	callback_reset_tile := callbacks['reset_tile'] or { panic('missing reset_tile callback') }
	callback_toggle_menu := callbacks['toggle_menu'] or { panic('missing toggle_menu callback') }
	callback_canvas_sheet := callbacks['canvas_sheet'] or { panic('missing canvas_sheet callback') }
	callback_menu_delete := callbacks['menu_delete'] or { panic('missing menu_delete callback') }
	callback_menu_export := callbacks['menu_export'] or { panic('missing menu_export callback') }
	callback_menu_exit := callbacks['menu_exit'] or { panic('missing menu_exit callback') }
	callback_canvas_tile := callbacks['canvas_tile'] or { panic('missing canvas_tile callback') }
	return $vml('canvas_layout.vml', frame)
}
