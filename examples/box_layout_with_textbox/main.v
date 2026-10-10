module main

import ui2

const box_textbox_width = 560
const box_textbox_height = 400

pub struct BoxLayoutTextboxDemo {
pub mut:
	text   string
	status string
}

fn initial_box_layout_textbox() BoxLayoutTextboxDemo {
	return BoxLayoutTextboxDemo{
		text:   'blah blah blah\n'.repeat(10).trim_right('\n')
		status: 'Edit the yellow text area, or show the original message.'
	}
}

pub fn (mut app BoxLayoutTextboxDemo) text_changed() {
	lines := if app.text.len == 0 { 0 } else { app.text.split_into_lines().len }
	app.status = '${lines} lines, ${app.text.runes().len} characters'
}

pub fn (mut app BoxLayoutTextboxDemo) show_message() {
	app.status = 'coucou toto!'
}

fn main() {
	mut app := initial_box_layout_textbox()
	ui2.run_compiled_vml[BoxLayoutTextboxDemo](
		build:  build_box_layout_with_textbox
		model:  &app
		title:  'Box Layout with Textbox'
		width:  box_textbox_width
		height: box_textbox_height
	) or {
		panic(err)
	}
}

fn build_box_layout_with_textbox(mut app BoxLayoutTextboxDemo) ui2.Element {
	return $vml('box_layout_with_textbox.vml')
}

fn box_layout_with_textbox_tree(mut app BoxLayoutTextboxDemo, frame ui2.Rect) ui2.Element {
	return $vml('box_layout_with_textbox.vml', frame)
}
