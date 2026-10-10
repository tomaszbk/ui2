module main

import ui2

const spinner_width = 360
const spinner_height = 190

pub struct SpinnerDemo {
pub mut:
	selection string = 'Home'
	message   string = 'Home selected.'
}

pub fn (mut app SpinnerDemo) selection_changed() {
	app.message = '${app.selection} selected.'
}

fn main() {
	mut app := SpinnerDemo{}
	ui2.run_compiled_vml[SpinnerDemo](
		build:  build_spinner
		model:  &app
		title:  'Spinner'
		width:  spinner_width
		height: spinner_height
	) or { panic(err) }
}

fn build_spinner(mut app SpinnerDemo) ui2.Element {
	return $vml('spinner.vml')
}

fn spinner_tree(mut app SpinnerDemo, frame ui2.Rect) ui2.Element {
	return $vml('spinner.vml', frame)
}
