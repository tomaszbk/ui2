module main

// vml: profile_dialog.vml

import ui2

const profile_dialog_width = 460
const profile_dialog_height = 340

pub struct ProfileDialogDemo {
pub mut:
	editing bool
	name    string = 'Ada'
}

pub fn (mut app ProfileDialogDemo) open_editor() {
	app.editing = true
}

pub fn (mut app ProfileDialogDemo) close_editor() {
	app.editing = false
}

pub fn (mut app ProfileDialogDemo) save_editor() {
	app.editing = false
}

fn main() {
	mut app := ProfileDialogDemo{}
	ui2.run_compiled_vml[ProfileDialogDemo](
		build:  build_profile_dialog
		model:  &app
		title:  'Profile Dialog'
		width:  profile_dialog_width
		height: profile_dialog_height
	) or { panic(err) }
}

fn build_profile_dialog(mut app ProfileDialogDemo) ui2.Element {
	return profile_dialog_vml(mut app)
}

fn profile_dialog_tree(mut app ProfileDialogDemo, frame ui2.Rect) ui2.Element {
	return profile_dialog_vml_framed(mut app, frame)
}
