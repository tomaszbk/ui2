module main

import ui2

const modal_view_width = 460
const modal_view_height = 340

pub struct ModalViewDemo {
pub mut:
	confirming bool
	status     string = 'No pending action.'
}

pub fn (mut app ModalViewDemo) open_confirmation() {
	app.confirming = true
	app.status = 'Waiting for confirmation.'
}

pub fn (mut app ModalViewDemo) close_confirmation() {
	app.confirming = false
	app.status = 'Action cancelled.'
}

pub fn (mut app ModalViewDemo) confirm() {
	app.confirming = false
	app.status = 'Action confirmed.'
}

fn main() {
	mut app := ModalViewDemo{}
	ui2.run_compiled_vml[ModalViewDemo](
		build:  build_modal_view
		model:  &app
		title:  'Modal View'
		width:  modal_view_width
		height: modal_view_height
	) or { panic(err) }
}

fn build_modal_view(mut app ModalViewDemo) ui2.Element {
	return $vml('modal_view.vml')
}

fn modal_view_tree(mut app ModalViewDemo, frame ui2.Rect) ui2.Element {
	return $vml('modal_view.vml', frame)
}
