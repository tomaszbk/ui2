module main

import ui2

const text_input_width = 430
const text_input_height = 300

pub struct TextInputDemo {
pub mut:
	title string = 'Draft'
	notes string = 'Unicode, selection, clipboard, and undo are handled by the native editor.'
	saved string
}

pub fn (mut app TextInputDemo) save() {
	app.saved = app.title
}

fn main() {
	mut app := TextInputDemo{}
	ui2.run_compiled_vml[TextInputDemo](
		build:  build_text_input
		model:  &app
		title:  'Text Input'
		width:  text_input_width
		height: text_input_height
	) or { panic(err) }
}

fn build_text_input(mut app TextInputDemo) ui2.Element {
	return $vml('text_input.vml')
}

fn text_input_tree(mut app TextInputDemo, frame ui2.Rect) ui2.Element {
	return $vml('text_input.vml', frame)
}
