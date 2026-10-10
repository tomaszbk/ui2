module main

import ui2

const rgb_color_width = 380
const rgb_color_height = 330

pub struct RgbColorDemo {
pub mut:
	red           string = '128'
	green         string = '128'
	blue          string = '128'
	preview_color u32    = u32(0x808080)
	valid         bool   = true
	message       string = 'rgb(128, 128, 128)'
}

fn rgb_component(value string) ?int {
	trimmed := value.trim_space()
	if trimmed.len == 0 {
		return none
	}
	for character in trimmed {
		if character < `0` || character > `9` {
			return none
		}
	}
	component := trimmed.int()
	if component < 0 || component > 255 {
		return none
	}
	return component
}

pub fn (mut app RgbColorDemo) update_color() {
	r := rgb_component(app.red) or {
		app.valid = false
		app.preview_color = u32(0xffffff)
		app.message = 'RGB values must be between 0 and 255.'
		return
	}
	g := rgb_component(app.green) or {
		app.valid = false
		app.preview_color = u32(0xffffff)
		app.message = 'RGB values must be between 0 and 255.'
		return
	}
	b := rgb_component(app.blue) or {
		app.valid = false
		app.preview_color = u32(0xffffff)
		app.message = 'RGB values must be between 0 and 255.'
		return
	}
	app.valid = true
	app.preview_color = (u32(r) << 16) | (u32(g) << 8) | u32(b)
	app.message = 'rgb(${r}, ${g}, ${b})'
}

pub fn (mut app RgbColorDemo) show_color() {
	app.update_color()
}

fn main() {
	mut app := RgbColorDemo{}
	ui2.run_compiled_vml[RgbColorDemo](
		build:  build_rgb_color
		model:  &app
		title:  'RGB Color'
		width:  rgb_color_width
		height: rgb_color_height
	) or { panic(err) }
}

fn build_rgb_color(mut app RgbColorDemo) ui2.Element {
	return $vml('rgb_color.vml')
}

fn rgb_color_tree(mut app RgbColorDemo, frame ui2.Rect) ui2.Element {
	return $vml('rgb_color.vml', frame)
}
