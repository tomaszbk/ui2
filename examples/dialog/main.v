module main

import ui2

const dialog_width = 460
const dialog_height = 340

pub struct DialogDemo {
pub mut:
	confirming bool
	status     string = 'No pending action.'
}

pub fn (mut app DialogDemo) open_confirmation() {
	app.confirming = true
	app.status = 'Waiting for confirmation.'
}

pub fn (mut app DialogDemo) close_confirmation() {
	app.confirming = false
	app.status = 'Action cancelled.'
}

pub fn (mut app DialogDemo) confirm() {
	app.confirming = false
	app.status = 'Action confirmed.'
}

fn main() {
	mut app := DialogDemo{}
	ui2.run_compiled_vml[DialogDemo](
		build:  build_dialog
		model:  &app
		title:  'Dialog'
		width:  dialog_width
		height: dialog_height
	) or { panic(err) }
}

fn build_dialog(mut app DialogDemo) ui2.Element {
	return $vml('dialog.vml')
}

fn dialog_tree(mut app DialogDemo, frame ui2.Rect) ui2.Element {
	return $vml('dialog.vml', frame)
}
