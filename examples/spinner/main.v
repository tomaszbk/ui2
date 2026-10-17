module main

import ui2

// The loading Spinner: a turning three-quarter ring in three sizes, and the
// same ring in a loading Button while a save runs.

const spinner_width = 360
const spinner_height = 260

pub struct SpinnerDemo {
pub mut:
	saving bool
	status string = 'Idle'
}

pub fn (mut app SpinnerDemo) save() {
	app.saving = true
	app.status = 'Saving changes'
}

pub fn (mut app SpinnerDemo) finish() {
	app.saving = false
	app.status = 'Saved'
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
