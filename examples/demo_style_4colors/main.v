module main

import ui2

const style_colors_width = 640
const style_colors_height = 420

pub struct StyleFourColorsDemo {
pub mut:
	palette string = 'Classic'
	color0  u32    = u32(0xffffff)
	color1  u32    = u32(0xe5e7eb)
	color2  u32    = u32(0xbfdbfe)
	color3  u32    = u32(0x111827)
	enabled bool   = true
	status  string = 'Classic palette selected.'
}

pub fn (mut app StyleFourColorsDemo) palette_changed() {
	match app.palette {
		'Ocean' {
			app.color0 = u32(0xf0f9ff)
			app.color1 = u32(0xbae6fd)
			app.color2 = u32(0x0ea5e9)
			app.color3 = u32(0x0c4a6e)
		}
		'Sunset' {
			app.color0 = u32(0xfff7ed)
			app.color1 = u32(0xfed7aa)
			app.color2 = u32(0xf97316)
			app.color3 = u32(0x7c2d12)
		}
		'Forest' {
			app.color0 = u32(0xf0fdf4)
			app.color1 = u32(0xbbf7d0)
			app.color2 = u32(0x22c55e)
			app.color3 = u32(0x14532d)
		}
		else {
			app.palette = 'Classic'
			app.color0 = u32(0xffffff)
			app.color1 = u32(0xe5e7eb)
			app.color2 = u32(0xbfdbfe)
			app.color3 = u32(0x111827)
		}
	}
	app.status = '${app.palette} palette selected.'
}

pub fn (mut app StyleFourColorsDemo) apply_palette() {
	app.status = '${app.palette} palette applied to the preview.'
}

fn main() {
	mut app := StyleFourColorsDemo{}
	ui2.run_compiled_vml[StyleFourColorsDemo](
		build:  build_demo_style_4colors
		model:  &app
		title:  'Four Colors'
		width:  style_colors_width
		height: style_colors_height
	) or { panic(err) }
}

fn build_demo_style_4colors(mut app StyleFourColorsDemo) ui2.Element {
	return $vml('demo_style_4colors.vml')
}

fn demo_style_4colors_tree(mut app StyleFourColorsDemo, frame ui2.Rect) ui2.Element {
	return $vml('demo_style_4colors.vml', frame)
}
