module main

import math
import ui2

const colorbox_width = 760
const colorbox_height = 580
const hue_bands = 32
const sv_side = 16
const swatch_columns = 2
const swatch_rows = 3
// The picker is a fixed-size instrument, so its origin in the window never
// moves and pointer positions convert with plain constants.
const hue_root_y = 76.0
const picker_side = 256.0
const sv_root_x = 78.0
const sv_root_y = 76.0
const swatch_root_x = 348.0
const swatch_root_y = 76.0
const swatch_cell_w = 74.0
const swatch_cell_h = 37.0
const swatch_gap = 6.0

pub struct HueCell {
pub:
	key   string
	index int
	color u32
}

pub struct SvCell {
pub:
	key    string
	column int
	row    int
	color  u32
}

pub struct Swatch {
pub:
	key    string
	index  int
	column int
	row    int
pub mut:
	color    u32
	selected bool
}

@[heap]
pub struct ColorBoxDemo {
pub mut:
	hue         f64
	saturation  f64 = 0.75
	value       f64 = 0.75
	red         int
	green       int
	blue        int
	red_text    string
	green_text  string
	blue_text   string
	valid       bool = true
	color       u32
	hue_color   u32
	hue_marker  f64
	sv_marker_x f64
	sv_marker_y f64
	hue_cells   []HueCell
	sv_cells    []SvCell
	swatches    []Swatch
	status      string = 'Drag the hue strip and the square, or type RGB values.'
}

const colorbox_state = &ColorBoxDemo{}

// hsv_to_rgb and rgb_to_hsv are the same round trip the original colorbox
// component performs between its canvases and its three numeric text boxes.
fn hsv_to_rgb(hue f64, saturation f64, value f64) (int, int, int) {
	sector := int(hue / 60.0) % 6
	fraction := hue / 60.0 - math.floor(hue / 60.0)
	p := value * (1.0 - saturation)
	q := value * (1.0 - fraction * saturation)
	t := value * (1.0 - (1.0 - fraction) * saturation)
	mut red, mut green, mut blue := value, t, p
	match sector {
		1 {
			red, green, blue = q, value, p
		}
		2 {
			red, green, blue = p, value, t
		}
		3 {
			red, green, blue = p, q, value
		}
		4 {
			red, green, blue = t, p, value
		}
		5 {
			red, green, blue = value, p, q
		}
		else {}
	}
	return int(math.round(red * 255)), int(math.round(green * 255)), int(math.round(blue * 255))
}

fn rgb_to_hsv(red int, green int, blue int) (f64, f64, f64) {
	r := f64(red) / 255.0
	g := f64(green) / 255.0
	b := f64(blue) / 255.0
	high := math.max(r, math.max(g, b))
	low := math.min(r, math.min(g, b))
	span := high - low
	mut hue := 0.0
	if span > 0 {
		hue = if high == r {
			60.0 * (((g - b) / span) + if g < b { 6.0 } else { 0.0 })
		} else if high == g {
			60.0 * ((b - r) / span + 2.0)
		} else {
			60.0 * ((r - g) / span + 4.0)
		}
	}
	saturation := if high == 0 { 0.0 } else { span / high }
	return hue, saturation, high
}

fn hex_color(red int, green int, blue int) u32 {
	return (u32(red) << 16) | (u32(green) << 8) | u32(blue)
}

fn clamp_unit(value f64) f64 {
	return math.max(0.0, math.min(1.0, value))
}

fn colorbox_demo() ColorBoxDemo {
	mut app := ColorBoxDemo{
		hue_cells: hue_strip_cells()
	}
	for index in 0 .. swatch_columns * swatch_rows {
		hue := f64(index) * 360.0 / f64(swatch_columns * swatch_rows)
		red, green, blue := hsv_to_rgb(hue, 0.65, 0.9)
		app.swatches << Swatch{
			key:      'swatch-${index}'
			index:    index
			column:   index % swatch_columns
			row:      index / swatch_columns
			color:    hex_color(red, green, blue)
			selected: index == 0
		}
	}
	app.sync()
	return app
}

// hue_strip_cells never changes: the strip always shows the whole circle at
// full saturation and value, and only the marker over it moves.
fn hue_strip_cells() []HueCell {
	mut cells := []HueCell{cap: hue_bands}
	for index in 0 .. hue_bands {
		hue := f64(index) * 360.0 / f64(hue_bands)
		red, green, blue := hsv_to_rgb(hue, 1.0, 1.0)
		cells << HueCell{
			key:   'hue-${index}'
			index: index
			color: hex_color(red, green, blue)
		}
	}
	return cells
}

// sync rebuilds everything that is derived from the current hue, saturation,
// and value: the square's tiles, the marker positions, and the RGB read-outs.
fn (mut app ColorBoxDemo) sync() {
	app.sv_cells = []SvCell{cap: sv_side * sv_side}
	for row in 0 .. sv_side {
		for column in 0 .. sv_side {
			saturation := (f64(column) + 0.5) / f64(sv_side)
			value := 1.0 - (f64(row) + 0.5) / f64(sv_side)
			red, green, blue := hsv_to_rgb(app.hue, saturation, value)
			app.sv_cells << SvCell{
				key:    'sv-${row}-${column}'
				column: column
				row:    row
				color:  hex_color(red, green, blue)
			}
		}
	}
	app.red, app.green, app.blue = hsv_to_rgb(app.hue, app.saturation, app.value)
	app.red_text = app.red.str()
	app.green_text = app.green.str()
	app.blue_text = app.blue.str()
	app.color = hex_color(app.red, app.green, app.blue)
	hue_red, hue_green, hue_blue := hsv_to_rgb(app.hue, 1.0, 1.0)
	app.hue_color = hex_color(hue_red, hue_green, hue_blue)
	app.hue_marker = app.hue / 360.0 * picker_side
	app.sv_marker_x = app.saturation * picker_side
	app.sv_marker_y = (1.0 - app.value) * picker_side
	app.valid = true
}

pub fn (mut app ColorBoxDemo) set_hue(hue f64) {
	app.hue = math.max(0.0, math.min(359.999, hue))
	app.sync()
	app.status = 'Hue ${int(app.hue)}° · #${app.color:06X}'
}

pub fn (mut app ColorBoxDemo) set_saturation_value(saturation f64, value f64) {
	app.saturation = clamp_unit(saturation)
	app.value = clamp_unit(value)
	app.sync()
	app.status = 'S ${int(app.saturation * 100)}% · V ${int(app.value * 100)}% · #${app.color:06X}'
}

fn parse_channel(text string) ?int {
	trimmed := text.trim_space()
	if trimmed.len == 0 || trimmed.len > 3 {
		return none
	}
	for character in trimmed {
		if !character.is_digit() {
			return none
		}
	}
	channel := trimmed.int()
	return if channel > 255 { none } else { channel }
}

pub fn (mut app ColorBoxDemo) apply_channel(name string, text string) {
	match name {
		'red' {
			app.red_text = text
		}
		'green' {
			app.green_text = text
		}
		else {
			app.blue_text = text
		}
	}
	red := parse_channel(app.red_text) or {
		app.valid = false
		app.status = 'Each channel must be a number between 0 and 255.'
		return
	}
	green := parse_channel(app.green_text) or {
		app.valid = false
		app.status = 'Each channel must be a number between 0 and 255.'
		return
	}
	blue := parse_channel(app.blue_text) or {
		app.valid = false
		app.status = 'Each channel must be a number between 0 and 255.'
		return
	}
	app.hue, app.saturation, app.value = rgb_to_hsv(red, green, blue)
	app.sync()
	app.status = 'RGB(${red}, ${green}, ${blue}) · #${app.color:06X}'
}

fn (app &ColorBoxDemo) selected_slot() int {
	for swatch in app.swatches {
		if swatch.selected {
			return swatch.index
		}
	}
	return 0
}

pub fn (mut app ColorBoxDemo) select_swatch(index int) {
	if index < 0 || index >= app.swatches.len {
		return
	}
	for slot in 0 .. app.swatches.len {
		app.swatches[slot].selected = slot == index
	}
	stored := app.swatches[index].color
	red := int((stored >> 16) & 0xff)
	green := int((stored >> 8) & 0xff)
	blue := int(stored & 0xff)
	app.hue, app.saturation, app.value = rgb_to_hsv(red, green, blue)
	app.sync()
	app.status = 'Recalled slot ${index + 1} · #${app.color:06X}'
}

pub fn (mut app ColorBoxDemo) store_swatch() {
	index := app.selected_slot()
	app.swatches[index].color = app.color
	app.status = 'Stored #${app.color:06X} in slot ${index + 1}.'
}

fn (app &ColorBoxDemo) swatch_at(x f64, y f64) int {
	local_x := x - swatch_root_x
	local_y := y - swatch_root_y
	if local_x < 0 || local_y < 0 {
		return -1
	}
	column := int(local_x / (swatch_cell_w + swatch_gap))
	row := int(local_y / (swatch_cell_h + swatch_gap))
	if column >= swatch_columns || row >= swatch_rows {
		return -1
	}
	// The gap between two slots belongs to neither of them.
	if local_x - f64(column) * (swatch_cell_w + swatch_gap) > swatch_cell_w
		|| local_y - f64(row) * (swatch_cell_h + swatch_gap) > swatch_cell_h {
		return -1
	}
	return row * swatch_columns + column
}

fn colorbox_callbacks() map[string]ui2.ElementCallback {
	return {
		'red_input':   fn (event ui2.ElementEvent) {
			mut state := unsafe { colorbox_state }
			state.apply_channel('red', event.text)
			ui2.refresh()
		}
		'green_input': fn (event ui2.ElementEvent) {
			mut state := unsafe { colorbox_state }
			state.apply_channel('green', event.text)
			ui2.refresh()
		}
		'blue_input':  fn (event ui2.ElementEvent) {
			mut state := unsafe { colorbox_state }
			state.apply_channel('blue', event.text)
			ui2.refresh()
		}
		'store':       fn (_event ui2.ElementEvent) {
			mut state := unsafe { colorbox_state }
			state.store_swatch()
			ui2.refresh()
		}
		'hue_strip':   fn (event ui2.ElementEvent) {
			mut state := unsafe { colorbox_state }
			if event.kind in [.pointer_down, .pointer_drag, .pointer_up] {
				state.set_hue(clamp_unit((event.y - hue_root_y) / picker_side) * 359.999)
			}
			ui2.refresh()
		}
		'sv_square':   fn (event ui2.ElementEvent) {
			mut state := unsafe { colorbox_state }
			if event.kind in [.pointer_down, .pointer_drag, .pointer_up] {
				state.set_saturation_value((event.x - sv_root_x) / picker_side, 1.0 - (event.y - sv_root_y) / picker_side)
			}
			ui2.refresh()
		}
		'swatch_grid': fn (event ui2.ElementEvent) {
			mut state := unsafe { colorbox_state }
			if event.kind == .pointer_up { state.select_swatch(state.swatch_at(event.x, event.y)) }
			ui2.refresh()
		}
	}
}

fn main() {
	mut state := unsafe { colorbox_state }
	unsafe {
		*state = colorbox_demo()
	}
	ui2.run_compiled_vml[ColorBoxDemo](
		build:  build_colorbox
		model:  colorbox_state
		title:  'Color Box'
		width:  colorbox_width
		height: colorbox_height
	) or { panic(err) }
}

fn build_colorbox(mut app ColorBoxDemo) ui2.Element {
	callbacks := colorbox_callbacks()
	callback_store := callbacks['store'] or { panic('missing store callback') }
	callback_hue_strip := callbacks['hue_strip'] or { panic('missing hue_strip callback') }
	callback_sv_square := callbacks['sv_square'] or { panic('missing sv_square callback') }
	callback_swatch_grid := callbacks['swatch_grid'] or { panic('missing swatch_grid callback') }
	callback_red_input := callbacks['red_input'] or { panic('missing red_input callback') }
	callback_green_input := callbacks['green_input'] or { panic('missing green_input callback') }
	callback_blue_input := callbacks['blue_input'] or { panic('missing blue_input callback') }
	return $vml('colorbox.vml')
}

fn colorbox_tree(mut app ColorBoxDemo, frame ui2.Rect) ui2.Element {
	callbacks := colorbox_callbacks()
	callback_store := callbacks['store'] or { panic('missing store callback') }
	callback_hue_strip := callbacks['hue_strip'] or { panic('missing hue_strip callback') }
	callback_sv_square := callbacks['sv_square'] or { panic('missing sv_square callback') }
	callback_swatch_grid := callbacks['swatch_grid'] or { panic('missing swatch_grid callback') }
	callback_red_input := callbacks['red_input'] or { panic('missing red_input callback') }
	callback_green_input := callbacks['green_input'] or { panic('missing green_input callback') }
	callback_blue_input := callbacks['blue_input'] or { panic('missing blue_input callback') }
	return $vml('colorbox.vml', frame)
}

pub fn (app &ColorBoxDemo) display_color() string {
	return '#${app.color:06X}'
}
