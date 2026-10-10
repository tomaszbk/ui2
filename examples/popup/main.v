module main

import ui2

const popup_width = 460
const popup_height = 340

pub struct PopupDemo {
pub mut:
	editing bool
	name    string = 'Ada'
}

pub fn (mut app PopupDemo) open_editor() {
	app.editing = true
}

pub fn (mut app PopupDemo) close_editor() {
	app.editing = false
}

pub fn (mut app PopupDemo) save_editor() {
	app.editing = false
}

fn main() {
	mut app := PopupDemo{}
	ui2.run_compiled_vml[PopupDemo](
		build:  build_popup
		model:  &app
		title:  'Popup'
		width:  popup_width
		height: popup_height
	) or { panic(err) }
}

fn build_popup(mut app PopupDemo) ui2.Element {
	return $vml('popup.vml')
}

fn popup_tree(mut app PopupDemo, frame ui2.Rect) ui2.Element {
	return $vml('popup.vml', frame)
}
