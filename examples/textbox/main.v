module main

import ui2

const textbox_width = 640
const textbox_height = 430

pub struct TextboxDemo {
pub mut:
	title        string = 'Release notes'
	notes        string = 'Type multiline text here.\nThe preview stays read-only.'
	show_preview bool   = true
	status       string = '54 characters'
}

pub fn (mut app TextboxDemo) update_status() {
	app.status = '${app.notes.runes().len} characters'
}

pub fn (mut app TextboxDemo) clear() {
	app.notes = ''
	app.update_status()
}

fn main() {
	mut app := TextboxDemo{}
	ui2.run_compiled_vml[TextboxDemo](
		build:  build_textbox
		model:  &app
		title:  'Textbox Demo'
		width:  textbox_width
		height: textbox_height
	) or { panic(err) }
}

fn build_textbox(mut app TextboxDemo) ui2.Element {
	return $vml('textbox.vml')
}

fn textbox_tree(mut app TextboxDemo, frame ui2.Rect) ui2.Element {
	return $vml('textbox.vml', frame)
}
