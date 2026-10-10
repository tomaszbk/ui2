module main

import ui2

const menu_window_width = 680
const menu_window_height = 360

pub struct ResizableMenuDemo {
pub mut:
	compact bool   = true
	status  string = 'Right-click Actions to open its native context menu.'
}

pub fn (mut app ResizableMenuDemo) open_actions() {
	app.status = 'Right-click the button to choose a menu action.'
}

pub fn (mut app ResizableMenuDemo) delete_developers() {
	app.status = 'Delete all developers selected.'
}

pub fn (mut app ResizableMenuDemo) delete_users() {
	app.status = 'Delete users selected.'
}

pub fn (mut app ResizableMenuDemo) export_users() {
	app.status = 'Export users selected.'
}

pub fn (mut app ResizableMenuDemo) exit_selected() {
	app.status = 'Exit selected.'
}

pub fn (mut app ResizableMenuDemo) add_user() {
	app.status = 'Add user selected.'
}

fn main() {
	mut app := ResizableMenuDemo{}
	ui2.run_compiled_vml[ResizableMenuDemo](
		build:  build_resizable_menu_window
		model:  &app
		title:  'Resizable Menu Window'
		width:  menu_window_width
		height: menu_window_height
	) or { panic(err) }
}

fn build_resizable_menu_window(mut app ResizableMenuDemo) ui2.Element {
	return $vml('resizable_menu_window.vml')
}

fn resizable_menu_window_tree(mut app ResizableMenuDemo, frame ui2.Rect) ui2.Element {
	return $vml('resizable_menu_window.vml', frame)
}
