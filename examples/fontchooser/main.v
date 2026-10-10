// ui2 profiles: custom (custom font family)
module main

import ui2

const fontchooser_width = 720
const fontchooser_height = 460

pub struct FontChooserDemo {
pub mut:
	font_choice  string = 'System'
	font_family  string
	size_choice  string = '30'
	font_size    f64    = 30
	color_choice string = 'Red'
	text_color   u32    = u32(0xb91c1c)
	bold         bool   = true
	italic       bool
	text         string = 'il était une fois V ....\nLa vie est belle...'
	status       string = 'System, 30 pt, red'
}

pub fn (mut app FontChooserDemo) style_changed() {
	app.font_family = match app.font_choice {
		'Serif' { 'Times New Roman' }
		'Monospace' { 'Courier New' }
		'Arial' { 'Arial' }
		else { '' }
	}
	app.font_size = app.size_choice.f64()
	app.text_color = match app.color_choice {
		'Blue' { u32(0x1d4ed8) }
		'Green' { u32(0x15803d) }
		'Purple' { u32(0x7e22ce) }
		else { u32(0xb91c1c) }
	}
	app.status = '${app.font_choice}, ${app.size_choice} pt, ${app.color_choice.to_lower()}'
}

pub fn (mut app FontChooserDemo) reset_style() {
	app.font_choice = 'System'
	app.font_family = ''
	app.size_choice = '30'
	app.font_size = 30
	app.color_choice = 'Red'
	app.text_color = u32(0xb91c1c)
	app.bold = true
	app.italic = false
	app.status = 'System, 30 pt, red'
}

fn main() {
	mut app := FontChooserDemo{}
	ui2.run_compiled_vml[FontChooserDemo](
		build:  build_fontchooser
		model:  &app
		title:  'Font Chooser'
		width:  fontchooser_width
		height: fontchooser_height
	) or {
		panic(err)
	}
}

fn build_fontchooser(mut app FontChooserDemo) ui2.Element {
	return $vml('fontchooser.vml')
}

fn fontchooser_tree(mut app FontChooserDemo, frame ui2.Rect) ui2.Element {
	return $vml('fontchooser.vml', frame)
}
